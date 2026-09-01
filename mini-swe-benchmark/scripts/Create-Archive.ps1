. (Join-Path $PSScriptRoot 'Common.ps1')
$paths = Get-BenchmarkPaths
$destination = Join-Path (Split-Path -Parent $paths.Root) 'mini-swe-benchmark-full.zip'
if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }

$items = @(
    (Join-Path $paths.Root 'config'),
    (Join-Path $paths.Root 'scripts'),
    (Join-Path $paths.Root 'state'),
    (Join-Path $paths.Root 'logs'),
    (Join-Path $paths.Root 'results'),
    (Join-Path $paths.Root 'README.md'),
    (Join-Path $paths.Root 'REPORT.md'),
    (Join-Path $paths.Root 'Resume-After-Reboot.ps1'),
    (Join-Path $paths.Root 'requirements.lock.txt'),
    (Join-Path $paths.Root '.gitignore')
) | Where-Object { Test-Path -LiteralPath $_ }

Compress-Archive -LiteralPath $items -DestinationPath $destination -CompressionLevel Optimal
Write-Host "Full benchmark archive created: $destination"
