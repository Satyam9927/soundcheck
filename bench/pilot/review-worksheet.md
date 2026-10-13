# Advisory review worksheet

Copy privately for a separately authorized evaluation. This worksheet is not
consumed by the runner, not a new contract format, and not proof evidence. Do
not commit private configurations, authorization records, identities, findings,
or credentials to this repository. Synthetic exercises must remain labelled
synthetic; the repository does not claim that any real pilot has taken place.

## Input and permission record

- Pseudonymous case ID and origin category:
- Private reference to processing authorization and permitted scope:
- Permission to retain/share summary, detailed report, or evidence bundle:
- Retention period, access owner, and deletion responsibility:
- Config digest and separately reviewed canonical contract digest:
- Contract approval record, reviewer, and approval date (keep private):
- Time spent understanding intent and authoring/reviewing the contract:
- Kong version/router and how each relevant environment assumption was checked:
- Verifier/profile/solver baseline:

## Independent review

- Verifier outcome, assurance category, and finding codes:
- Review category: confirmed issue / intended exception / approximation
  candidate / unsupported / unresolved / no modeled violation found:
- Independently established expected behavior and basis:
- Does the reported candidate identify useful request/route/service context?
- Was any target validation separately authorized? If none, record “not run.”
- Were functionality and relevant destination/routing expectations represented
  by the approved contract? Record missing intent instead of weakening it.
- What would the existing review/test process have found or missed, and what
  evidence supports that comparison?
- Time spent reviewing this result and deciding the next action:
- Proposed follow-up (no automatic repair or contract change):

## Aggregate evaluation cautions

Keep every scheduled case in the denominator, including parse failures and
unsupported/unknown results. Separate origin categories and explain selection
bias. Never count unresolved candidates as confirmed vulnerabilities or false
alarms. A false-alarm rate requires independently adjudicated cases; missed
findings require an independent reference set. Runtime and contract-authoring
effort are observations, not assurances. Evaluate whether findings are useful
without presenting example-fixture results as production evidence.

Before sharing, review IDs, hashes, counts, timing and finding codes for sensitive
information. These fields are minimized, not anonymous. Any richer diagnostic
or evidence artifact needs its own sharing decision.
