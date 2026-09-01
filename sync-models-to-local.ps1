$ErrorActionPreference = 'Stop'

$archiveRoot = 'D:\AI\Qwen3.8-27B-Uncensored'
$localRoot = 'C:\AI\Qwen3.8-27B-Uncensored'
$runtimeName = 'llama.cpp-b10734'

$models = @(
    'models\Qwen3.8-27B-Uncensored-FP8.i1-Q2_K.gguf',
    'models\Qwen3.8-27B-Uncensored-FP8.i1-Q4_K_M.gguf',
    'models\uncensored-12gb\Qwen3.8-27B-Unleashed-UD-Q2_K_XL.gguf',
    'models\uncensored-12gb\Qwen3.8-27B-LowGPU-uncensored-NoMTP-IQ3XXXS.gguf'
)

$runtimeSource = Join-Path $archiveRoot $runtimeName
$runtimeTarget = Join-Path $localRoot $runtimeName
if (-not (Test-Path -LiteralPath $runtimeSource)) {
    throw "Runtime archive not found: $runtimeSource"
}

New-Item -ItemType Directory -Path $runtimeTarget -Force | Out-Null
Write-Host "Syncing llama.cpp runtime to $runtimeTarget"
Copy-Item -Path (Join-Path $runtimeSource '*') -Destination $runtimeTarget -Recurse -Force

foreach ($relativePath in $models) {
    $source = Join-Path $archiveRoot $relativePath
    $target = Join-Path $localRoot $relativePath

    if (-not (Test-Path -LiteralPath $source)) {
        Write-Warning "Skipping missing archive file: $source"
        continue
    }

    $sourceItem = Get-Item -LiteralPath $source
    $targetItem = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
    if ($null -ne $targetItem -and $targetItem.Length -eq $sourceItem.Length) {
        Write-Host "Already current: $($sourceItem.Name)"
        continue
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Write-Host "Copying $($sourceItem.Name) ($([math]::Round($sourceItem.Length / 1GB, 2)) GiB)"
    Copy-Item -LiteralPath $source -Destination $target -Force

    $copied = Get-Item -LiteralPath $target
    if ($copied.Length -ne $sourceItem.Length) {
        throw "Size verification failed after copying: $target"
    }
}

Write-Host 'Local NVMe cache is ready.'
