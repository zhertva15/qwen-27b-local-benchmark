param(
    [switch]$SkipSmoke
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$paths = Get-BenchmarkPaths
$plan = Get-RunPlan
$tasksConfig = Get-TaskConfiguration
$selectedPath = Join-Path $paths.State 'selected-tasks.json'
if (-not (Test-Path -LiteralPath $selectedPath)) {
    throw 'Gold preflight is missing. Run Prepare-GoldPreflight.ps1 first.'
}
if (-not $SkipSmoke -and -not (Test-Path -LiteralPath (Join-Path $paths.Results 'smoke-summary.json'))) {
    & (Join-Path $PSScriptRoot 'Run-Smoke.ps1')
}
Wait-DockerReady
$selected = Get-Content -LiteralPath $selectedPath -Raw | ConvertFrom-Json
$taskIds = @($selected.tasks)
if ($taskIds.Count -ne 4) { throw "Expected exactly four selected tasks, found $($taskIds.Count)." }

$runStatePath = Join-Path $paths.State 'benchmark-state.json'
if (Test-Path -LiteralPath $runStatePath) {
    $runState = Get-Content -LiteralPath $runStatePath -Raw | ConvertFrom-Json
} else {
    $runState = [pscustomobject]@{
        startedUtc = [DateTime]::UtcNow.ToString('o')
        accumulatedSeconds = 0.0
        completedAttempts = 0
        status = 'running'
    }
}

foreach ($block in $plan.blocks) {
    if ([double]$runState.accumulatedSeconds -ge [double]$plan.suiteWallTimeSeconds) {
        $runState.status = 'time-limit-reached'
        $runState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $runStatePath -Encoding utf8
        throw 'The six-hour suite limit has been reached. Existing results are preserved.'
    }
    $server = $null
    try {
        $logTag = ('block-{0:d2}-{1}-seed{2}' -f [int]$block.ordinal, $block.model, $block.seed)
        Write-Host "Starting $logTag"
        $server = Start-BenchmarkModel -ModelId $block.model -Seed $block.seed -LogTag $logTag
        $runState.accumulatedSeconds = [math]::Round([double]$runState.accumulatedSeconds + [double]$server.loadSeconds, 3)
        foreach ($taskId in $taskIds) {
            $attemptId = ('b{0:d2}--{1}--seed{2}--{3}' -f [int]$block.ordinal, $block.model, $block.seed, $taskId.Replace('__', '--'))
            $attemptDir = Join-Path $paths.Results "attempts\$attemptId"
            $metadataPath = Join-Path $attemptDir 'attempt.json'
            if (Test-Path -LiteralPath $metadataPath) {
                Write-Host "Skipping completed attempt $attemptId"
                continue
            }
            New-Item -ItemType Directory -Path $attemptDir -Force | Out-Null
            Clear-ModelPromptCache
            $beforeGpu = Get-GpuSnapshot
            $startedUtc = [DateTime]::UtcNow
            $totalWatch = [Diagnostics.Stopwatch]::StartNew()
            $resourceLogPath = Join-Path $attemptDir 'resources.csv'
            $monitorStopPath = Join-Path $attemptDir 'resources.stop'
            Remove-Item -LiteralPath $monitorStopPath -Force -ErrorAction SilentlyContinue
            $monitor = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $PSScriptRoot 'Monitor-Resources.ps1'),
                '-OutputPath', $resourceLogPath, '-StopFile', $monitorStopPath, '-ServerPid', [string]$server.processId
            ) -PassThru -WindowStyle Hidden

            $agentDir = Join-Path $attemptDir 'agent'
            $agentLogs = Join-Path $attemptDir 'launcher-logs\agent'
            $filter = '^(' + [regex]::Escape($taskId) + ')$'
            $agentArguments = @(
                'swebench',
                '--subset', 'verified',
                '--split', 'test',
                '--filter', $filter,
                '--output', $agentDir,
                '--workers', '1',
                '--redo-existing',
                '-c', 'swebench_backticks.yaml',
                '-c', (Join-Path $paths.Config 'agent-limits.yaml'),
                '-c', (Join-Path $paths.Config "models\$($block.model).yaml"),
                '-c', (Join-Path $paths.Config "seeds\seed-$($block.seed).yaml")
            )
            Write-Host "Attempt $attemptId"
            $agentRun = Invoke-LoggedProcess -FilePath $paths.MiniExtra -ArgumentList $agentArguments -WorkingDirectory $paths.Root -StdoutPath (Join-Path $agentLogs 'stdout.log') -StderrPath (Join-Path $agentLogs 'stderr.log') -TimeoutSeconds ($plan.agentWallTimeSeconds + 60)

            $predictionsPath = Join-Path $agentDir 'preds.json'
            $patchPath = Join-Path $attemptDir 'model.patch'
            $patch = ''
            if (Test-Path -LiteralPath $predictionsPath) {
                $predictions = Get-Content -LiteralPath $predictionsPath -Raw | ConvertFrom-Json
                $predictionProperty = $predictions.PSObject.Properties[$taskId]
                $prediction = if ($null -ne $predictionProperty) { $predictionProperty.Value } else { $null }
                if ($null -ne $prediction -and $null -ne $prediction.model_patch) { $patch = [string]$prediction.model_patch }
            }
            $patch | Set-Content -LiteralPath $patchPath -Encoding utf8

            $evaluatorRun = [pscustomobject]@{ exitCode = -1; timedOut = $false; seconds = 0.0; stdout = ''; stderr = '' }
            $summaryPath = ''
            if (Test-Path -LiteralPath $predictionsPath) {
                $reportDir = Join-Path $attemptDir 'evaluator-reports'
                $evaluatorLogs = Join-Path $attemptDir 'launcher-logs\evaluator'
                New-Item -ItemType Directory -Path $reportDir, $evaluatorLogs -Force | Out-Null
                $runId = $attemptId
                $evalArguments = @(
                    '-m', 'swebench.harness.run_evaluation',
                    '--dataset_name', $tasksConfig.dataset,
                    '--split', $tasksConfig.split,
                    '--instance_ids', $taskId,
                    '--predictions_path', $predictionsPath,
                    '--max_workers', '1',
                    '--timeout', [string]$plan.evaluatorTimeoutSeconds,
                    '--run_id', $runId,
                    '--report_dir', $reportDir
                )
                $evaluatorRun = Invoke-LoggedProcess -FilePath $paths.Python -ArgumentList $evalArguments -WorkingDirectory $attemptDir -StdoutPath (Join-Path $evaluatorLogs 'stdout.log') -StderrPath (Join-Path $evaluatorLogs 'stderr.log') -TimeoutSeconds ($plan.evaluatorTimeoutSeconds + 30)
                $summary = Get-ChildItem -LiteralPath $reportDir -Filter '*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -ne $summary) { $summaryPath = $summary.FullName }
            }

            $totalWatch.Stop()
            New-Item -ItemType File -Path $monitorStopPath -Force | Out-Null
            $monitor.WaitForExit(5000) | Out-Null
            if (-not $monitor.HasExited) { Stop-Process -Id $monitor.Id -Force }
            Remove-Item -LiteralPath $monitorStopPath -Force -ErrorAction SilentlyContinue
            $trajectory = Get-ChildItem -LiteralPath $agentDir -Filter '*.traj.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            $instanceReport = Get-ChildItem -LiteralPath (Join-Path $attemptDir 'logs') -Filter 'report.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            $serverProcess = Get-Process -Id $server.processId -ErrorAction SilentlyContinue
            $attempt = [pscustomobject]@{
                schemaVersion = 1
                attemptId = $attemptId
                block = [int]$block.ordinal
                model = $block.model
                seed = [int]$block.seed
                task = $taskId
                startedUtc = $startedUtc.ToString('o')
                finishedUtc = [DateTime]::UtcNow.ToString('o')
                agentSeconds = $agentRun.seconds
                evaluatorSeconds = $evaluatorRun.seconds
                totalWallSeconds = [math]::Round($totalWatch.Elapsed.TotalSeconds, 3)
                agentProcess = $agentRun
                evaluatorProcess = $evaluatorRun
                beforeGpu = $beforeGpu
                afterGpu = Get-GpuSnapshot
                server = [pscustomobject]@{
                    loadSeconds = $server.loadSeconds
                    loadedGpu = $server.loadedGpu
                    workingSetGiB = if ($null -ne $serverProcess) { [math]::Round($serverProcess.WorkingSet64 / 1GB, 3) } else { $null }
                    offloadedLayers = $server.offloadedLayers
                    stderrLog = $server.stderrLog
                }
                trajectoryPath = if ($null -ne $trajectory) { $trajectory.FullName } else { '' }
                predictionsPath = $predictionsPath
                patchPath = $patchPath
                summaryReportPath = $summaryPath
                instanceReportPath = if ($null -ne $instanceReport) { $instanceReport.FullName } else { '' }
                resourceLogPath = $resourceLogPath
            }
            $attempt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $metadataPath -Encoding utf8
            $runState.completedAttempts = [int]$runState.completedAttempts + 1
            $runState.accumulatedSeconds = [math]::Round([double]$runState.accumulatedSeconds + $totalWatch.Elapsed.TotalSeconds, 3)
            $runState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $runStatePath -Encoding utf8
            & (Join-Path $PSScriptRoot 'Collect-Results.ps1')
        }
    } finally {
        Stop-BenchmarkModel -ServerState $server
        $runState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $runStatePath -Encoding utf8
    }
}

$runState.status = 'complete'
$runState.finishedUtc = [DateTime]::UtcNow.ToString('o')
$runState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $runStatePath -Encoding utf8
& (Join-Path $PSScriptRoot 'Collect-Results.ps1')
& (Join-Path $PSScriptRoot 'Build-Report.ps1')
& (Join-Path $PSScriptRoot 'Create-Archive.ps1')
Write-Host "Benchmark complete. Report: $(Join-Path $paths.Root 'REPORT.md')"
