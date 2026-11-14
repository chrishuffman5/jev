# JevClient

A PowerShell module for TypeSafe AI's **jev** System One model.

Jev is a decision model, not a chat model. You give it some **state** (a ticket, a log entry, a change request) and a set of typed **questions**. It returns structured answers with calibrated probabilities that your script can branch on. There is no text to parse and no prompt to coax.

```powershell
Import-Module JevClient

$r = Invoke-Jev -State 'I was charged twice for order #4471. Please refund the duplicate.' -Questions ([ordered]@{
    team   = New-JevChoice 'Which team should handle this?' ([ordered]@{ billing = 'Charges and refunds'; shipping = 'Delivery'; other = 'Anything else' })
    urgent = New-JevNoul   'Does the customer need a response today?'
})

$r.answers.team.choice        # billing
$r.answers.team.confidence    # 1.0
$r.answers.urgent.noul        # P(yes), 0..1
```

The module is designed to drop into the PowerShell you already have: scheduled tasks, triage scripts, CSV pipelines and approval workflows. Your code keeps control flow, math and thresholds. Jev answers the narrow judgment calls inside it.

---

## Contents

- [Prerequisites](#prerequisites)
- [First-time setup: secret vault and API key](#first-time-setup-secret-vault-and-api-key)
- [Install the module](#install-the-module)
- [The three question types](#the-three-question-types)
- [Using JevClient in existing workstreams](#using-jevclient-in-existing-workstreams)
- [Function reference](#function-reference)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Important notes](#important-notes)

---

## Prerequisites

| Requirement | Why |
|---|---|
| **PowerShell 7.0+** (`pwsh`) | The module uses `Invoke-RestMethod -Authentication Bearer -Token <SecureString>` and `-SkipHttpErrorCheck`, which Windows PowerShell 5.1 doesn't have. |
| **Microsoft.PowerShell.SecretManagement** | Reads the API key from a vault (`Get-Secret`). |
| **A vault extension**, e.g. **Microsoft.PowerShell.SecretStore** | Somewhere to keep the key. SecretStore is a local, encrypted, cross-platform vault. Azure Key Vault, KeePass and others also work. |
| **A jev API key** from [typesafe.ai](https://typesafe.ai) | jev is in waitlisted early access. |

Check your PowerShell version:

```powershell
$PSVersionTable.PSVersion     # needs 7.0 or later
```

---

## First-time setup: secret vault and API key

You only do this once per machine and user account. Afterwards, `Get-JevApiKey` (and `Invoke-Jev`, which calls it for you) finds the key automatically.

### 1. Install SecretManagement and SecretStore

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
```

> If you use PSResourceGet, `Install-PSResource Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser` does the same thing.

### 2. Register a vault

Skip this step if `Get-SecretVault` already lists a vault you want to use.

```powershell
Register-SecretVault -Name LocalStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
Get-SecretVault
```

The first time you touch the store, SecretStore asks you to create a **store password**. This password encrypts the vault and is separate from your jev API key.

### 3. (Optional) Configure how the store unlocks

The default configuration requires the store password and asks for it again after 15 minutes. For interactive use, you can lengthen that window:

```powershell
Set-SecretStoreConfiguration -Authentication Password -PasswordTimeout 3600   # unlocked for 1 hour
```

When the store is locked, unlock it with:

```powershell
Unlock-SecretStore
```

See [Unattended use](#unattended-use-scheduled-tasks-ci-services) before you change these settings for automation.

### 4. Create the `jev` secret

Run `Set-Secret` **without** a `-Secret` value. PowerShell then prompts for the key with masked input, so the key never appears on screen or in your PSReadLine history file:

```powershell
Set-Secret -Name jev -Vault LocalStore
# Enter secret value: ********************************
```

Alternatively, read the key into a SecureString first:

```powershell
Set-Secret -Name jev -Vault LocalStore -Secret (Read-Host 'jev API key' -AsSecureString)
```

> **Don't** run `Set-Secret -Name jev -Secret 'ts_live_...'`. A literal string on the command line is saved to your history file in plain text.

You can give the secret a different name. If you do, pass it to the module with `Get-JevApiKey -SecretName <name>`.

### 5. Verify

```powershell
Get-SecretInfo -Name jev          # shows the name, type and vault
Get-Secret -Name jev              # should print: System.Security.SecureString
```

Then make a real call. It costs a few hundred input tokens:

```powershell
Import-Module JevClient
Invoke-Jev -State 'Can I talk to a real person, please?' -Questions ([ordered]@{
    wants_human = New-JevNoul 'Is the customer asking for a human agent?'
}) | Show-JevResponse
```

### Rotating or removing the key

```powershell
Set-Secret    -Name jev -Vault LocalStore     # overwrite with the new key (prompts)
Remove-Secret -Name jev -Vault LocalStore     # delete it
```

### Same secret name in several vaults

If more than one vault has a `jev` secret, `Get-Secret` searches the **default vault first**. To pick a specific vault:

```powershell
$key = Get-JevApiKey -Vault LocalStore
Invoke-Jev -State $s -Questions $q -ApiKey $key
```

---

## Install the module

The module lives in the `JevClient\` folder of this repo. It's a standard script module with a manifest.

### Option A: use it straight from the clone

```powershell
git clone https://github.com/chrishuffman5/jev.git
Import-Module .\jev\JevClient
```

### Option B: install it for your user account (recommended)

Copy the folder into your user module path. `Import-Module JevClient` then works from any session or script, and PowerShell will **autoload** the module the first time you call one of its functions.

```powershell
git clone https://github.com/chrishuffman5/jev.git
$userModules = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules'
New-Item -ItemType Directory -Path $userModules -Force | Out-Null
Copy-Item .\jev\JevClient (Join-Path $userModules 'JevClient') -Recurse -Force

Get-Module -ListAvailable JevClient
```

> `GetFolderPath('MyDocuments')` respects OneDrive folder redirection. On Linux and macOS, the user module path is `~/.local/share/powershell/Modules`.

To update the module later, run `git pull` in the clone and repeat the `Copy-Item`.

### Discover what's in it

```powershell
Get-Command -Module JevClient
Get-Help Invoke-Jev -Full
Get-Help New-JevScore -Parameter Criteria
```

---

## The three question types

Choose the type based on the shape of the answer your code will branch on.

| You need | Function | You get back | Limits |
|---|---|---|---|
| **One option** from a set of categories | `New-JevChoice` | `.choice`, `.probabilities`, `.confidence` | 2–255 options |
| **A position** on an ordered scale (severity, risk, urgency) | `New-JevScore` | `.score` (can be fractional), `.probabilities`, `.legend`, `.confidence` | 2–10 levels, lowest first |
| **Yes or no** for a single condition | `New-JevNoul` | `.noul`, the probability of yes from 0 to 1. There is no `.confidence`. | — |

You can mix all three in one `Invoke-Jev` call. Every question is evaluated against the same state, in parallel, so asking extra questions barely changes the response time.

**Rules of thumb**

- **Choice:** always give the complete list of options, plus an `other` option. Use `[ordered]@{}`, because option order is part of the input.
- **Score:** write each level as a concrete situation, such as `'Broken feature, but a workaround exists'`, not `'2'` or `'worse than the previous level'`. Each Score should measure only one thing. Use the score to set thresholds or to rank, not as a precise measurement.
- **Noul:** ask about one condition per question. A value near 0.5 means *uncertain*, not "medium".
- **Do the math in code:** counting, dates and arithmetic belong in your script. Put the *result* in state (for example `within_return_window = $true`) and ask jev only for the judgment call.
- **Gate on confidence in code.** These are the vendor's starting bands, available as `Get-JevConfidenceBand`:

  | Confidence | Default band | Typical action |
  |---|---|---|
  | above 0.9 | `act` | act automatically |
  | 0.5 to 0.9 | `review` | a person confirms first |
  | below 0.5 | `human` | a person decides |

---

## Using JevClient in existing workstreams

The pattern is always the same: **your script collects the facts, jev makes the judgment call, and your script acts on it.** Here are a few common integrations.

### Classify a CSV in a pipeline

```powershell
Import-Module JevClient
$key = Get-JevApiKey                                   # read the vault once and reuse the key

$questions = [ordered]@{
    team = New-JevChoice 'Which team should handle this ticket?' ([ordered]@{
        billing   = 'Charges, refunds, invoices'
        technical = 'Errors, login problems, bugs'
        shipping  = 'Delivery and tracking'
        other     = 'Anything else'
    })
    urgent = New-JevNoul 'Does the customer need a response today?'
}

Import-Csv .\tickets.csv | ForEach-Object {
    $r = Invoke-Jev -State $_.Body -Questions $questions -ApiKey $key
    [pscustomobject]@{
        Id         = $_.Id
        Team       = $r.answers.team.choice
        Confidence = [math]::Round($r.answers.team.confidence, 2)
        Band       = Get-JevConfidenceBand $r.answers.team.confidence
        Urgent     = $r.answers.urgent.noul -ge 0.8
    }
} | Export-Csv .\tickets-routed.csv -NoTypeInformation
```

### Add a judgment step to an existing script

Pass related facts as an object. Named fields keep the different records clear to the model.

```powershell
$state = [ordered]@{
    request   = $change.Description
    systems   = $change.Systems
    rollback  = $change.RollbackPlan
}

$r = Invoke-Jev -State $state -Questions ([ordered]@{
    regulated = New-JevNoul 'Does this change touch personal, payroll, health, or payment data?'
})

if ($r.answers.regulated.noul -ge 0.7) {
    Add-ApprovalStep -Change $change -Approver 'DataProtection'     # your existing function
}
```

### Always have a deterministic fallback

Treat jev like any other external dependency. If it's unavailable, your workflow should fall back to the path it would have taken without it:

```powershell
try {
    $r     = Invoke-Jev -State $ticket.Body -Questions $questions -ApiKey $key
    $route = if ((Get-JevConfidenceBand $r.answers.team.confidence) -eq 'act') { $r.answers.team.choice } else { 'triage' }
}
catch {
    Write-Warning "jev unavailable, using manual triage: $_"
    $route = 'triage'
}
```

`Invoke-Jev` already retries rate limits (429), timeouts (408), server errors (5xx) and dropped connections with backoff. It throws straight away on bad requests (400/422) and credential errors (401/403).

### Keep question definitions in one place

Question wording is production logic. Define your questions in a shared file, review changes to it like code, and dot-source it wherever you need it:

```powershell
# Questions.ps1
$script:TicketQuestions = [ordered]@{
    team    = New-JevChoice ...
    urgency = New-JevScore  ...
}

# Any script
. "$PSScriptRoot\Questions.ps1"
$r = Invoke-Jev -State $body -Questions $TicketQuestions
```

### Unattended use (scheduled tasks, CI, services)

SecretStore's default password prompt doesn't work in a non-interactive session. You have three options:

1. **Use a vault that doesn't need an interactive unlock**, such as Azure Key Vault (`Az.KeyVault` extension) with a managed identity, and register it under SecretManagement. The module code stays the same.
2. **Get the key some other way** and pass it in: `Invoke-Jev -ApiKey $secureString ...`. Any SecureString works.
3. **Turn off the SecretStore password** for a dedicated service account:
   ```powershell
   Set-SecretStoreConfiguration -Authentication None -Interaction None
   ```
   The store is still encrypted and tied to that user account. However, any process running as that account can read the key, so only do this for an account that exists solely for the job.

### Pin the model for audited decisions

`jev-latest` rolls forward to new model versions. For decisions you may need to explain later, pin a version and log it alongside the answers:

```powershell
$r = Invoke-Jev -State $s -Questions $q -Model 'jev-1.14.0'
$r.model, $r.requestId      # log these along with the state and the answers
```

---

## Function reference

| Function | Purpose |
|---|---|
| `Invoke-Jev -State <obj> -Questions <map> [-Model] [-ApiKey] [-MaxRetries] [-TimeoutSec]` | Sends one state and a map of named questions. Returns `{ model, answers, usage, requestId }`. |
| `New-JevChoice -Instructions <q> -Criteria <ordered map>` | Builds a Choice question and checks the 2–255 option limit. |
| `New-JevScore -Instructions <q> -Criteria <levels[]>` | Builds a Score question (levels lowest first) and checks the 2–10 level limit. |
| `New-JevNoul -Instructions <q> [-WhenTrue] [-WhenFalse]` | Builds a yes/no question, with optional criteria to clarify where the yes/no line falls. |
| `Get-JevApiKey [-SecretName jev] [-Vault <name>]` | Reads the API key from SecretManagement as a SecureString. |
| `Get-JevConfidenceBand <confidence> [-ActAbove 0.9] [-ReviewAbove 0.5]` | Maps a confidence value to `act`, `review` or `human`. |
| `ConvertTo-JevProbabilityList <probabilities>` | Turns the probabilities into a list of `{Option, Probability}` sorted from highest to lowest. |
| `Show-JevResponse <response>` / `Show-JevAnswer -Name -Answer` | Prints the answers in a readable form for the console. |
| `Get-JevProperty <object> <name>` | Reads a property safely under StrictMode. |

Instructions and criteria values can also be **structured objects** instead of plain strings. For example, a Choice option can be `[ordered]@{ what = '...'; not_for = '...'; examples = @(...) }`. See `examples\05-Structured-ChangeRequest.ps1`.

---

## Examples

The `examples\` folder has runnable scripts. Each one imports the module from the repo, so it works without installing anything.

| Script | Question types | What it shows | Sample output |
|---|---|---|---|
| `01-Choice-TicketRouting.ps1` | Choice | A complete option list with `other`, act/review/human bands, and a runner-up on a split decision | [view](examples/01-Choice-TicketRouting.output.md) |
| `02-Score-BugSeverity.ps1` | Score | Rubric levels written as concrete situations, rounding, normalizing, thresholds scaled to the consequence, ranking | [view](examples/02-Score-BugSeverity.output.md) |
| `03-Noul-YesNoChecks.ps1` | Noul | Several yes/no checks in one call, true/false criteria, date math done in code | [view](examples/03-Noul-YesNoChecks.output.md) |
| `04-Mixed-FanOut.ps1` | All three | One state with many questions, a composite priority calculated in code, a consistency check across answers | [view](examples/04-Mixed-FanOut.output.md) |
| `05-Structured-ChangeRequest.ps1` | All three | Structured JSON in questions: ITIL change type, risk, and approval routing | [view](examples/05-Structured-ChangeRequest.output.md) |
| `06-Gating-ShellCommands.ps1` | Noul + Score | Jev as one layer of several: a deterministic deny-list, then jev, then a human. **Nothing is executed.** | [view](examples/06-Gating-ShellCommands.output.md) |

The sample outputs are real runs captured against `jev-1.14.0`. Your probabilities may differ slightly.

```powershell
.\examples\01-Choice-TicketRouting.ps1
.\examples\02-Score-BugSeverity.ps1 -Model jev-1.14.0
```

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `Could not read secret 'jev'` | The vault is locked. Run `Unlock-SecretStore`. Otherwise the secret doesn't exist; check `Get-SecretInfo -Name jev`. |
| `Secret 'jev' is a [Hashtable]; expected a SecureString` | The secret was stored as the wrong type. Re-create it with `Set-Secret -Name jev` and enter the key at the prompt. |
| `jev authentication failed (HTTP 401)` | The key is invalid or has been revoked. Rotate it with `Set-Secret`. |
| `jev authentication failed (HTTP 403)` | The key is missing from the request. In practice the API returns 403 for this, even though the docs say 401. |
| `jev rejected the request (HTTP 400/422)` | The question shape is wrong, for example an empty criteria list or the wrong type. Fix the payload; retrying won't help. Use `-Verbose` to see the request body. |
| Repeated `retrying in N ms` warnings | Rate limiting or a service problem. Check [status.typesafe.ai](https://status.typesafe.ai). |
| `The term 'Invoke-Jev' is not recognized` | The module isn't on your `$env:PSModulePath`. See [Install the module](#install-the-module). |
| Errors about `-Authentication` or `-SkipHttpErrorCheck` | You're running Windows PowerShell 5.1. Use `pwsh` (PowerShell 7+). |

Include the `request_id` from error messages or `$r.requestId` when you contact TypeSafe support.

---

## Important notes

- **Your data leaves the machine.** The state and the questions are sent to TypeSafe's API. Strip secrets and regulated personal data from state before calling. TypeSafe says it doesn't train on API input; check their [privacy policy](https://typesafe.ai/legal/privacy-policy) and terms for your situation.
- **Cost:** you're billed for input tokens only (state plus question text); output is free. Keep state to what the decision actually needs. See [typesafe.ai](https://typesafe.ai) for current pricing.
- **Jev isn't a security boundary.** Prompt injection in the state can change its verdicts. Never make it the only gate on a destructive or privileged action. Combine it with deterministic checks and human approval, as in `06-Gating-ShellCommands.ps1`.
- **Retrying won't change an answer.** Jev returns essentially the same answer for the same input. If an answer is wrong, rewrite the question or escalate to a person.
- **Model versions:** `jev-latest` resolved to `jev-1.14.0` as of 2026-11-13.
