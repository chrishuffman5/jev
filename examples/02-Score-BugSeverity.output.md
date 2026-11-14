# Sample output: `02-Score-BugSeverity.ps1`

SCORE example - place bug reports on an ordered severity rubric.

```powershell
.\examples\02-Score-BugSeverity.ps1
```

Captured on **2026-11-13** against model **jev-1.14.0** (exit code 0). Probabilities and confidence values can shift slightly between model versions, and `jev-latest` moves to newer versions over time. Request IDs will differ on every run.

> Lines starting with `=>` are decisions made by the script's own code from jev's answers. Jev itself only returns the choice, score and noul values.

```text
BUG-101 : The "Contact us" link in the footer is underlined in blue instead of grey on the pricing page.
  severity               score   -> 0.00  (nearest level 0: Cosmetic only: typo, misaligned element, wrong colour; no functional effect; confidence 1.00)
      level 0              100%
  [model jev-1.14.0 | input 407 tok | output 17 tok | request req_01a1d7a18f2e7a6d86e3e9a645f0d00a]
  => Backlog

BUG-102 : Exporting a report to CSV fails with a 500 error. Copy-pasting the table into Excel works fine for now.
  severity               score   -> 2.00  (nearest level 2: Broken or degraded feature, but a reasonable workaround exists; confidence 1.00)
      level 2              100%
  [model jev-1.14.0 | input 414 tok | output 17 tok | request req_01a1d7a190dd76de9ae9f411205765ea]
  => Backlog

BUG-103 : Since this morning's deploy, every customer checking out with a saved card is being charged twice.
  severity               score   -> 4.00  (nearest level 4: Outage, data loss, security exposure, or money charged incorrectly for many users; confidence 1.00)
      level 4              100%
  [model jev-1.14.0 | input 404 tok | output 17 tok | request req_01a1d7a192457e99aa8e97e87ecb7715]
  => PAGE ON-CALL

BUG-104 : Users on Safari can't upload profile photos - the button does nothing. Chrome users are fine.
  severity               score   -> 2.90  (nearest level 3: Core feature broken for some users with no workaround; they cannot complete their task; confidence 0.92)
      level 2              10%
      level 3              90%
  [model jev-1.14.0 | input 404 tok | output 17 tok | request req_01a1d7a193c67f0ba354ce35e91df094]
  => Next sprint, high priority

Ranked by severity (score is for ordering, not magnitude):

Bug     Score Level Normalized Confidence Action
---     ----- ----- ---------- ---------- ------
BUG-103  4.00     4       1.00       1.00 PAGE ON-CALL
BUG-104  2.90     3       0.72       0.92 Next sprint, high priority
BUG-102  2.00     2       0.50       1.00 Backlog
BUG-101  0.00     0       0.00       1.00 Backlog
```
