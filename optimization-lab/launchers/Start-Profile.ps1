param(
    [Parameter(Mandatory)]
    [string]$ModelId,

    [Parameter(Mandatory)]
    [ValidateSet('baseline', 'q4kv', 'q4kv-ngram', 'q4kv-mtp')]
    [string]$ProfileId,

    [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'

$labRoot = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath (Join-Path $labRoot 'config\matrix.json') -Raw | ConvertFrom-Json
$model = $config.models | Where-Object id -eq $ModelId | Select-Object -First 1
$profile = $config.profiles | Where-Object id -eq $ProfileId | Select-Object -First 1

if ($null -eq $model) {
    throw "Unknown ModelId '$ModelId'. Valid values: $($config.models.id -join ', ')"
}
if ($null -eq $profile) {
    throw "Unknown ProfileId '$ProfileId'."
}
if ($profile.requiresMtp -and -not $model.supportsMtp) {
    throw "Model '$ModelId' has no MTP head and cannot use profile '$ProfileId'."
}
if (-not (Test-Path -LiteralPath $model.path)) {
    throw "Model not found: $($model.path)"
}

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
    '--reasoning-format', 'none'
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

Write-Host "Starting $($model.displayName) with profile $($profile.displayName)"
Write-Host "Web UI: http://127.0.0.1:$Port"
Write-Host "API key: $($config.apiKey)"
& $config.serverPath @serverArgs
