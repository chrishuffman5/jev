# Jev decision-model examples (PowerShell)

PowerShell 7 examples for TypeSafe AI's **jev** System One model (`POST https://api.typesafe.ai/v1/systemone`).
Jev returns typed answers with probabilities, not text. Your code makes the decision.

## Setup

The API key is read from the local SecretManagement vault:

```powershell
Get-Secret jev            # must return a SecureString
```

`JevClient.psm1` passes that SecureString straight to `Invoke-RestMethod -Authentication Bearer -Token`, so the plaintext key is never stored in a variable.

## Run

```powershell
.\examples\01-Choice-TicketRouting.ps1
.\examples\02-Score-BugSeverity.ps1 -Model jev-1.14.0   # pin a model id
```

| Script | Primitive(s) | Shows |
|---|---|---|
| `01-Choice-TicketRouting.ps1` | Choice | Full taxonomy with an `other` option, `[ordered]` options, confidence bands (act / review / human), runner-up on a split |
| `02-Score-BugSeverity.ps1` | Score | Rubric levels written as concrete situations, rounding, normalising, thresholds scaled to consequence, ranking |
| `03-Noul-YesNoChecks.ps1` | Noul | Several yes/no checks in one call, true/false criteria, date math done in code with the result passed in state, 0.5 = uncertain |
| `04-Mixed-FanOut.ps1` | All three | One state, many questions, composite priority calculated in code, a consistency check across answers |
| `05-Structured-ChangeRequest.ps1` | All three | JSON in questions: `{question, focus}`, `{what, not_for, examples}` and `{summary, signals}` (ITIL change type and risk) |
| `06-Gating-ShellCommands.ps1` | Noul + Score | Jev as one layer: deterministic deny-list, then jev, then a human. Tool output is kept out of state. **Nothing is executed.** |

## Module (`JevClient.psm1`)

- `New-JevChoice` / `New-JevScore` / `New-JevNoul` build questions and check the documented limits before sending: 2–255 options for Choice, 2–10 levels for Score.
- `Invoke-Jev -State <obj> -Questions <ordered map> [-Model jev-latest]` sends the request:
  - 408, 429 and 5xx errors are retried with backoff, honouring `retry_after_ms` and `Retry-After`.
  - 400 and 422 errors are never retried.
  - Both 401 (invalid key) and 403 (missing key) are treated as credential errors.
- `Show-JevResponse`, `Get-JevConfidenceBand` and `ConvertTo-JevProbabilityList` help display and read results.

## Notes

- Every run spends real input tokens. Output tokens are free.
- `jev-latest` rolls forward. It resolved to `jev-1.14.0` on 2026-11-13. Pin a model id for decisions you need to audit.
- Jev is not a security boundary, because prompt injection can change its verdicts. Never use it as the only gate on a destructive action.
