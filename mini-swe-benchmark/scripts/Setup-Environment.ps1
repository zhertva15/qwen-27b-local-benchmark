. (Join-Path $PSScriptRoot 'Common.ps1')
$paths = Get-BenchmarkPaths

$dockerFound = $true
try { $null = Get-DockerExecutable } catch { $dockerFound = $false }
if (-not $dockerFound) {
    Write-Host 'Installing Docker Desktop with winget...'
    & winget install --id Docker.DockerDesktop --exact --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "Docker Desktop installation failed with exit code $LASTEXITCODE." }
}

$features = @('Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform')
foreach ($featureName in $features) {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
    if ($feature.State -ne 'Enabled') {
        Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart | Out-Null
        Write-Host "Enabled $featureName; a Windows restart is required."
    }
}

if (-not (Test-Path -LiteralPath $paths.Python)) {
    $bundledPython = 'C:\Users\StrikeArena\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
    if (-not (Test-Path -LiteralPath $bundledPython)) { throw 'Bundled Python runtime was not found.' }
    & $bundledPython -m venv (Join-Path $paths.Root '.venv')
}
& $paths.Python -m pip install --disable-pip-version-check -r (Join-Path $paths.Root 'requirements.lock.txt')
if ($LASTEXITCODE -ne 0) { throw "Python dependency installation failed with exit code $LASTEXITCODE." }

& (Join-Path $PSScriptRoot 'Download-DirectModel.ps1')
Write-Host 'Environment files are installed. If Windows requests a restart, restart before Prepare-GoldPreflight.ps1.'
