$ErrorActionPreference = 'Stop'
$defaultRoot = 'C:\Users\StrikeArena\Documents\ChatGPT\Qwen_testr\mini-swe-benchmark'
$sourceRoot = $PSScriptRoot

if ([IO.Path]::GetFullPath($sourceRoot) -ne [IO.Path]::GetFullPath($defaultRoot)) {
    New-Item -ItemType Directory -Path $defaultRoot -Force | Out-Null
    & robocopy.exe $sourceRoot $defaultRoot /E /XD .venv /R:2 /W:2 /NP
    if ($LASTEXITCODE -gt 7) { throw "Project restore failed with robocopy code $LASTEXITCODE." }
}

Set-Location $defaultRoot
& (Join-Path $defaultRoot 'scripts\Setup-Environment.ps1')
& (Join-Path $defaultRoot 'scripts\Prepare-GoldPreflight.ps1')
& (Join-Path $defaultRoot 'scripts\Run-Smoke.ps1')
& (Join-Path $defaultRoot 'scripts\Run-Benchmark.ps1')

