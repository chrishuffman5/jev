# Sample output: `01-Choice-TicketRouting.ps1`

CHOICE example - route support tickets to exactly one team.

```powershell
.\examples\01-Choice-TicketRouting.ps1
```

Captured on **2026-11-13** against model **jev-1.14.0** (exit code 0). Probabilities and confidence values can shift slightly between model versions, and `jev-latest` moves to newer versions over time. Request IDs will differ on every run.

> Lines starting with `=>` are decisions made by the script's own code from jev's answers. Jev itself only returns the choice, score and noul values.

```text
TICKET: I was charged twice for order #4471 this morning. Please refund the duplicate charge.
  team                   choice  -> billing  (confidence 1.00, band: act)
      billing              100%
  [model jev-1.14.0 | input 444 tok | output 59 tok | request req_01a1d7a17dd17f79b6583993d7268e95]
  => Auto-assign to 'billing'.

TICKET: The tracking page has said "label created" for nine days. Where is my package?
  team                   choice  -> shipping  (confidence 1.00, band: act)
      shipping             100%
  [model jev-1.14.0 | input 442 tok | output 59 tok | request req_01a1d7a180227ba7aa0b857e72f6667c]
  => Auto-assign to 'shipping'.

TICKET: I can't log in to the app - it keeps saying my session expired, even right after a password reset.
  team                   choice  -> technical  (confidence 1.00, band: act)
      technical            100%
  [model jev-1.14.0 | input 447 tok | output 59 tok | request req_01a1d7a18175762fb7840b75a95fb9a6]
  => Auto-assign to 'technical'.

TICKET: My package arrived crushed and the blender inside is cracked. Also, why was I billed for express shipping when it took two weeks?
  team                   choice  -> returns  (confidence 0.83, band: review)
      returns              86%
      shipping             9%
      billing              4%
      other                1%
  [model jev-1.14.0 | input 450 tok | output 59 tok | request req_01a1d7a1826b71cd94f594b20abad0c6]
  => Suggest 'returns' (runner-up 'shipping'); agent confirms.
```
