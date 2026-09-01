. (Join-Path $PSScriptRoot 'Common.ps1')
$config = Get-ServerConfiguration
$profile = $config.models | Where-Object id -eq 'direct-iq4-xs' | Select-Object -First 1
$target = $profile.path
$expectedBytes = 15567825152

if (Test-Path -LiteralPath $target) {
    $size = (Get-Item -LiteralPath $target).Length
    if ($size -eq $expectedBytes) {
        Write-Host "Direct IQ4_XS is ready: $target ($size bytes)"
        exit 0
    }
    throw "Unexpected existing file size at ${target}: $size bytes (expected $expectedBytes)."
}

$persistentBackup = 'D:\Qwen_testr-backup\models\orcarouter_Qwen3.8-27B-Uncensored-IQ4_XS.gguf'
if (Test-Path -LiteralPath $persistentBackup) {
    $backupSize = (Get-Item -LiteralPath $persistentBackup).Length
    if ($backupSize -eq $expectedBytes) {
        Write-Host 'Restoring direct IQ4_XS from the persistent D: backup...'
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $persistentBackup -Destination $target
        Write-Host "Direct IQ4_XS restored to local NVMe: $target"
        exit 0
    }
}

$job = Get-BitsTransfer -AllUsers | Where-Object DisplayName -eq 'Qwen-IQ4-XS' | Select-Object -First 1
if ($null -eq $job) {
    $url = 'https://huggingface.co/bartowski/orcarouter_Qwen3.8-27B-Uncensored-GGUF/resolve/main/orcarouter_Qwen3.8-27B-Uncensored-IQ4_XS.gguf?download=true'
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    $job = Start-BitsTransfer -Source $url -Destination $target -DisplayName 'Qwen-IQ4-XS' -Asynchronous
}

while ($job.JobState -in @('Connecting', 'Transferring', 'TransientError')) {
    $job = Get-BitsTransfer -AllUsers | Where-Object DisplayName -eq 'Qwen-IQ4-XS' | Select-Object -First 1
    $percent = if ($job.BytesTotal -gt 0) { [math]::Round(100 * $job.BytesTransferred / $job.BytesTotal, 1) } else { 0 }
    Write-Progress -Activity 'Downloading direct OrcaRouter IQ4_XS' -Status "$percent%" -PercentComplete $percent
    Start-Sleep -Seconds 5
}

if ($job.JobState -eq 'Transferred') {
    Complete-BitsTransfer -BitsJob $job
} elseif ($job.JobState -eq 'Error') {
    throw "BITS download failed: $($job.ErrorDescription)"
} else {
    throw "BITS download stopped in state $($job.JobState)."
}

$size = (Get-Item -LiteralPath $target).Length
if ($size -ne $expectedBytes) { throw "Downloaded file size is $size, expected $expectedBytes." }
Write-Host "Direct IQ4_XS is ready: $target"
