. (Join-Path $PSScriptRoot 'Common.ps1')
$paths = Get-BenchmarkPaths
$tasks = Get-TaskConfiguration
$plan = Get-RunPlan

if (Test-PendingReboot) {
    throw 'Windows has a pending restart after enabling WSL/VirtualMachinePlatform. Restart Windows, then run this script again.'
}
Wait-DockerReady
& (Join-Path $PSScriptRoot 'Download-DirectModel.ps1')

New-Item -ItemType Directory -Path $paths.Results, $paths.State, $paths.Logs -Force | Out-Null

Write-Host 'Caching SWE-bench Verified metadata...'
$datasetWarmup = "from datasets import load_dataset; load_dataset('princeton-nlp/SWE-Bench_Verified', split='test')"
& $paths.Python -c $datasetWarmup
if ($LASTEXITCODE -ne 0) { throw 'Could not cache SWE-bench Verified metadata.' }

$allTasks = @($tasks.primary) + @($tasks.fallbacks.django) + @($tasks.fallbacks.'pytest-dev')
$docker = Get-DockerExecutable
foreach ($taskId in $allTasks) {
    $dockerId = $taskId.ToLowerInvariant().Replace('__', '_1776_')
    $image = "docker.io/swebench/sweb.eval.x86_64.$dockerId`:latest"
    Write-Host "Preloading $image"
    & $docker pull $image
    if ($LASTEXITCODE -ne 0) { throw "Docker image pull failed: $image" }
}

function Invoke-GoldEvaluation {
    param([Parameter(Mandatory)][string]$TaskId)

    $safe = $TaskId.Replace('__', '--')
    $attemptDir = Join-Path $paths.Results "preflight\$safe"
    $reportDir = Join-Path $attemptDir 'reports'
    $logDir = Join-Path $attemptDir 'launcher-logs'
    New-Item -ItemType Directory -Path $reportDir, $logDir -Force | Out-Null
    $runId = "gold-$safe"
    $arguments = @(
        '-m', 'swebench.harness.run_evaluation',
        '--dataset_name', $tasks.dataset,
        '--split', $tasks.split,
        '--instance_ids', $TaskId,
        '--predictions_path', 'gold',
        '--max_workers', '1',
        '--timeout', [string]$plan.evaluatorTimeoutSeconds,
        '--run_id', $runId,
        '--report_dir', $reportDir
    )
    $result = Invoke-LoggedProcess -FilePath $paths.Python -ArgumentList $arguments -WorkingDirectory $attemptDir -StdoutPath (Join-Path $logDir 'stdout.log') -StderrPath (Join-Path $logDir 'stderr.log') -TimeoutSeconds ($plan.evaluatorTimeoutSeconds + 60)
    $reportPath = Join-Path $reportDir "gold.$runId.json"
    $resolved = $false
    if (Test-Path -LiteralPath $reportPath) {
        $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        $resolved = $report.resolved_ids -contains $TaskId
    }
    return [pscustomobject]@{
        task = $TaskId
        resolved = $resolved
        exitCode = $result.exitCode
        timedOut = $result.timedOut
        seconds = $result.seconds
        reportPath = $reportPath
    }
}

$selected = [Collections.Generic.List[string]]::new()
$preflight = [Collections.Generic.List[object]]::new()
foreach ($taskId in $tasks.primary) {
    Write-Host "Gold preflight: $taskId"
    $result = Invoke-GoldEvaluation -TaskId $taskId
    $preflight.Add($result)
    if ($result.resolved) {
        $selected.Add($taskId)
        continue
    }

    $repoKey = if ($taskId.StartsWith('django__')) { 'django' } else { 'pytest-dev' }
    $replacement = @($tasks.fallbacks.$repoKey) | Where-Object { -not $selected.Contains($_) } | Select-Object -First 1
    if (-not $replacement) { throw "Gold patch failed for $taskId and no unused $repoKey fallback remains." }
    Write-Warning "Gold patch failed for $taskId. Trying fallback $replacement."
    $replacementResult = Invoke-GoldEvaluation -TaskId $replacement
    $preflight.Add($replacementResult)
    if (-not $replacementResult.resolved) { throw "Gold patch also failed for fallback $replacement." }
    $selected.Add($replacement)
}

$selectedState = [pscustomobject]@{
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    tasks = @($selected)
    source = 'official SWE-bench evaluator gold predictions'
}
$selectedState | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $paths.State 'selected-tasks.json') -Encoding utf8
$preflight | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $paths.Results 'gold-preflight.json') -Encoding utf8
Write-Host "Gold preflight passed. Fixed task order: $($selected -join ', ')"

