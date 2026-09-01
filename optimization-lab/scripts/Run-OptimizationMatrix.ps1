param(
    [string[]]$OnlyModel,
    [string[]]$OnlyProfile,
    [int]$Port = 8090
)

$ErrorActionPreference = 'Stop'

$labRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $labRoot 'config\matrix.json'
$codingPromptPath = Join-Path $labRoot 'prompts\coding.txt'
$refactorPromptPath = Join-Path $labRoot 'prompts\refactor-copy.txt'
$rawDirectory = Join-Path $labRoot 'results\raw'
$summaryPath = Join-Path $labRoot 'results\summary.csv'
$serverLogDirectory = Join-Path $labRoot 'logs\server'

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$codingPrompt = Get-Content -LiteralPath $codingPromptPath -Raw
$refactorPrompt = Get-Content -LiteralPath $refactorPromptPath -Raw
$refactorSource = $refactorPrompt.Substring($refactorPrompt.IndexOf('from dataclasses'))
$expectedRefactor = $refactorSource.Replace('    result = {', '    payload = {').Replace('    return result', '    return payload')
$headers = @{ Authorization = "Bearer $($config.apiKey)" }

$selectedModels = @($OnlyModel | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$selectedProfiles = @($OnlyProfile | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

New-Item -ItemType Directory -Path $rawDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $serverLogDirectory -Force | Out-Null

if (-not (Test-Path -LiteralPath $config.serverPath)) {
    throw "llama-server not found: $($config.serverPath)"
}

$existingServers = @(Get-Process llama-server -ErrorAction SilentlyContinue)
if ($existingServers.Count -gt 0) {
    throw "Another llama-server is already running (PID: $($existingServers.Id -join ', ')). Stop it before running the matrix."
}

function Get-GpuSnapshot {
    $line = (& nvidia-smi --query-gpu=memory.used,memory.free,utilization.gpu --format=csv,noheader,nounits).Trim()
    $parts = $line -split ',' | ForEach-Object { [int]$_.Trim() }
    return [pscustomobject]@{
        UsedMiB = $parts[0]
        FreeMiB = $parts[1]
        UtilizationPercent = $parts[2]
    }
}

function ConvertTo-CleanCode {
    param([string]$Text)

    $lf = [string][char]10
    $crlf = ([string][char]13) + [char]10
    $clean = [regex]::Replace($Text, '(?s)^\s*<think>.*?</think>\s*', '')
    $clean = [regex]::Replace($clean, '(?m)^\s*```(?:python)?\s*$', '')
    return $clean.Replace($crlf, $lf).Trim()
}

function Wait-ServerReady {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 240
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Process.HasExited) {
            throw "llama-server exited during model loading with code $($Process.ExitCode)"
        }
        try {
            $null = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -Headers $headers -TimeoutSec 2
            return
        } catch {
            Start-Sleep -Milliseconds 500
        }
    }
    throw "llama-server did not become ready within $TimeoutSeconds seconds"
}

function Invoke-ChatCompletion {
    param(
        [string]$ModelId,
        [string]$Prompt,
        [int]$MaxTokens
    )

    $body = @{
        model = $ModelId
        messages = @(@{ role = 'user'; content = $Prompt })
        temperature = 0
        max_tokens = $MaxTokens
        chat_template_kwargs = @{ enable_thinking = $false }
    } | ConvertTo-Json -Depth 10

    return Invoke-RestMethod `
        -Uri "http://127.0.0.1:$Port/v1/chat/completions" `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 300
}

function Invoke-ToolFlow {
    param([string]$ModelId)

    $toolDefinition = @{
        type = 'function'
        function = @{
            name = 'read_file'
            description = 'Read a UTF-8 text file'
            parameters = @{
                type = 'object'
                properties = @{ path = @{ type = 'string' } }
                required = @('path')
            }
        }
    }
    $prompt = 'Read C:\work\sample.py with the available tool, then summarize the file in one sentence.'
    $firstBody = @{
        model = $ModelId
        messages = @(@{ role = 'user'; content = $prompt })
        tools = @($toolDefinition)
        tool_choice = 'auto'
        temperature = 0
        max_tokens = 128
        chat_template_kwargs = @{ enable_thinking = $false }
    } | ConvertTo-Json -Depth 15

    $first = Invoke-RestMethod `
        -Uri "http://127.0.0.1:$Port/v1/chat/completions" `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $firstBody `
        -TimeoutSec 120

    $call = $first.choices[0].message.tool_calls[0]
    if ($null -eq $call -or $call.function.name -ne 'read_file') {
        return [ordered]@{
            passed = $false
            toolName = $call.function.name
            arguments = $call.function.arguments
            final = $null
        }
    }

    $secondBody = @{
        model = $ModelId
        messages = @(
            @{ role = 'user'; content = $prompt },
            @{ role = 'assistant'; content = $null; tool_calls = @($call) },
            @{ role = 'tool'; tool_call_id = $call.id; content = "def add(a, b):`n    return a + b`n" }
        )
        tools = @($toolDefinition)
        temperature = 0
        max_tokens = 128
        chat_template_kwargs = @{ enable_thinking = $false }
    } | ConvertTo-Json -Depth 18

    $second = Invoke-RestMethod `
        -Uri "http://127.0.0.1:$Port/v1/chat/completions" `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json' `
        -Body $secondBody `
        -TimeoutSec 120

    $final = [string]$second.choices[0].message.content
    return [ordered]@{
        passed = ($final -match 'add' -and $final -match 'sum')
        toolName = $call.function.name
        arguments = $call.function.arguments
        final = $final
        generationTps = [math]::Round([double]$second.timings.predicted_per_second, 2)
    }
}

function Get-CompletionMetrics {
    param($Response)

    $content = [string]$Response.choices[0].message.content
    $drafted = if ($null -eq $Response.timings.draft_n) { 0 } else { [int]$Response.timings.draft_n }
    $accepted = if ($null -eq $Response.timings.draft_n_accepted) { 0 } else { [int]$Response.timings.draft_n_accepted }
    return [ordered]@{
        promptTokens = [int]$Response.timings.prompt_n
        promptTps = [math]::Round([double]$Response.timings.prompt_per_second, 2)
        generatedTokens = [int]$Response.timings.predicted_n
        generationTps = [math]::Round([double]$Response.timings.predicted_per_second, 2)
        draftedTokens = $drafted
        acceptedDraftTokens = $accepted
        acceptancePercent = if ($drafted -gt 0) { [math]::Round(100 * $accepted / $drafted, 1) } else { 0 }
        finishReason = $Response.choices[0].finish_reason
        content = $content
    }
}

$summary = [System.Collections.Generic.List[object]]::new()
$models = @($config.models | Where-Object { $selectedModels.Count -eq 0 -or $_.id -in $selectedModels })
$profiles = @($config.profiles | Where-Object { $selectedProfiles.Count -eq 0 -or $_.id -in $selectedProfiles })

foreach ($model in $models) {
    if (-not (Test-Path -LiteralPath $model.path)) {
        throw "Model not found: $($model.path)"
    }

    foreach ($profile in $profiles) {
        if ($profile.requiresMtp -and -not $model.supportsMtp) {
            continue
        }

        $caseId = "$($model.id)--$($profile.id)"
        $stdoutPath = Join-Path $serverLogDirectory "$caseId.stdout.log"
        $stderrPath = Join-Path $serverLogDirectory "$caseId.stderr.log"
        $resultPath = Join-Path $rawDirectory "$caseId.json"
        $serverProcess = $null
        $loadWatch = [System.Diagnostics.Stopwatch]::StartNew()

        $serverArgs = @(
            '--model', $model.path,
            '--alias', $model.id,
            '--host', '127.0.0.1',
            '--port', [string]$Port,
            '--api-key', $config.apiKey,
            '--ctx-size', [string]$config.contextSize,
            '--parallel', '1',
            '--flash-attn', 'on',
            '--threads', '8',
            '--threads-batch', '16',
            '--jinja',
            '--reasoning-format', 'none',
            '-lv', '4'
        )

        if ($profile.optimizedMemory) {
            $serverArgs += @(
                '--cache-type-k', 'q4_0',
                '--cache-type-v', 'q4_0',
                '--batch-size', '512',
                '--ubatch-size', '128'
            )
            if ($model.forceFullGpu) {
                $serverArgs += @('--fit', 'off', '--n-gpu-layers', '999')
            } else {
                $serverArgs += @('--fit', 'on', '--fit-target', '512', '--fit-ctx', [string]$config.contextSize)
            }
        } else {
            $serverArgs += @(
                '--cache-type-k', 'q8_0',
                '--cache-type-v', 'q8_0',
                '--batch-size', '1024',
                '--ubatch-size', '512',
                '--fit', 'on',
                '--fit-target', [string]$model.baselineFitTarget,
                '--fit-ctx', '8192'
            )
        }

        if ($profile.speculation -eq 'ngram-simple') {
            $serverArgs += @('--spec-type', 'ngram-simple')
        } elseif ($profile.speculation -eq 'draft-mtp') {
            $serverArgs += @('--spec-type', 'draft-mtp', '--spec-draft-n-max', '2')
        }

        Write-Host "[$caseId] loading..."
        try {
            $serverProcess = Start-Process `
                -FilePath $config.serverPath `
                -ArgumentList $serverArgs `
                -PassThru `
                -WindowStyle Hidden `
                -RedirectStandardOutput $stdoutPath `
                -RedirectStandardError $stderrPath

            Wait-ServerReady -Process $serverProcess
            $loadWatch.Stop()
            $loadedGpu = Get-GpuSnapshot
            $peakVram = $loadedGpu.UsedMiB

            $codingResponse = Invoke-ChatCompletion -ModelId $model.id -Prompt $codingPrompt -MaxTokens 384
            $coding = Get-CompletionMetrics -Response $codingResponse
            $peakVram = [math]::Max($peakVram, (Get-GpuSnapshot).UsedMiB)

            $refactorResponse = Invoke-ChatCompletion -ModelId $model.id -Prompt $refactorPrompt -MaxTokens 1024
            $refactor = Get-CompletionMetrics -Response $refactorResponse
            $refactor.staticEditCheck = ($refactor.content -match 'payload\s*=' -and $refactor.content -notmatch 'result\s*=')
            $refactor.exactMatch = ((ConvertTo-CleanCode -Text $refactor.content) -ceq (ConvertTo-CleanCode -Text $expectedRefactor))
            $peakVram = [math]::Max($peakVram, (Get-GpuSnapshot).UsedMiB)

            $tool = Invoke-ToolFlow -ModelId $model.id
            $peakVram = [math]::Max($peakVram, (Get-GpuSnapshot).UsedMiB)
            $processInfo = Get-Process -Id $serverProcess.Id

            $result = [ordered]@{
                caseId = $caseId
                status = 'ok'
                timestamp = [DateTime]::UtcNow.ToString('o')
                modelId = $model.id
                modelName = $model.displayName
                profileId = $profile.id
                profileName = $profile.displayName
                modelPath = $model.path
                serverArguments = $serverArgs
                loadSeconds = [math]::Round($loadWatch.Elapsed.TotalSeconds, 2)
                loadedVramMiB = $loadedGpu.UsedMiB
                freeVramMiB = $loadedGpu.FreeMiB
                peakVramMiB = $peakVram
                processWorkingSetGiB = [math]::Round($processInfo.WorkingSet64 / 1GB, 2)
                coding = $coding
                refactor = $refactor
                toolFlow = $tool
                logs = @{ stdout = $stdoutPath; stderr = $stderrPath }
            }

            $summary.Add([pscustomobject]@{
                Model = $model.displayName
                ModelId = $model.id
                Profile = $profile.displayName
                ProfileId = $profile.id
                Status = 'ok'
                LoadSeconds = $result.loadSeconds
                LoadedVramMiB = $result.loadedVramMiB
                PeakVramMiB = $result.peakVramMiB
                CodingPromptTps = $coding.promptTps
                CodingGenerationTps = $coding.generationTps
                RefactorPromptTps = $refactor.promptTps
                RefactorGenerationTps = $refactor.generationTps
                RefactorDrafted = $refactor.draftedTokens
                RefactorAccepted = $refactor.acceptedDraftTokens
                RefactorAcceptancePercent = $refactor.acceptancePercent
                RefactorStaticCheck = $refactor.staticEditCheck
                RefactorExactMatch = $refactor.exactMatch
                ToolFlowPassed = $tool.passed
            })
            Write-Host "[$caseId] coding $($coding.generationTps) tok/s, refactor $($refactor.generationTps) tok/s"
        } catch {
            $loadWatch.Stop()
            $errorResult = [ordered]@{
                caseId = $caseId
                status = 'failed'
                timestamp = [DateTime]::UtcNow.ToString('o')
                modelId = $model.id
                modelName = $model.displayName
                profileId = $profile.id
                profileName = $profile.displayName
                serverArguments = $serverArgs
                loadSeconds = [math]::Round($loadWatch.Elapsed.TotalSeconds, 2)
                error = $_.Exception.Message
                logs = @{ stdout = $stdoutPath; stderr = $stderrPath }
            }
            $result = $errorResult
            $summary.Add([pscustomobject]@{
                Model = $model.displayName
                ModelId = $model.id
                Profile = $profile.displayName
                ProfileId = $profile.id
                Status = 'failed'
                LoadSeconds = $errorResult.loadSeconds
                LoadedVramMiB = $null
                PeakVramMiB = $null
                CodingPromptTps = $null
                CodingGenerationTps = $null
                RefactorPromptTps = $null
                RefactorGenerationTps = $null
                RefactorDrafted = $null
                RefactorAccepted = $null
                RefactorAcceptancePercent = $null
                RefactorStaticCheck = $null
                RefactorExactMatch = $null
                ToolFlowPassed = $null
            })
            Write-Warning "[$caseId] failed: $($errorResult.error)"
        } finally {
            if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
                Stop-Process -Id $serverProcess.Id -Force
                Wait-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue
            }
            $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resultPath -Encoding utf8
            Start-Sleep -Seconds 2
        }
    }
}

$summary | Export-Csv -LiteralPath $summaryPath -NoTypeInformation -Encoding utf8
Write-Host "Matrix complete. Summary: $summaryPath"
