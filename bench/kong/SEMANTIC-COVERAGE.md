# Checked semantic evidence inventory

[`semantic-coverage.yaml`](semantic-coverage.yaml) maps every feature in the
compiled `kong-traditional-http-v11` profile to a semantic rule, immutable Kong
3.9.3 source references, lowering ownership, approximation direction, local
regressions, available target samples and remaining gaps. It is internal,
experimental test infrastructure, not a public verifier result schema.

The current inventory has **42 entries: 18 source-only, 23 modeled-sample and
one boundary-sample**. These are evidence categories, not a coverage percentage
or 42 independently established semantic guarantees. One probe can inform
several feature rows; reference counts are not distinct target observations.
This inventory covers the assurance feature catalogue, not every solver,
equivalence, frozen-contract or adapter requirement in the repository; those
retain their separate acceptance tests.

| Evidence category | What its references establish | What they do not establish |
| --- | --- | --- |
| `source-only` | Local source/regression references exist; no target probe is claimed | Independent execution of that behavior in Kong |
| `modeled-samples` | Named exact/conservative probes exist for each declared router | Complete feature coverage or exactness of a conservative model |
| `boundary-samples` | Named unsupported probes exercise target observations and the whole-config unknown boundary | Modeled decision agreement or the individual cause of rejection |

All entries retain explicit gaps. There is no `complete` evidence level.
`source-only` does **not** mean every cited source independently proves the
feature: for example, the GraphQL commercial-plugin row cites OSS plugin
infrastructure and explicitly records the missing proprietary semantic source.

## What the gate checks

`test/semantic_acceptance_t.ml`, run by `dune test`, rejects profile identity,
feature-set and class drift; missing/duplicate/obsolete entries; floating source
URLs; absent or noncanonical local file references; missing control anchors;
nonexistent or duplicate probe identities; and false model-class/router/evidence
declarations. A probe name may occur in separate rows for disjoint router
flavors, but never twice for the same flavor. Unsupported rows cannot be credited
as modeled agreement. Probe references use the harness's strict fifteen-column
format, including its source-IP column.

The internal YAML subset rejects literal NUL and **every backslash character
anywhere in the file, including comments**. Escapes such as `\0`, `\x00`,
`\u0000` and `\U00000000` must not let the YAML binding truncate a scalar
before identity/reference validation. Use literal UTF-8 text and YAML single
quoting (doubling an embedded apostrophe), not backslash escapes. This restriction
belongs only to the inventory reader; it does not change shared config or
frozen-contract parsing.

The gate's negative controls corrupt inputs **in memory**, including missing
features, wrong profiles, source revisions, files, probes and router observations,
class downgrades, unsupported-as-agreement claims, an invented `complete` level,
duplicate identities, empty/malformed matrices and missing evidence gaps.
Parser controls reject literal/escaped NUL, other backslash escapes and
backslashes in comments, while preserving permitted literal paths, quotes and
UTF-8 text.
They do not edit or weaken the approved target expectations. The executable
prints its checked entry and rejected-corruption counts.

For a focused check from the repository root:

```sh
eval "$(opam env)"
dune exec test/semantic_acceptance_t.exe -- . bench/kong/semantic-coverage.yaml
```

This check does not run Docker, contact a target, browse source URLs, execute the
referenced regressions, or decide whether their contents support the prose.
The complete regression gate and the separate pinned real-Kong conformance gate
remain required. File existence and source pinning cannot replace independent
semantic review; a reference is not a certificate.

## Existing mutation evidence

The four referenced controls in `test/approximation_refinement_t.ml` reject
deliberately incorrect abstract decision semantics: deny-overrides aggregation,
unconditional default-Allow fallthrough, incomplete-match suppression and mixed
priority shapes. They validate the independent finite refinement oracle's
sensitivity, **not** every feature's parsing or lowering into that abstraction.

Harness controls test observation/class/bound checking and lifecycle failures.
They are not credited as feature-specific semantic mutation coverage. Most
individual feature rows still lack dedicated semantic mutations; their gaps say
so rather than turning validator corruption checks into semantic evidence.

## Priority gaps that remain visible

- Authentication samples cover Key Auth, Basic Auth and JWT with public synthetic
  credentials, not all ten recognized plugins, production credential stores,
  expiration, provider availability, Consumer policy or multi-plugin identity.
  Basic/JWT negative samples are malformed credentials, not well-formed wrong
  passwords or signatures.
- IP samples use an explicit fixture-only trusted client-IP setup. They do not
  prove a deployment's source-integrity assumption, IPv6, or every CIDR mixture.
- Conditional termination samples cover headers, not query triggers.
- Rate-limit presence is not quota/runtime functionality. No exhaustion, datastore
  failure or commercial rate-limit execution is claimed. The current referenced
  tests do not include a dedicated quota/definite-allow lowering regression.
- Mixed known/unknown CIDR lowering still needs a focused independent regression;
  CIDR parsing, assurance labels and valid IPv4 target samples are different evidence.
- Raw-path normalization, disabled services, plugin subsystem selection, wildcard
  SNI, uppercase route hosts and stream criteria retain source-only target evidence.
  Header case/repetition has local checks but no dedicated live probes here.
- Admin-port recognition is limited to the declared default-port heuristic, not
  discovery of arbitrary deployed Admin APIs. Several unresolved relationship
  forms have local fail-closed checks without a live boundary matrix.

## Updating the inventory

For semantic changes, review the pinned target rule and approximation direction
first. Add independent positive/negative expectations and explain what deliberate
error the new regression would detect. Run the applicable regression and target
gates, then link those exact cases here. Keep remaining gaps explicit; do not
rename a conservative or unsupported observation merely to satisfy this checker.
Record approvals and actual run evidence in the bounded task's `docs/plans/`
acceptance note. The inventory links evidence; it does not approve broader
assurance claims or changes to frozen contracts.
