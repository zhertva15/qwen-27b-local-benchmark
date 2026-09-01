. (Join-Path $PSScriptRoot 'Common.ps1')
Set-StrictMode -Off
$paths = Get-BenchmarkPaths
$attemptRoot = Join-Path $paths.Results 'attempts'
$rows = [Collections.Generic.List[object]]::new()
if (-not (Test-Path -LiteralPath $attemptRoot)) { exit 0 }

foreach ($metadataFile in Get-ChildItem -LiteralPath $attemptRoot -Filter 'attempt.json' -Recurse | Sort-Object FullName) {
    try {
        $attempt = Get-Content -LiteralPath $metadataFile.FullName -Raw | ConvertFrom-Json
        $resolved = $false
        if ($attempt.summaryReportPath -and (Test-Path -LiteralPath $attempt.summaryReportPath)) {
            $summary = Get-Content -LiteralPath $attempt.summaryReportPath -Raw | ConvertFrom-Json
            $resolved = $summary.resolved_ids -contains $attempt.task
        }

        $exitStatus = ''
        $apiSteps = 0
        $formatErrors = 0
        $testCommands = 0
        $promptTokens = 0
        $outputTokens = 0
        $reasoningTokens = 0
        $trajectoryText = ''
        if ($attempt.trajectoryPath -and (Test-Path -LiteralPath $attempt.trajectoryPath)) {
            $trajectoryText = Get-Content -LiteralPath $attempt.trajectoryPath -Raw
            $trajectory = $trajectoryText | ConvertFrom-Json
            $exitStatus = [string]$trajectory.info.exit_status
            if ($trajectory.info.model_stats.api_calls) { $apiSteps = [int]$trajectory.info.model_stats.api_calls }
            foreach ($message in @($trajectory.messages)) {
                $content = [string]$message.content
                if ($content -match '(?i)format error:|RepeatedFormatError') { $formatErrors++ }
                if ($null -ne $message.extra) {
                    foreach ($action in @($message.extra.actions)) {
                        if ($null -ne $action -and [string]$action.command -match '(?i)(pytest|tox|nox|manage\.py\s+test|python\s+-m\s+pytest|make\s+test)') { $testCommands++ }
                    }
                    $usage = $message.extra.response.usage
                    if ($null -ne $usage) {
                        if ($usage.prompt_tokens) { $promptTokens += [int]$usage.prompt_tokens }
                        if ($usage.completion_tokens) { $outputTokens += [int]$usage.completion_tokens }
                        if ($usage.completion_tokens_details.reasoning_tokens) { $reasoningTokens += [int]$usage.completion_tokens_details.reasoning_tokens }
                    }
                }
            }
        }

        $patchLines = 0
        if ($attempt.patchPath -and (Test-Path -LiteralPath $attempt.patchPath)) {
            $patchLines = @(Get-Content -LiteralPath $attempt.patchPath | Where-Object { ($_ -match '^[+-]') -and ($_ -notmatch '^(---|\+\+\+)') }).Count
        }

        $patchApplied = $false
        $f2pPassed = 0
        $f2pTotal = 0
        $p2pPassed = 0
        $p2pTotal = 0
        if ($attempt.instanceReportPath -and (Test-Path -LiteralPath $attempt.instanceReportPath)) {
            $instanceWrapper = Get-Content -LiteralPath $attempt.instanceReportPath -Raw | ConvertFrom-Json
            $instance = $instanceWrapper.PSObject.Properties[$attempt.task].Value
            if ($null -ne $instance) {
                $patchApplied = [bool]$instance.patch_successfully_applied
                $f2pPassed = @($instance.tests_status.FAIL_TO_PASS.success).Count
                $f2pTotal = $f2pPassed + @($instance.tests_status.FAIL_TO_PASS.failure).Count
                $p2pPassed = @($instance.tests_status.PASS_TO_PASS.success).Count
                $p2pTotal = $p2pPassed + @($instance.tests_status.PASS_TO_PASS.failure).Count
            }
        }

        $peakVram = 0
        $peakRam = 0.0
        if ($attempt.resourceLogPath -and (Test-Path -LiteralPath $attempt.resourceLogPath)) {
            $samples = Import-Csv -LiteralPath $attempt.resourceLogPath
            if ($samples) {
                $peakVram = [int](($samples | Measure-Object -Property vram_used_mib -Maximum).Maximum)
                $peakRam = [double](($samples | Where-Object server_working_set_gib | Measure-Object -Property server_working_set_gib -Maximum).Maximum)
            }
        }
        if ($peakVram -eq 0 -and $attempt.server.loadedGpu.usedMiB) { $peakVram = [int]$attempt.server.loadedGpu.usedMiB }
        if ($peakRam -eq 0 -and $attempt.server.workingSetGiB) { $peakRam = [double]$attempt.server.workingSetGiB }

        $allText = $trajectoryText
        foreach ($logPath in @($attempt.agentProcess.stderr, $attempt.evaluatorProcess.stderr, $attempt.server.stderrLog)) {
            if ($logPath -and (Test-Path -LiteralPath $logPath)) { $allText += "`n" + (Get-Content -LiteralPath $logPath -Raw) }
        }
        $oom = $allText -match '(?i)out of memory|cuda.*oom|failed to allocate.*(cuda|vram)'
        $timedOut = [bool]$attempt.agentProcess.timedOut -or [bool]$attempt.evaluatorProcess.timedOut -or $exitStatus -in @('TimeExceeded', 'LimitsExceeded')

        $rows.Add([pscustomobject][ordered]@{
            block = [int]$attempt.block
            model = [string]$attempt.model
            seed = [int]$attempt.seed
            task = [string]$attempt.task
            started_utc = [string]$attempt.startedUtc
            agent_seconds = [double]$attempt.agentSeconds
            evaluator_seconds = [double]$attempt.evaluatorSeconds
            total_wall_seconds = [double]$attempt.totalWallSeconds
            cold_load_seconds = [double]$attempt.server.loadSeconds
            resolved = $resolved
            exit_status = $exitStatus
            api_bash_steps = $apiSteps
            format_errors = $formatErrors
            test_commands = $testCommands
            prompt_tokens = $promptTokens
            output_tokens = $outputTokens
            reasoning_tokens = $reasoningTokens
            patch_lines = $patchLines
            patch_applied = $patchApplied
            f2p_passed = $f2pPassed
            f2p_total = $f2pTotal
            p2p_passed = $p2pPassed
            p2p_total = $p2pTotal
            regressions = $p2pTotal - $p2pPassed
            oom = $oom
            timeout = $timedOut
            loaded_vram_mib = if ($attempt.server.loadedGpu.usedMiB) { [int]$attempt.server.loadedGpu.usedMiB } else { 0 }
            peak_vram_mib = $peakVram
            peak_ram_gib = [math]::Round($peakRam, 3)
            offloaded_layers = [string]$attempt.server.offloadedLayers
            report_path = [string]$attempt.instanceReportPath
            trajectory_path = [string]$attempt.trajectoryPath
            patch_path = [string]$attempt.patchPath
        })
    } catch {
        Write-Warning "Could not collect $($metadataFile.FullName): $($_.Exception.Message)"
    }
}

$csvPath = Join-Path $paths.Results 'attempts.csv'
$rows | Sort-Object block, task | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
Write-Host "Collected $($rows.Count) attempts into $csvPath"
