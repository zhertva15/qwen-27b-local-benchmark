. (Join-Path $PSScriptRoot 'Common.ps1')
$paths = Get-BenchmarkPaths
$selectedPath = Join-Path $paths.State 'selected-tasks.json'
if (-not (Test-Path -LiteralPath $selectedPath)) {
    throw 'Gold preflight has not run. Run Prepare-GoldPreflight.ps1 first.'
}
Wait-DockerReady
$selected = Get-Content -LiteralPath $selectedPath -Raw | ConvertFrom-Json
$smokeTask = @($selected.tasks | Where-Object { $_ -like 'pytest-dev__*' } | Select-Object -First 1)[0]
if (-not $smokeTask) { $smokeTask = $selected.tasks[0] }
$models = @('lowgpu-iq3xxxs', 'fp8-q4-k-m', 'direct-iq4-xs')
$summaries = [Collections.Generic.List[object]]::new()

foreach ($modelId in $models) {
    $server = $null
    try {
        Write-Host "Smoke-test: $modelId"
        $server = Start-BenchmarkModel -ModelId $modelId -Seed 101 -LogTag "smoke-$modelId"
        Clear-ModelPromptCache
        $outputDir = Join-Path $paths.Results "smoke\$modelId"
        $launcherLogs = Join-Path $outputDir 'launcher-logs'
        New-Item -ItemType Directory -Path $launcherLogs -Force | Out-Null
        $filter = '^(' + [regex]::Escape($smokeTask) + ')$'
        $arguments = @(
            'swebench',
            '--subset', 'verified',
            '--split', 'test',
            '--filter', $filter,
            '--output', $outputDir,
            '--workers', '1',
            '--redo-existing',
            '-c', 'swebench_backticks.yaml',
            '-c', (Join-Path $paths.Config 'agent-limits.yaml'),
            '-c', (Join-Path $paths.Config 'smoke-limits.yaml'),
            '-c', (Join-Path $paths.Config "models\$modelId.yaml"),
            '-c', (Join-Path $paths.Config 'seeds\seed-101.yaml')
        )
        $run = Invoke-LoggedProcess -FilePath $paths.MiniExtra -ArgumentList $arguments -WorkingDirectory $paths.Root -StdoutPath (Join-Path $launcherLogs 'stdout.log') -StderrPath (Join-Path $launcherLogs 'stderr.log') -TimeoutSeconds 300
        $trajectoryPath = Get-ChildItem -LiteralPath $outputDir -Filter '*.traj.json' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        $predictionsPath = Join-Path $outputDir 'preds.json'
        $bashSteps = 0
        $exitStatus = ''
        $hasOom = $false
        if ($trajectoryPath) {
            $trajectory = Get-Content -LiteralPath $trajectoryPath -Raw | ConvertFrom-Json
            $bashSteps = @($trajectory.messages | ForEach-Object { @($_.extra.actions).Count } | Measure-Object -Sum).Sum
            $exitStatus = $trajectory.info.exit_status
            $hasOom = (Get-Content -LiteralPath $trajectoryPath -Raw) -match '(?i)out of memory|cuda.*oom'
        }
        $patchBytes = 0
        if (Test-Path -LiteralPath $predictionsPath) {
            $predictions = Get-Content -LiteralPath $predictionsPath -Raw | ConvertFrom-Json
            $predictionProperty = $predictions.PSObject.Properties[$smokeTask]
            $prediction = if ($null -ne $predictionProperty) { $predictionProperty.Value } else { $null }
            if ($null -ne $prediction -and $null -ne $prediction.model_patch) {
                $patchBytes = [Text.Encoding]::UTF8.GetByteCount([string]$prediction.model_patch)
            }
        }
        $passed = ($run.exitCode -eq 0 -and $bashSteps -gt 0 -and -not $hasOom)
        $summaries.Add([pscustomobject]@{
            model = $modelId
            task = $smokeTask
            passed = $passed
            apiAndBashSteps = $bashSteps
            patchBytes = $patchBytes
            exitStatus = $exitStatus
            oom = $hasOom
            seconds = $run.seconds
            loadSeconds = $server.loadSeconds
            trajectoryPath = $trajectoryPath
        })
        if (-not $passed) { throw "Smoke-test failed for $modelId. See $launcherLogs" }
    } finally {
        Stop-BenchmarkModel -ServerState $server
    }
}

$summaryPath = Join-Path $paths.Results 'smoke-summary.json'
$summaries | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $summaryPath -Encoding utf8
Write-Host "All model smoke-tests passed. Summary: $summaryPath"
