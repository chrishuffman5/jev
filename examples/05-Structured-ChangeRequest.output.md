# Sample output: `05-Structured-ChangeRequest.ps1`

STRUCTURED example - JSON objects inside instructions and criteria (IT change management).

```powershell
.\examples\05-Structured-ChangeRequest.ps1
```

Captured on **2026-11-13** against model **jev-1.14.0** (exit code 0). Probabilities and confidence values can shift slightly between model versions, and `jev-latest` moves to newer versions over time. Request IDs will differ on every run.

> Lines starting with `=>` are decisions made by the script's own code from jev's answers. Jev itself only returns the choice, score and noul values.

```text
CHG-2041: Monthly Windows cumulative update on file servers
  change_type            choice  -> standard  (confidence 1.00, band: act)
      standard             100%
  risk                   score   -> 0.34  (nearest level 0: {"summary":"Low risk","signals":["few systems","tested template","quick, proven rollback","no sensitive data"]}; confidence 0.50)
      level 0              67%
      level 1              33%
  rollback_credible      noul    -> P(yes) = 0.95  (likely yes)
  touches_regulated_data noul    -> P(yes) = 0.22  (leaning no)
  [model jev-1.14.0 | input 922 tok | output 95 tok | request req_01a1d7a1b9b57407ab71ed925dba5573]
  => Auto-approve (standard template)

CHG-2042: Rotate expired TLS certificate on the public API gateway
  change_type            choice  -> emergency  (confidence 1.00, band: act)
      emergency            100%
  risk                   score   -> 1.67  (nearest level 2: {"summary":"High risk","signals":["many dependent apps","sensitive or regulated data","cut-over with limited rollback","cross-platform migration"]}; confidence 0.51)
      level 0              6%
      level 1              21%
      level 2              73%
  rollback_credible      noul    -> P(yes) = 0.12  (likely no)
  touches_regulated_data noul    -> P(yes) = 0.34  (leaning no)
  [model jev-1.14.0 | input 906 tok | output 97 tok | request req_01a1d7a1bc8e7d83b4f44135e4143e4e]
  => ECAB: on-call manager approves now, retrospective CAB review

CHG-2043: Migrate the HR database from SQL Server 2016 to Azure SQL Managed Instance
  change_type            choice  -> normal  (confidence 1.00, band: act)
      normal               100%
  risk                   score   -> 1.99  (nearest level 2: {"summary":"High risk","signals":["many dependent apps","sensitive or regulated data","cut-over with limited rollback","cross-platform migration"]}; confidence 0.98)
      level 1              1%
      level 2              99%
  rollback_credible      noul    -> P(yes) = 0.89  (likely yes)
  touches_regulated_data noul    -> P(yes) = 0.98  (likely yes)
  [model jev-1.14.0 | input 967 tok | output 95 tok | request req_01a1d7a1bdab7fcc8ef99e9c4595e4ca]
  => Schedule for weekly CAB + data-protection sign-off
```
