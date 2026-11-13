#Requires -Version 7.0
<#
.SYNOPSIS
    SCORE example - place bug reports on an ordered severity rubric.

.DESCRIPTION
    Score rates against 2-10 ordered levels (lowest first) and returns:
      score          - probability-weighted level, can be fractional (e.g. 2.4)
      probabilities  - level -> 0..1
      legend         - level -> its description
      confidence     - how concentrated the mass is

    Practices shown:
      - Levels are CONCRETE situations, never bare numbers or "worse than the previous".
      - One dimension per Score (severity only - not severity AND breadth).
      - Use the score to threshold / rank; do not interpolate magnitudes between levels.
      - Normalise with score / (levels - 1) when you need a 0..1 value.
      - Inspect probabilities: the same score can hide very different distributions.
#>
[CmdletBinding()]
param([string]$Model = 'jev-latest')

Import-Module (Join-Path $PSScriptRoot '..\JevClient\JevClient.psd1') -Force
$apiKey = Get-JevApiKey

$severityLevels = @(
    'Cosmetic only: typo, misaligned element, wrong colour; no functional effect'                  # 0
    'Minor annoyance: a feature works but is slow or awkward; no data or money at risk'            # 1
    'Broken or degraded feature, but a reasonable workaround exists'                               # 2
    'Core feature broken for some users with no workaround; they cannot complete their task'       # 3
    'Outage, data loss, security exposure, or money charged incorrectly for many users'            # 4
)
$severity = New-JevScore -Instructions 'How severe is the problem described in this bug report?' -Criteria $severityLevels

$bugs = [ordered]@{
    'BUG-101' = 'The "Contact us" link in the footer is underlined in blue instead of grey on the pricing page.'
    'BUG-102' = 'Exporting a report to CSV fails with a 500 error. Copy-pasting the table into Excel works fine for now.'
    'BUG-103' = 'Since this morning''s deploy, every customer checking out with a saved card is being charged twice.'
    'BUG-104' = 'Users on Safari can''t upload profile photos - the button does nothing. Chrome users are fine.'
}

$results = foreach ($id in $bugs.Keys) {
    Write-Host "`n$id : $($bugs[$id])" -ForegroundColor White
    $r = Invoke-Jev -State $bugs[$id] -Questions ([ordered]@{ severity = $severity }) -Model $Model -ApiKey $apiKey
    Show-JevResponse $r

    $a          = $r.answers.severity
    $level      = [int][math]::Round([double]$a.score)
    $normalized = [double]$a.score / ($severityLevels.Count - 1)

    # Threshold in code, scaled to consequence: paging someone needs a high level AND decent confidence.
    $action = if ($level -ge 4 -and $a.confidence -ge 0.6) { 'PAGE ON-CALL' }
              elseif ($level -ge 3)                         { 'Next sprint, high priority' }
              elseif ($a.confidence -lt 0.5)                { 'Uncertain - human triage' }
              else                                          { 'Backlog' }
    Write-Host "  => $action" -ForegroundColor Magenta

    [pscustomobject]@{ Bug = $id; Score = [math]::Round([double]$a.score, 2); Level = $level
                       Normalized = [math]::Round($normalized, 2); Confidence = [math]::Round([double]$a.confidence, 2); Action = $action }
}

Write-Host "`nRanked by severity (score is for ordering, not magnitude):" -ForegroundColor White
$results | Sort-Object Score -Descending | Format-Table -AutoSize | Out-Host
