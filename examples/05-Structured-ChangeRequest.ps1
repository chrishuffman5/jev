#Requires -Version 7.0
<#
.SYNOPSIS
    STRUCTURED example - JSON objects inside instructions and criteria (IT change management).

.DESCRIPTION
    instructions, Choice criteria values, Score levels and Noul true/false all accept
    objects/arrays instead of plain strings. Use structure when an option needs scope
    boundaries or the source data is already structured. Documented shapes used here:
      - instructions as { question, focus } - focus may reference state fields in backticks
      - Choice options as { what, not_for, examples }
      - Score levels as { summary, signals }
#>
[CmdletBinding()]
param([string]$Model = 'jev-latest')

Import-Module (Join-Path $PSScriptRoot '..\JevClient.psm1') -Force
$apiKey = Get-JevApiKey

$changeRequests = @(
    [ordered]@{
        id = 'CHG-2041'; title = 'Monthly Windows cumulative update on file servers'
        description = 'Apply the standard monthly CU to FS01-FS04 via WSUS during the Saturday maintenance window. Pre-approved template; snapshots taken first.'
        systems = @('FS01','FS02','FS03','FS04'); rollback = 'Restore VM snapshots'; window = 'Saturday 02:00-04:00'
    }
    [ordered]@{
        id = 'CHG-2042'; title = 'Rotate expired TLS certificate on the public API gateway'
        description = 'The wildcard certificate expired 20 minutes ago; all API clients are failing TLS handshakes. Replace it immediately.'
        systems = @('apigw-prod-01','apigw-prod-02'); rollback = 'None needed - old cert is expired'; window = 'Immediately'
    }
    [ordered]@{
        id = 'CHG-2043'; title = 'Migrate the HR database from SQL Server 2016 to Azure SQL Managed Instance'
        description = 'Move the HR database (employee PII, payroll) to Azure SQL MI using DMS online migration, then cut over connection strings in 6 apps.'
        systems = @('sql-hr-01','hr-portal','payroll-sync','badge-svc','benefits-api','reports','sso-connector'); rollback = 'Repoint apps to the old server within 30 minutes'; window = 'Next Sunday 00:00-06:00'
    }
)

$questions = [ordered]@{
    change_type = New-JevChoice -Instructions ([ordered]@{
            question = 'Which ITIL change type fits this change request?'
            focus    = 'Use `description` and `window`; a pre-approved template implies a standard change.'
        }) -Criteria ([ordered]@{
            standard  = [ordered]@{ what = 'Low-risk, repeatable, pre-approved change following a documented template'
                                    not_for = 'Anything novel, urgent, or touching systems outside the template'
                                    examples = @('monthly patching', 'adding a user to a group', 'routine cert renewal scheduled in advance') }
            normal    = [ordered]@{ what = 'Planned change that needs CAB review and approval before it runs'
                                    not_for = 'Changes that must happen immediately to restore service'
                                    examples = @('database migration', 'new firewall zone', 'major version upgrade') }
            emergency = [ordered]@{ what = 'Must be implemented as soon as possible to restore service or stop active harm'
                                    not_for = 'Planned work that is merely important or has a deadline next week'
                                    examples = @('production outage fix', 'expired certificate breaking clients', 'patch for an actively exploited CVE') }
        })

    risk = New-JevScore -Instructions 'How risky is this change if it goes wrong?' -Criteria @(
        [ordered]@{ summary = 'Low risk';      signals = @('few systems', 'tested template', 'quick, proven rollback', 'no sensitive data') }
        [ordered]@{ summary = 'Moderate risk'; signals = @('several systems', 'rollback exists but is manual', 'some user impact possible') }
        [ordered]@{ summary = 'High risk';     signals = @('many dependent apps', 'sensitive or regulated data', 'cut-over with limited rollback', 'cross-platform migration') }
    )

    rollback_credible = New-JevNoul -Instructions 'Does the change have a credible rollback plan?' `
        -WhenTrue  ([ordered]@{ means = 'A concrete, quick way to return to the previous state is stated' }) `
        -WhenFalse ([ordered]@{ means = 'No rollback, a vague rollback, or rollback is irrelevant because the old state was already broken' })

    touches_regulated_data = New-JevNoul 'Does this change touch personal, payroll, health, or payment data?'
}

foreach ($cr in $changeRequests) {
    Write-Host "`n$($cr.id): $($cr.title)" -ForegroundColor White
    $r = Invoke-Jev -State $cr -Questions $questions -Model $Model -ApiKey $apiKey
    Show-JevResponse $r
    $a = $r.answers

    # Approval routing in code - the destructive/expensive path requires the strongest evidence.
    $approval = switch ($a.change_type.choice) {
        'standard'  { if ($a.change_type.confidence -gt 0.9 -and [double]$a.risk.score -lt 0.5) { 'Auto-approve (standard template)' } else { 'Send to change manager to confirm it is really standard' } }
        'emergency' { 'ECAB: on-call manager approves now, retrospective CAB review' }
        default     { 'Schedule for weekly CAB' }
    }
    if ($a.touches_regulated_data.noul -ge 0.7) { $approval += ' + data-protection sign-off' }
    if ($a.rollback_credible.noul -lt 0.5 -and $a.change_type.choice -ne 'emergency') { $approval += ' + require a written rollback plan' }
    Write-Host "  => $approval" -ForegroundColor Magenta
}
