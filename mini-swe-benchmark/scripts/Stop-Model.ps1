. (Join-Path $PSScriptRoot 'Common.ps1')
$paths = Get-BenchmarkPaths
$statePath = Join-Path $paths.State 'active-server.json'
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    Stop-BenchmarkModel -ServerState $state
    Remove-Item -LiteralPath $statePath -Force
    Write-Host "Stopped benchmark llama-server PID $($state.processId)."
} else {
    Write-Host 'No benchmark server state was found.'
}

