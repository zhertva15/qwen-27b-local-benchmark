param(
    [Parameter(Mandatory)]
    [ValidateSet('lowgpu-iq3xxxs', 'fp8-q4-k-m', 'direct-iq4-xs')]
    [string]$Model,

    [ValidateSet(101, 202)]
    [int]$Seed = 101
)

. (Join-Path $PSScriptRoot 'Common.ps1')
$state = Start-BenchmarkModel -ModelId $Model -Seed $Seed -LogTag "manual-$Model-seed$Seed"
$state | Format-List
Write-Host "Server is ready at http://127.0.0.1:8092/v1 (PID $($state.processId))."

