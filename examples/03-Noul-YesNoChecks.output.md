# Sample output: `03-Noul-YesNoChecks.ps1`

NOUL example - batched yes/no checks on a customer message.

```powershell
.\examples\03-Noul-YesNoChecks.ps1
```

Captured on **2026-11-13** against model **jev-1.14.0** (exit code 0). Probabilities and confidence values can shift slightly between model versions, and `jev-latest` moves to newer versions over time. Request IDs will differ on every run.

> Lines starting with `=>` are decisions made by the script's own code from jev's answers. Jev itself only returns the choice, score and noul values.

```text
STATE:
{
  "customer_message": "This is the third time I'm writing about these headphones. The left side cut out after a month. I want my money back, and honestly if nobody fixes this I'll be talking to my lawyer. Can someone who actually works there call me?",
  "order": {
    "item": "Wireless headphones",
    "days_since_order": 41,
    "within_return_window": false,
    "under_warranty": true
  }
}

  wants_refund           noul    -> P(yes) = 0.99  (likely yes)
  wants_human            noul    -> P(yes) = 0.98  (likely yes)
  threatens_legal        noul    -> P(yes) = 0.98  (likely yes)
  is_angry               noul    -> P(yes) = 0.96  (likely yes)
  repeat_contact         noul    -> P(yes) = 0.92  (likely yes)
  product_defect         noul    -> P(yes) = 0.99  (likely yes)
  asks_for_discount      noul    -> P(yes) = 0.02  (likely no)
  [model jev-1.14.0 | input 551 tok | output 133 tok | request req_01a1d7a1a1347936a5baed07343c2d30]

DECISIONS:
  => Flag for the escalations team (legal language present).
  => Schedule a call-back from a human agent.
  => Outside the 30-day window (41 days) but under warranty and defective: offer a warranty replacement or refund.
  => Priority bump: angry repeat contact.
```
