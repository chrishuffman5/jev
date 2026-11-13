#Requires -Version 7.0
<#
.SYNOPSIS
    CHOICE example - route support tickets to exactly one team.

.DESCRIPTION
    Choice picks one option from an unordered set and returns:
      choice         - the top option
      probabilities  - option -> 0..1 (sums to 1)
      confidence     - how concentrated the mass is on one option

    Practices shown:
      - Give the COMPLETE taxonomy, including an "other" escape hatch so jev never force-fits.
      - Use [ordered]@{} - option order is input and can move answers.
      - Gate the action on confidence in code (act / review / human), not in the prompt.
      - The last ticket is deliberately ambiguous to show a split distribution.
#>
[CmdletBinding()]
param([string]$Model = 'jev-latest')

Import-Module (Join-Path $PSScriptRoot '..\JevClient\JevClient.psd1') -Force
$apiKey = Get-JevApiKey   # Get-Secret jev -> SecureString

# One reviewed definition of the question - question wording is production logic.
$routeQuestion = New-JevChoice -Instructions 'Which team should handle this support ticket?' -Criteria ([ordered]@{
    billing   = 'Charges, refunds, invoices, payment methods, subscription pricing'
    shipping  = 'Delivery status, delays, lost or misrouted packages, tracking numbers'
    returns   = 'Exchanges, wrong size, wrong or damaged items, return labels'
    technical = 'Website or app errors, login problems, password resets, bugs'
    account   = 'Profile details, email address changes, closing or merging accounts'
    other     = 'Anything that does not clearly fit one of the teams above'
})

$tickets = @(
    'I was charged twice for order #4471 this morning. Please refund the duplicate charge.'
    'The tracking page has said "label created" for nine days. Where is my package?'
    'I can''t log in to the app - it keeps saying my session expired, even right after a password reset.'
    'My package arrived crushed and the blender inside is cracked. Also, why was I billed for express shipping when it took two weeks?'
)

foreach ($ticket in $tickets) {
    Write-Host "`nTICKET: $ticket" -ForegroundColor White

    $r = Invoke-Jev -State $ticket -Questions ([ordered]@{ team = $routeQuestion }) -Model $Model -ApiKey $apiKey
    Show-JevResponse $r

    # Decision logic lives in code. Thresholds are vendor starting points - tune on your data.
    $a = $r.answers.team
    switch (Get-JevConfidenceBand $a.confidence) {
        'act'    { Write-Host "  => Auto-assign to '$($a.choice)'." -ForegroundColor Magenta }
        'review' {
            $top2 = ConvertTo-JevProbabilityList $a.probabilities | Select-Object -First 2
            Write-Host "  => Suggest '$($top2[0].Option)' (runner-up '$($top2[1].Option)'); agent confirms." -ForegroundColor Magenta
        }
        'human'  { Write-Host '  => Too uncertain - send to the triage queue.' -ForegroundColor Magenta }
    }
    if ($a.choice -eq 'other') { Write-Host '  => Landed in "other": consider whether the taxonomy is missing a team.' -ForegroundColor Magenta }
}
