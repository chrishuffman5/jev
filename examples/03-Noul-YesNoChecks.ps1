#Requires -Version 7.0
<#
.SYNOPSIS
    NOUL example - batched yes/no checks on a customer message.

.DESCRIPTION
    Noul answers a yes/no question with a single number: P(yes), 0..1.
    There is NO confidence field - the probability is the whole signal, and a value
    near 0.5 means "uncertain", never "medium".

    Practices shown:
      - One condition per Noul ("angry AND wants refund" becomes two questions).
      - Optional true/false criteria to pin down a subtle boundary.
      - Many Nouls in one call: they are evaluated in parallel and in isolation.
      - Arithmetic and dates stay in CODE. We compute whether the order is inside the
        return window and put the RESULT in state; jev never does date maths.
      - Thresholds are applied in code, not in the question wording.
#>
[CmdletBinding()]
param([string]$Model = 'jev-latest')

Import-Module (Join-Path $PSScriptRoot '..\JevClient\JevClient.psd1') -Force
$apiKey = Get-JevApiKey

# --- facts computed deterministically in code ---------------------------------------
$orderDate        = (Get-Date).AddDays(-41)
$returnWindowDays = 30
$daysSinceOrder   = [int]((Get-Date) - $orderDate).TotalDays
$withinWindow     = $daysSinceOrder -le $returnWindowDays

# State as an object keeps the message and the facts unambiguous.
$state = [ordered]@{
    customer_message = 'This is the third time I''m writing about these headphones. The left side cut out after a month. ' +
                       'I want my money back, and honestly if nobody fixes this I''ll be talking to my lawyer. ' +
                       'Can someone who actually works there call me?'
    order = [ordered]@{
        item                    = 'Wireless headphones'
        days_since_order        = $daysSinceOrder
        within_return_window    = $withinWindow
        under_warranty          = $true
    }
}

$questions = [ordered]@{
    wants_refund     = New-JevNoul 'Is the customer asking for their money back?'
    wants_human      = New-JevNoul 'Is the customer asking to speak with a human / staff member?'
    threatens_legal  = New-JevNoul 'Does the customer threaten legal action?' `
                         -WhenTrue  'Explicit mention of lawyers, suing, courts, or regulators as a consequence' `
                         -WhenFalse 'General frustration or complaints without any legal consequence mentioned'
    is_angry         = New-JevNoul 'Is the customer angry?' `
                         -WhenTrue  'Hostile, exasperated, or furious tone' `
                         -WhenFalse 'Calm, neutral, or only mildly disappointed'
    repeat_contact   = New-JevNoul 'Has the customer contacted support about this before?'
    product_defect   = New-JevNoul 'Does the message describe the product failing or malfunctioning?'
    asks_for_discount= New-JevNoul 'Is the customer asking for a discount or coupon?'   # expected: no
}

Write-Host "`nSTATE:" -ForegroundColor White
$state | ConvertTo-Json -Depth 5 | Write-Host
Write-Host ''

$r = Invoke-Jev -State $state -Questions $questions -Model $Model -ApiKey $apiKey
Show-JevResponse $r

# --- decision logic in code -----------------------------------------------------------
$p = @{}; foreach ($prop in $r.answers.PSObject.Properties) { $p[$prop.Name] = [double]$prop.Value.noul }
$yes = { param($name) $p[$name] -ge 0.8 }
$uncertain = $p.GetEnumerator() | Where-Object { $_.Value -gt 0.35 -and $_.Value -lt 0.65 } | ForEach-Object Key

Write-Host "`nDECISIONS:" -ForegroundColor White
if (& $yes 'threatens_legal') { Write-Host '  => Flag for the escalations team (legal language present).' -ForegroundColor Magenta }
if (& $yes 'wants_human')     { Write-Host '  => Schedule a call-back from a human agent.' -ForegroundColor Magenta }
if (& $yes 'wants_refund') {
    # The refund policy decision combines jev's judgement with facts computed in code.
    if ($withinWindow)                                   { $refund = 'Offer a refund (inside the return window).' }
    elseif ($state.order.under_warranty -and (& $yes 'product_defect')) { $refund = "Outside the $returnWindowDays-day window ($daysSinceOrder days) but under warranty and defective: offer a warranty replacement or refund." }
    else                                                 { $refund = 'Outside the return window: explain policy.' }
    Write-Host "  => $refund" -ForegroundColor Magenta
}
if ((& $yes 'is_angry') -and (& $yes 'repeat_contact')) { Write-Host '  => Priority bump: angry repeat contact.' -ForegroundColor Magenta }
if ($uncertain) { Write-Host "  => Uncertain (near 0.5), needs a human read: $($uncertain -join ', ')" -ForegroundColor Magenta }
