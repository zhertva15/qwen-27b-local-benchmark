[CmdletBinding()]
param(
    [string]$ThreadId = '01a05d27-c52f-7891-bb59-aac28d93f5fd',
    [string]$DestinationRoot = 'D:\Qwen_testr-backup\codex-session'
)

$ErrorActionPreference = 'Stop'

$userProfilePath = [Environment]::GetFolderPath('UserProfile')
$codexDataRoot = Join-Path $userProfilePath '.codex'
$destination = Join-Path $DestinationRoot $ThreadId
$rawDestination = Join-Path $destination 'raw'

if (-not (Test-Path -LiteralPath 'D:\')) {
    throw 'Persistent D: drive is not available.'
}

if (-not (Test-Path -LiteralPath $codexDataRoot)) {
    throw "Codex data directory was not found: $codexDataRoot"
}

$sessionFile = Get-ChildItem (Join-Path $codexDataRoot 'sessions') -Recurse -File -Filter "*$ThreadId*.jsonl" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $sessionFile) {
    throw "Rollout JSONL for thread $ThreadId was not found."
}

$sessionDestination = Join-Path $rawDestination 'session'
$metadataDestination = Join-Path $rawDestination 'metadata'
$attachmentsDestination = Join-Path $rawDestination 'attachments'
$plansDestination = Join-Path $rawDestination 'plans'

@($destination, $rawDestination, $sessionDestination, $metadataDestination,
  $attachmentsDestination, $plansDestination) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

Copy-Item -LiteralPath $sessionFile.FullName -Destination $sessionDestination -Force

$metadataPatterns = @(
    'session_index.jsonl',
    '.codex-global-state.json',
    'state_5.sqlite*',
    'thread_history_1.sqlite*'
)

foreach ($pattern in $metadataPatterns) {
    Get-ChildItem -Path (Join-Path $codexDataRoot $pattern) -File -ErrorAction SilentlyContinue |
        Copy-Item -Destination $metadataDestination -Force
}

$attachmentsSource = Join-Path $codexDataRoot 'attachments'
if (Test-Path -LiteralPath $attachmentsSource) {
    Copy-Item -Path (Join-Path $attachmentsSource '*') -Destination $attachmentsDestination -Recurse -Force
}

$threadPlanSource = Join-Path (Join-Path $codexDataRoot 'plans') $ThreadId
if (Test-Path -LiteralPath $threadPlanSource) {
    Copy-Item -LiteralPath $threadPlanSource -Destination $plansDestination -Recurse -Force
}

$scriptDirectory = Split-Path -Parent $PSCommandPath
$projectRoot = Split-Path -Parent $scriptDirectory
$recoveryDocument = Join-Path $projectRoot 'SESSION_RECOVERY.md'
if (Test-Path -LiteralPath $recoveryDocument) {
    Copy-Item -LiteralPath $recoveryDocument -Destination $destination -Force
}

$copiedFiles = Get-ChildItem -LiteralPath $rawDestination -Recurse -File
$manifestFiles = foreach ($file in $copiedFiles) {
    [ordered]@{
        relative_path = $file.FullName.Substring($destination.Length).TrimStart('\')
        bytes = $file.Length
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
}

$manifest = [ordered]@{
    schema_version = 1
    thread_id = $ThreadId
    created_at = (Get-Date).ToString('o')
    source_session = $sessionFile.FullName
    destination = $destination
    excludes = @('auth.json', '.sandbox-secrets', 'browser profile', 'tokens')
    files = @($manifestFiles)
}

$manifest | ConvertTo-Json -Depth 6 |
    Set-Content -LiteralPath (Join-Path $destination 'BACKUP-MANIFEST.json') -Encoding UTF8

$archivePath = Join-Path $DestinationRoot "$ThreadId.zip"
Compress-Archive -Path (Join-Path $destination '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash

$totalBytes = ($copiedFiles | Measure-Object Length -Sum).Sum
Write-Host "Codex session backup completed: $destination"
Write-Host "Files: $($copiedFiles.Count); bytes: $totalBytes"
Write-Host "Archive: $archivePath"
Write-Host "Archive SHA256: $archiveHash"
Write-Host 'Credentials and browser data were not copied.'
