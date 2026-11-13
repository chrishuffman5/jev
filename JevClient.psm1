#Requires -Version 7.0
<#
.SYNOPSIS
    Minimal PowerShell client for TypeSafe AI's Jev "System One" model.

.DESCRIPTION
    Wraps POST https://api.typesafe.ai/v1/systemone.
    - The API key is read from the SecretManagement vault (Get-Secret jev) and is kept
      as a SecureString end-to-end: Invoke-RestMethod -Authentication Bearer -Token
      accepts a SecureString, so the plaintext key never lands in a variable.
    - Question builders (New-JevChoice / New-JevScore / New-JevNoul) validate the
      documented limits client-side, because the published JSON Schema does not
      enforce the 255-option / 10-level maxima.
    - Retries 408/429/5xx (incl. 529) and connection errors with exponential backoff,
      honouring retry_after_ms / Retry-After. Never retries 400/422 or auth errors.
    - Treats BOTH 401 (invalid key) and 403 (missing key, observed defect) as
      credential errors.
#>

Set-StrictMode -Version Latest

$script:JevEndpoint      = 'https://api.typesafe.ai/v1/systemone'
$script:RetryableStatus  = @(408, 429) + (500..599)

#region Helpers -------------------------------------------------------------------

function Get-JevProperty {
    # StrictMode-safe property read from a PSCustomObject / hashtable.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function Get-JevApiKey {
    <#
    .SYNOPSIS
        Reads the Jev API key from the local SecretManagement vault as a SecureString.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param([string]$SecretName = 'jev')

    try {
        $secret = Get-Secret -Name $SecretName -ErrorAction Stop
    }
    catch {
        throw "Could not read secret '$SecretName' from the SecretManagement vault: $($_.Exception.Message)"
    }
    if ($secret -isnot [securestring]) {
        throw "Secret '$SecretName' is a [$($secret.GetType().Name)]; expected a SecureString."
    }
    $secret
}

function ConvertTo-JevProbabilityList {
    <#
    .SYNOPSIS
        Turns a probabilities object into a list of { Option; Probability } sorted high -> low.
    #>
    param([Parameter(Mandatory)] $Probabilities)
    $Probabilities.PSObject.Properties |
        ForEach-Object { [pscustomobject]@{ Option = $_.Name; Probability = [double]$_.Value } } |
        Sort-Object Probability -Descending
}

function Get-JevConfidenceBand {
    <#
    .SYNOPSIS
        Maps a confidence value onto the vendor's starting bands. Tune on your own data.
        > 0.9 act automatically | 0.5-0.9 confirm/review | < 0.5 route to a human
    #>
    param([Parameter(Mandatory)] [double]$Confidence,
          [double]$ActAbove = 0.9,
          [double]$ReviewAbove = 0.5)
    if ($Confidence -gt $ActAbove)     { 'act' }
    elseif ($Confidence -ge $ReviewAbove) { 'review' }
    else                               { 'human' }
}

#endregion

#region Question builders ---------------------------------------------------------

function New-JevChoice {
    <#
    .SYNOPSIS
        Choice: pick ONE option from an unordered set (2-255 options).
    .PARAMETER Instructions
        The question. A string, or a structured object/array (e.g. @{ question=...; focus=... }).
    .PARAMETER Criteria
        Ordered dictionary of option name -> description. Values may be a string, $null,
        an object (e.g. @{ what=...; not_for=...; examples=@(...) }) or an array.
        Use [ordered]@{} - option order is input to the model and can change answers.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Instructions,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Criteria
    )
    if ($Criteria.Count -lt 2 -or $Criteria.Count -gt 255) {
        throw "Choice criteria must have 2-255 options (got $($Criteria.Count))."
    }
    if ($Criteria -is [hashtable]) {
        Write-Warning 'Choice criteria is an unordered @{} hashtable; option order can affect answers. Use [ordered]@{}.'
    }
    [ordered]@{ type = 'choice'; instructions = $Instructions; criteria = $Criteria }
}

function New-JevScore {
    <#
    .SYNOPSIS
        Score: a position on an ORDERED rubric of 2-10 levels, lowest first.
    .PARAMETER Criteria
        Level descriptions, lowest first. Write each as a concrete situation, never a bare
        number or relative wording - each level is judged independently.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Instructions,
        [Parameter(Mandatory)] [object[]] $Criteria
    )
    if ($Criteria.Count -lt 2 -or $Criteria.Count -gt 10) {
        throw "Score criteria must have 2-10 levels (got $($Criteria.Count))."
    }
    [ordered]@{ type = 'score'; instructions = $Instructions; criteria = @($Criteria) }
}

function New-JevNoul {
    <#
    .SYNOPSIS
        Noul: a yes/no question. The answer is P(yes) in 0-1; there is no confidence field.
    .PARAMETER WhenTrue / WhenFalse
        Optional clarifications for a subtle yes/no boundary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Instructions,
        $WhenTrue,
        $WhenFalse
    )
    $q = [ordered]@{ type = 'noul'; instructions = $Instructions }
    if ($PSBoundParameters.ContainsKey('WhenTrue') -or $PSBoundParameters.ContainsKey('WhenFalse')) {
        $c = [ordered]@{}
        if ($PSBoundParameters.ContainsKey('WhenTrue'))  { $c['true']  = $WhenTrue }
        if ($PSBoundParameters.ContainsKey('WhenFalse')) { $c['false'] = $WhenFalse }
        $q['criteria'] = $c
    }
    $q
}

#endregion

#region API call ------------------------------------------------------------------

function Invoke-Jev {
    <#
    .SYNOPSIS
        Sends one state + a map of named questions to Jev and returns { model, answers, usage, requestId }.
    .PARAMETER State
        String, hashtable/object, or array. Filter it to what the decision needs.
    .PARAMETER Questions
        Ordered dictionary of name -> question (from New-JevChoice / New-JevScore / New-JevNoul).
    .PARAMETER Model
        'jev-latest' (rolls forward) or a pinned id such as 'jev-1.13.0' for audited decisions.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] $State,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Questions,
        [string] $Model = 'jev-latest',
        [securestring] $ApiKey,
        [ValidateRange(0, 10)] [int] $MaxRetries = 2,
        [ValidateRange(1, 300)] [int] $TimeoutSec = 30
    )

    if ($Questions.Count -eq 0) { throw 'Questions map must not be empty.' }
    if (-not $ApiKey) { $ApiKey = Get-JevApiKey }

    $body = [ordered]@{ state = $State; model = $Model; questions = $Questions } |
        ConvertTo-Json -Depth 32 -Compress
    Write-Verbose "Jev request body: $body"

    $attempt = 0
    while ($true) {
        $attempt++
        $status = 0; $headers = $null; $resp = $null; $netError = $null

        try {
            $resp = Invoke-RestMethod -Uri $script:JevEndpoint -Method Post `
                -Authentication Bearer -Token $ApiKey `
                -ContentType 'application/json; charset=utf-8' -Body $body `
                -TimeoutSec $TimeoutSec -SkipHttpErrorCheck `
                -StatusCodeVariable 'status' -ResponseHeadersVariable 'headers'
        }
        catch {
            $netError = $_   # DNS / TLS / timeout / connection reset - no HTTP status
        }

        $requestId = $null
        if ($headers -and $headers.ContainsKey('x-typesafe-request-id')) {
            $requestId = @($headers['x-typesafe-request-id'])[0]
        }

        # ---- success ----
        if (-not $netError -and $status -ge 200 -and $status -lt 300) {
            $resp | Add-Member -NotePropertyName requestId -NotePropertyValue $requestId -Force
            return $resp
        }

        # ---- classify failure ----
        $message   = if ($netError) { $netError.Exception.Message }
                     elseif ($resp -is [string]) { $resp }
                     else { Get-JevProperty $resp 'message' }
        $errorType = Get-JevProperty $resp 'error_type'
        $suffix    = if ($requestId) { " (request_id: $requestId)" } else { '' }

        if ($status -in 401, 403 -or $errorType -eq 'authentication_error') {
            # 401 = invalid key, 403 = missing key (observed; docs say 401 - typesafe-ai/skills#8)
            throw "Jev authentication failed (HTTP $status): $message. Check the 'jev' secret.$suffix"
        }
        if ($status -in 400, 422) {
            throw "Jev rejected the request (HTTP $status, $errorType): $message. Fix the payload; not retrying.$suffix"
        }

        $retryable = $netError -or ($status -in $script:RetryableStatus)
        if (-not $retryable -or $attempt -gt $MaxRetries) {
            $what = if ($netError) { 'connection error' } else { "HTTP $status" }
            throw "Jev call failed after $attempt attempt(s) ($what): $message$suffix"
        }

        # ---- backoff: retry_after_ms > Retry-After header > exponential 0.5s..5s with jitter ----
        $delayMs = $null
        $retryAfterMs = Get-JevProperty $resp 'retry_after_ms'
        if ($retryAfterMs) { $delayMs = [int]$retryAfterMs }
        elseif ($headers -and $headers.ContainsKey('Retry-After')) {
            $ra = 0
            if ([int]::TryParse(@($headers['Retry-After'])[0], [ref]$ra)) { $delayMs = $ra * 1000 }
        }
        if (-not $delayMs) {
            $base = [math]::Min(5000, 500 * [math]::Pow(2, $attempt - 1))
            $delayMs = [int]($base * (0.75 + (Get-Random -Maximum 0.5)))
        }
        $what = if ($netError) { 'connection error' } else { "HTTP $status" }
        Write-Warning "Jev $what; retrying in $delayMs ms (attempt $attempt of $($MaxRetries + 1))$suffix"
        Start-Sleep -Milliseconds $delayMs
    }
}

#endregion

#region Display -------------------------------------------------------------------

function Show-JevAnswer {
    <#
    .SYNOPSIS
        Pretty-prints one named answer (choice / score / noul).
    #>
    param([Parameter(Mandatory)] [string]$Name, [Parameter(Mandatory)] $Answer)

    switch ($Answer.type) {
        'choice' {
            Write-Host ("  {0,-22} choice  -> {1}  (confidence {2:N2}, band: {3})" -f `
                $Name, $Answer.choice, $Answer.confidence, (Get-JevConfidenceBand $Answer.confidence)) -ForegroundColor Cyan
            ConvertTo-JevProbabilityList $Answer.probabilities | Where-Object Probability -gt 0 |
                ForEach-Object { Write-Host ("      {0,-20} {1:P0}" -f $_.Option, $_.Probability) }
        }
        'score' {
            $level = [int][math]::Round([double]$Answer.score)
            $desc  = Get-JevProperty $Answer.legend "$level"
            if ($desc -isnot [string]) { $desc = $desc | ConvertTo-Json -Compress -Depth 5 }
            Write-Host ("  {0,-22} score   -> {1:N2}  (nearest level {2}: {3}; confidence {4:N2})" -f `
                $Name, $Answer.score, $level, $desc, $Answer.confidence) -ForegroundColor Yellow
            $Answer.probabilities.PSObject.Properties | Where-Object { [double]$_.Value -gt 0 } |
                ForEach-Object { Write-Host ("      level {0,-14} {1:P0}" -f $_.Name, [double]$_.Value) }
        }
        'noul' {
            $p = [double]$Answer.noul
            $read = if     ($p -ge 0.8)  { 'likely yes' }
                    elseif ($p -le 0.2)  { 'likely no' }
                    elseif ($p -gt 0.35 -and $p -lt 0.65) { 'UNCERTAIN' }
                    elseif ($p -ge 0.65) { 'leaning yes' }
                    else                 { 'leaning no' }
            Write-Host ("  {0,-22} noul    -> P(yes) = {1:N2}  ({2})" -f $Name, $p, $read) -ForegroundColor Green
        }
        default { Write-Host "  $Name : $($Answer | ConvertTo-Json -Compress -Depth 10)" }
    }
}

function Show-JevResponse {
    <#
    .SYNOPSIS
        Pretty-prints every answer in a Jev response plus model / usage metadata.
    #>
    param([Parameter(Mandatory)] $Response)
    foreach ($p in $Response.answers.PSObject.Properties) { Show-JevAnswer -Name $p.Name -Answer $p.Value }
    $u = $Response.usage
    Write-Host ("  [model {0} | input {1} tok | output {2} tok | request {3}]" -f `
        $Response.model, $u.input_tokens, $u.output_tokens, $Response.requestId) -ForegroundColor DarkGray
}

#endregion

Export-ModuleMember -Function Get-JevApiKey, Invoke-Jev, New-JevChoice, New-JevScore, New-JevNoul,
    Show-JevAnswer, Show-JevResponse, ConvertTo-JevProbabilityList, Get-JevConfidenceBand, Get-JevProperty
