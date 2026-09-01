Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:BenchmarkRoot = Split-Path -Parent $PSScriptRoot

function Get-BenchmarkRoot {
    return $script:BenchmarkRoot
}

function Get-BenchmarkPaths {
    $root = Get-BenchmarkRoot
    [pscustomobject]@{
        Root       = $root
        Python     = Join-Path $root '.venv\Scripts\python.exe'
        MiniExtra  = Join-Path $root '.venv\Scripts\mini-extra.exe'
        Config     = Join-Path $root 'config'
        Results    = Join-Path $root 'results'
        State      = Join-Path $root 'state'
        Logs       = Join-Path $root 'logs'
    }
}

function Get-ServerConfiguration {
    $paths = Get-BenchmarkPaths
    return Get-Content -LiteralPath (Join-Path $paths.Config 'server-profiles.json') -Raw | ConvertFrom-Json
}

function Get-RunPlan {
    $paths = Get-BenchmarkPaths
    return Get-Content -LiteralPath (Join-Path $paths.Config 'run-plan.json') -Raw | ConvertFrom-Json
}

function Get-TaskConfiguration {
    $paths = Get-BenchmarkPaths
    return Get-Content -LiteralPath (Join-Path $paths.Config 'tasks.json') -Raw | ConvertFrom-Json
}

function Get-DockerExecutable {
    $candidate = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    $command = Get-Command docker.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    throw 'docker.exe not found. Run Setup-Environment.ps1 first.'
}

function Test-PendingReboot {
    $checks = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    return [bool]($checks | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Wait-DockerReady {
    param([int]$TimeoutSeconds = 240)

    $docker = Get-DockerExecutable
    & $docker info *> $null
    if ($LASTEXITCODE -eq 0) { return }

    $desktop = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
    if (-not (Test-Path -LiteralPath $desktop)) {
        throw 'Docker Desktop is not installed.'
    }
    Start-Process -FilePath $desktop -WindowStyle Hidden | Out-Null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        Start-Sleep -Seconds 3
        & $docker info *> $null
        if ($LASTEXITCODE -eq 0) { return }
    } while ($watch.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    throw "Docker daemon did not become ready in $TimeoutSeconds seconds."
}

function Get-GpuSnapshot {
    $line = & nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if (-not $line) { return $null }
    $parts = $line -split ',\s*'
    [pscustomobject]@{
        name        = $parts[0]
        totalMiB    = [int]$parts[1]
        usedMiB     = [int]$parts[2]
        freeMiB     = [int]$parts[3]
        utilization = [int]$parts[4]
        capturedUtc = [DateTime]::UtcNow.ToString('o')
    }
}

function Clear-ModelPromptCache {
    $config = Get-ServerConfiguration
    $headers = @{ Authorization = "Bearer $($config.apiKey)" }
    try {
        Invoke-RestMethod -Method Post -Uri "http://$($config.host):$($config.port)/slots/0?action=erase" -Headers $headers -TimeoutSec 15 | Out-Null
    } catch {
        Write-Warning "Prompt-cache erase endpoint was unavailable: $($_.Exception.Message)"
    }
}

function Stop-BenchmarkModel {
    param([AllowNull()]$ServerState)

    if ($null -eq $ServerState) { return }
    $process = Get-Process -Id $ServerState.processId -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(15000) | Out-Null
    }
}

function Start-BenchmarkModel {
    param(
        [Parameter(Mandatory)][string]$ModelId,
        [Parameter(Mandatory)][ValidateSet(101, 202)][int]$Seed,
        [string]$LogTag = 'manual'
    )

    $paths = Get-BenchmarkPaths
    $config = Get-ServerConfiguration
    $profile = $config.models | Where-Object id -eq $ModelId | Select-Object -First 1
    if ($null -eq $profile) { throw "Unknown model profile: $ModelId" }
    if (-not (Test-Path -LiteralPath $config.serverPath)) { throw "llama-server not found: $($config.serverPath)" }
    if (-not (Test-Path -LiteralPath $profile.path)) { throw "Model not found: $($profile.path)" }

    $listener = Get-NetTCPConnection -LocalPort $config.port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $listener) {
        $owner = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
        if ($null -ne $owner -and $owner.ProcessName -eq 'llama-server') {
            Stop-Process -Id $owner.Id -Force
            Start-Sleep -Seconds 2
        } else {
            throw "Port $($config.port) is occupied by PID $($listener.OwningProcess)."
        }
    }

    $logDir = Join-Path $paths.Logs "server\$LogTag"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $stdout = Join-Path $logDir 'stdout.log'
    $processStderr = Join-Path $logDir 'process-stderr.log'
    $serverLog = Join-Path $logDir 'server.log'
    $common = $config.common
    $arguments = @(
        '--model', $profile.path,
        '--alias', $profile.id,
        '--host', $config.host,
        '--port', [string]$config.port,
        '--api-key', $config.apiKey,
        '--ctx-size', [string]$common.contextSize,
        '--parallel', '1',
        '--flash-attn', $common.flashAttention,
        '--cache-type-k', $common.cacheTypeK,
        '--cache-type-v', $common.cacheTypeV,
        '--batch-size', [string]$common.batchSize,
        '--ubatch-size', [string]$common.ubatchSize,
        '--cache-reuse', [string]$common.cacheReuse,
        '--threads', [string]$common.threads,
        '--threads-batch', [string]$common.threadsBatch,
        '--seed', [string]$Seed,
        '--jinja',
        '--reasoning-format', $common.reasoningFormat,
        '--reasoning-effort', $common.reasoningEffort,
        '--reasoning-preserve',
        '--slots',
        '--no-webui',
        '--log-file', $serverLog,
        '--log-timestamps',
        '-lv', '4'
    )
    if ($profile.fullGpu) {
        $arguments += @('--fit', 'off', '--n-gpu-layers', 'all')
    } else {
        $arguments += @('--fit', 'on', '--fit-target', '512', '--fit-ctx', [string]$common.contextSize, '--n-gpu-layers', 'auto')
    }
    if ($profile.mtp) {
        $arguments += @('--spec-type', 'draft-mtp', '--spec-draft-n-max', '2')
    }

    $beforeGpu = Get-GpuSnapshot
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $config.serverPath -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $processStderr
    try {
        do {
            if ($process.HasExited) {
                $tail = if (Test-Path -LiteralPath $serverLog) { (Get-Content -LiteralPath $serverLog -Tail 60) -join [Environment]::NewLine } elseif (Test-Path -LiteralPath $processStderr) { (Get-Content -LiteralPath $processStderr -Tail 60) -join [Environment]::NewLine } else { '' }
                throw "llama-server exited during load (code $($process.ExitCode)).`n$tail"
            }
            try {
                $health = Invoke-RestMethod -Uri "http://$($config.host):$($config.port)/health" -TimeoutSec 3
                if ($health.status -eq 'ok') { break }
            } catch { }
            Start-Sleep -Milliseconds 750
        } while ($watch.Elapsed.TotalSeconds -lt 240)
        if ($watch.Elapsed.TotalSeconds -ge 240) { throw 'llama-server load timeout after 240 seconds.' }

        $process.Refresh()
        $logText = if (Test-Path -LiteralPath $serverLog) { Get-Content -LiteralPath $serverLog -Raw } else { '' }
        $offloaded = ''
        if ($logText -match 'offloaded\s+(\d+)/(\d+)\s+layers') { $offloaded = "$($Matches[1])/$($Matches[2])" }
        $state = [pscustomobject]@{
            modelId          = $profile.id
            displayName      = $profile.displayName
            modelPath        = $profile.path
            seed             = $Seed
            processId        = $process.Id
            startedUtc       = [DateTime]::UtcNow.ToString('o')
            loadSeconds      = [math]::Round($watch.Elapsed.TotalSeconds, 3)
            beforeGpu        = $beforeGpu
            loadedGpu        = Get-GpuSnapshot
            workingSetGiB    = [math]::Round($process.WorkingSet64 / 1GB, 3)
            offloadedLayers  = $offloaded
            arguments        = $arguments
            stdoutLog        = $stdout
            stderrLog        = $serverLog
            processStderrLog = $processStderr
        }
        $statePath = Join-Path $paths.State 'active-server.json'
        New-Item -ItemType Directory -Path $paths.State -Force | Out-Null
        $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8
        return $state
    } catch {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
        throw
    }
}

function Invoke-LoggedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$StdoutPath,
        [Parameter(Mandatory)][string]$StderrPath,
        [int]$TimeoutSeconds = 0
    )

    New-Item -ItemType Directory -Path (Split-Path -Parent $StdoutPath) -Force | Out-Null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -PassThru -WindowStyle Hidden -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    $timedOut = $false
    if ($TimeoutSeconds -gt 0) {
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $timedOut = $true
            & taskkill.exe /PID $process.Id /T /F *> $null
            $process.WaitForExit(15000) | Out-Null
        }
    } else {
        $process.WaitForExit()
    }
    $process.Refresh()
    [pscustomobject]@{
        exitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        timedOut = $timedOut
        seconds  = [math]::Round($watch.Elapsed.TotalSeconds, 3)
        stdout   = $StdoutPath
        stderr   = $StderrPath
    }
}
