#Requires -Version 7.0
<#
.SYNOPSIS
    MIXED example - Choice + Score + Noul in ONE call, then route and prioritise in code.

.DESCRIPTION
    All questions in a request see the same state and are answered in parallel, so
    adding questions barely changes latency. Ask everything you MIGHT need ("speculative
    fan-out") and read only what the code path uses.

    Practices shown:
      - Related facts (ticket + customer + order) go in state; judgements go in questions.
      - Each Score is one dimension; normalise each with score / (levels - 1), weight and
        sum in code to build a composite priority.
      - Do not assume cross-question consistency (e.g. that "urgency" and "is_urgent" agree);
        check invariants in code when it matters.
#>
[CmdletBinding()]
param([string]$Model = 'jev-latest')

Import-Module (Join-Path $PSScriptRoot '..\JevClient\JevClient.psd1') -Force
$apiKey = Get-JevApiKey

$state = [ordered]@{
    ticket = [ordered]@{
        subject = 'Payroll export broken before month-end'
        body    = 'Our payroll export to ADP has failed every night since Tuesday with "invalid schema". ' +
                  'We run payroll on Friday for 340 employees. Your status page says everything is fine. ' +
                  'We need this fixed or a manual workaround today.'
    }
    customer = [ordered]@{ plan = 'Enterprise'; seats = 340; account_age_years = 4 }
}

$urgencyLevels = @(
    'No time pressure; informational or a nice-to-have'
    'Should be handled within a few days; inconvenience only'
    'Blocks routine work; needs attention within a day'
    'Hard business deadline within days, or many people blocked right now'
)
$impactLevels = @(
    'Affects a single user'
    'Affects a team or a handful of users'
    'Affects a whole department or a large customer''s workflow'
    'Affects the entire organisation or has payroll / legal / financial consequences'
)

$questions = [ordered]@{
    # Choice: category
    category = New-JevChoice 'What kind of request is this?' ([ordered]@{
        integration_failure = 'A connection, sync, export or import with a third-party system is failing'
        product_bug         = 'A feature inside our product behaves incorrectly'
        how_to              = 'The customer is asking how to do something'
        billing             = 'Charges, invoices, plan changes'
        feature_request     = 'Asking for new functionality'
        other               = 'None of the above'
    })
    # Scores: two independent dimensions
    urgency  = New-JevScore 'How time-sensitive is this ticket?' $urgencyLevels
    impact   = New-JevScore 'How broad is the business impact described?' $impactLevels
    # Nouls: single conditions
    has_deadline       = New-JevNoul 'Does the customer mention a specific upcoming deadline?'
    wants_workaround   = New-JevNoul 'Would the customer accept a temporary workaround?'
    questions_status   = New-JevNoul 'Does the customer doubt or contradict our status page?'
    is_security_issue  = New-JevNoul 'Does this ticket describe a security vulnerability or breach?'   # read only if routing needs it
}

$r = Invoke-Jev -State $state -Questions $questions -Model $Model -ApiKey $apiKey
Write-Host "`nANSWERS:" -ForegroundColor White
Show-JevResponse $r
$a = $r.answers

# --- composite priority in code -------------------------------------------------------
$urgencyN = [double]$a.urgency.score / ($urgencyLevels.Count - 1)
$impactN  = [double]$a.impact.score  / ($impactLevels.Count - 1)
$planBoost = if ($state.customer.plan -eq 'Enterprise') { 0.1 } else { 0 }
$priority = [math]::Min(1.0, 0.5 * $urgencyN + 0.4 * $impactN + $planBoost)

$queue = switch ($a.category.choice) {
    'integration_failure' { 'Integrations engineering' }
    'product_bug'         { 'Product support' }
    'billing'             { 'Billing' }
    default               { 'Tier-1 support' }
}
if ($a.is_security_issue.noul -ge 0.5) { $queue = 'Security response' }   # low bar for a high-consequence route

$sla = if ($priority -ge 0.75) { 'P1 - respond within 1 hour' }
       elseif ($priority -ge 0.5) { 'P2 - respond within 4 hours' }
       else { 'P3 - next business day' }

Write-Host "`nROUTING (computed in code):" -ForegroundColor White
Write-Host ("  urgency normalised {0:N2} | impact normalised {1:N2} | plan boost {2} => priority {3:N2}" -f $urgencyN, $impactN, $planBoost, $priority)
Write-Host "  => Queue: $queue | $sla" -ForegroundColor Magenta
if ($a.wants_workaround.noul -ge 0.7)  { Write-Host '  => Include a manual export workaround in the first reply.' -ForegroundColor Magenta }
if ($a.questions_status.noul -ge 0.7)  { Write-Host '  => Check whether the status page is missing an incident.' -ForegroundColor Magenta }

# Invariant check: a stated deadline should not come with "no time pressure".
if ($a.has_deadline.noul -ge 0.8 -and [double]$a.urgency.score -lt 1) {
    Write-Warning 'Inconsistent answers: a deadline was detected but urgency is lowest. Flag for review.'
}
