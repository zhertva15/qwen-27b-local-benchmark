$ErrorActionPreference = 'Stop'

$labRoot = Split-Path -Parent $PSScriptRoot
$promptPath = Join-Path $labRoot 'prompts\refactor-copy.txt'
$rawDirectory = Join-Path $labRoot 'results\raw'
$auditPath = Join-Path $labRoot 'results\audit.csv'

$prompt = Get-Content -LiteralPath $promptPath -Raw
$source = $prompt.Substring($prompt.IndexOf('from dataclasses'))
$expected = $source.Replace('    result = {', '    payload = {').Replace('    return result', '    return payload')
$lf = [string][char]10
$crlf = ([string][char]13) + [char]10

function ConvertTo-CleanCode {
    param([string]$Text)

    $clean = [regex]::Replace($Text, '(?s)^\s*<think>.*?</think>\s*', '')
    $clean = [regex]::Replace($clean, '(?m)^\s*```(?:python)?\s*$', '')
    return $clean.Replace($crlf, $lf).Trim()
}

$expectedClean = $expected.Replace($crlf, $lf).Trim()
$audit = foreach ($file in Get-ChildItem -LiteralPath $rawDirectory -Filter '*.json' | Sort-Object Name) {
    $result = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $actual = ConvertTo-CleanCode -Text ([string]$result.refactor.content)
    [pscustomobject]@{
        CaseId = $result.caseId
        Status = $result.status
        ExactRefactorMatch = ($actual -ceq $expectedClean)
        RefactorGeneratedTokens = $result.refactor.generatedTokens
        RefactorFinishReason = $result.refactor.finishReason
        RefactorDraftedTokens = $result.refactor.draftedTokens
        RefactorAcceptedTokens = $result.refactor.acceptedDraftTokens
        RefactorAcceptancePercent = $result.refactor.acceptancePercent
        ToolFlowPassed = $result.toolFlow.passed
    }
}

$audit | Export-Csv -LiteralPath $auditPath -NoTypeInformation -Encoding utf8
$audit | Format-Table -AutoSize
Write-Host "Audit written to $auditPath"
