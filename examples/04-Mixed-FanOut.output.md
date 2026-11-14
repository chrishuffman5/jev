# Sample output: `04-Mixed-FanOut.ps1`

MIXED example - Choice + Score + Noul in ONE call, then route and prioritise in code.

```powershell
.\examples\04-Mixed-FanOut.ps1
```

Captured on **2026-11-13** against model **jev-1.14.0** (exit code 0). Probabilities and confidence values can shift slightly between model versions, and `jev-latest` moves to newer versions over time. Request IDs will differ on every run.

> Lines starting with `=>` are decisions made by the script's own code from jev's answers. Jev itself only returns the choice, score and noul values.

```text
ANSWERS:
  category               choice  -> integration_failure  (confidence 1.00, band: act)
      integration_failure  100%
  urgency                score   -> 2.97  (nearest level 3: Hard business deadline within days, or many people blocked right now; confidence 0.97)
      level 2              3%
      level 3              97%
  impact                 score   -> 3.00  (nearest level 3: Affects the entire organisation or has payroll / legal / financial consequences; confidence 1.00)
      level 3              100%
  has_deadline           noul    -> P(yes) = 0.81  (likely yes)
  wants_workaround       noul    -> P(yes) = 0.79  (leaning yes)
  questions_status       noul    -> P(yes) = 0.96  (likely yes)
  is_security_issue      noul    -> P(yes) = 0.03  (likely no)
  [model jev-1.14.0 | input 729 tok | output 167 tok | request req_01a1d7a1ad2675899d38e120954f6df4]

ROUTING (computed in code):
  urgency normalised 0.99 | impact normalised 1.00 | plan boost 0.1 => priority 0.99
  => Queue: Integrations engineering | P1 - respond within 1 hour
  => Include a manual export workaround in the first reply.
  => Check whether the status page is missing an incident.
```
