param(
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$StopFile,
    [Parameter(Mandatory)][int]$ServerPid
)

$directory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Path $directory -Force | Out-Null
'timestamp_utc,vram_used_mib,vram_free_mib,gpu_utilization,server_working_set_gib' | Set-Content -LiteralPath $OutputPath -Encoding ascii
while (-not (Test-Path -LiteralPath $StopFile)) {
    $gpu = & nvidia-smi --query-gpu=memory.used,memory.free,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    $parts = $gpu -split ',\s*'
    $process = Get-Process -Id $ServerPid -ErrorAction SilentlyContinue
    $ram = if ($null -ne $process) { [math]::Round($process.WorkingSet64 / 1GB, 3) } else { '' }
    if ($parts.Count -ge 3) {
        $line = '{0},{1},{2},{3},{4}' -f [DateTime]::UtcNow.ToString('o'), $parts[0], $parts[1], $parts[2], $ram
        Add-Content -LiteralPath $OutputPath -Value $line -Encoding ascii
    }
    Start-Sleep -Seconds 1
}

