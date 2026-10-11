# Kong conformance and advisory-pilot readiness

## Authority and boundary

Sourav requested a single running development Goal for the next grouped roadmap
items after PR #52. Baseline: `c9589e0f0fbe49025c337cd1ce79111c1b8ecb44`.
The integration branch is `feat/kong-pilot-readiness`. This batch combines
bounded M11/M12 work, local M13 preparation, and evidence-led M14 workflow
improvements. Sourav confirmed **synthetic fixtures only**; no partner data or
production evidence is implied.

Implementation, focused tests, integration and task-related fixes proceed
continuously. Present the tested integrated diff for human review before any
commit or push. No PR creation/merge, production action, external partner
contact, repository-protection change, or computer-use automation is authorized.
No model runtime, new connector or agent benchmark belongs in this Goal.

Preserve report schema 9, profile `kong-traditional-http-v11`, frozen artifacts,
current verifier semantics, solver deadlines, and existing expected verdicts.
New manifest/coverage formats are internal experimental tooling, not public
verifier contracts. If independent evidence contradicts current lowering or
requires an assurance-boundary/schema/contract change, stop that affected work
and request a semantic decision; never bless model output as the target oracle.

## Work packages and ownership

### A. Additional pinned plugin conformance

One owner controls `bench/kong/conformance/`, `bench/kong_model_oracle.ml`, and
the corresponding harness mock tests. Target stays Kong OSS 3.9.3, source
`a643428bc4d5397152164a63bcc0f8bc65fce69d`, on both supported router flavors.

- Add strict internal source-IP probe/oracle support. Exercise IPv4 allow/deny,
  deny-before-allow overlap, `/0`, `/32`, boundaries, effective global/service/
  route/combined scopes, and disabled-plugin fallback.
- Derive the target address through an explicit fixture-only trusted real-IP
  setup on owned loopback containers. Reject malformed addresses and accidental
  mismatch/injection omissions. This tests the stated source-integrity
  assumption; it does not configure or prove a production trust boundary.
- Add conditional header-trigger termination absence/presence and effective
  scope/precedence, including authentication/IP rejection before termination.
  Conditional decisions remain conservative. Query triggers are a recorded gap;
  do not pass a query string as the model's path.
- Add small singleton basic-auth and JWT samples with public synthetic
  credentials: missing/invalid/valid credentials and JWT OPTIONS bypass.
  No external provider, richer identity, Enterprise plugin, expiration-clock
  requirement, or claim that one sample covers the entire known-auth list.
- Preserve every previous target expectation and exact/conservative/unsupported
  classification. Add negative harness controls for the new source-IP protocol
  and matrix-selection failures. Keep runtime rate-limit exhaustion and quota
  modeling out of this finite batch; record the gap rather than add flaky probes.

Independent source basis includes `ip-restriction/handler.lua`,
`request-termination/handler.lua`, `jwt/handler.lua`, `basic-auth/access.lua`,
`runloop/plugins_iterator.lua`, and `kong.conf.default` in the pinned source.
Expected decisions, identities and statuses must be justified from these
semantics before consulting Soundcheck output. Only one live harness runs at a
time; Docker-free tests are not target conformance.

### B. Checked semantic evidence inventory

One owner adds an internal inventory, validator and negative controls; the
coordinator integrates shared Dune files. Cover every current profile feature
code/class (modeled, conservative and unsupported), including explicit partial
or source-only evidence and identity/runtime/commercial gaps.

Entries record the pinned target rule/source, lowering ownership and
approximation direction, local regression references, independent target probe
references/classes/flavors where available, and unresolved evidence gaps.
Validate profile identity/completeness, duplicates/obsolete or misclassified
features, pinned references, file/probe existence, and flavor/class claims.
Unsupported probes cannot count as modeled target agreement. Tests must reject
deliberately corrupted inventories and false class/flavor/coverage declarations.

This is an **inventory-integrity gate**, not a proof that citations or tests
justify all semantics. Harness mutation controls are not feature-specific
semantic mutation evidence. Publish the limitations and remaining gaps plainly.

### C. Local advisory evaluation preparation

One owner adds experimental tooling under `bench/` plus focused tests and a
pilot runbook. Reuse `Contract_spec`, `Verify` and `Report`; do not duplicate
lowering, infer intent, repair configs, walk directories, fetch inputs, or probe
targets. An explicit strict manifest supplies pseudonymous IDs, config paths,
reviewed frozen-contract paths and self-declared provenance. Only synthetic
examples execute in this batch. A provenance label is not verified authority.

- Parse and freeze each contract before its sequential verification. Hash the
  exact config bytes verified and use the existing normalized contract identity.
- Summarize stable verdict/profile/assurance/finding codes, identifiers, elapsed
  time and explicit failure categories. Count all scheduled cases, including
  input errors and unknowns. Keep record ordering deterministic; timings vary.
- Default output excludes raw configs, paths, route/service names, hosts,
  witnesses, raw diagnostics, canonical contract text and SMT. Do not add
  automatic evidence retention. Hashes and user-chosen IDs are not anonymization.
- Keep exit behavior explicit and fail closed: zero only if every scheduled
  case is proved; non-proof results and input/tool errors remain nonzero while
  retaining the complete summary. This runner is experimental advisory tooling,
  not a replacement for the trusted frozen CI gate.
- Strict-input, mixed-outcome, failure-denominator, secret-sentinel and
  verifier/CLI consistency tests are required. Do not pin solver witnesses or
  measured times. No automatic overwrite of files or existing destinations.
- Document authorization, human contract approval, version/router/environment
  assumptions, review categories, retention/sharing choices and manual metrics.
  False-alarm rates, missed findings, usefulness and authoring effort require
  human/independent evidence; the runner must not invent them.
- Correct or clearly retire stale `bench/survey.ml` assurance claims. Its old
  independent heuristics are not a foundation for v11 coverage metrics.

Actual partner evaluation and feedback-driven feature choices remain M13/M14
follow-up, not acceptance of this synthetic preparation package.

### D. Predictable local validation

After package A's focused checks, its helper implements check wrappers and
wrapper tests in a separate workflow worktree; the coordinator owns their
integration, shared Dune files, README and this execution plan. Match the shipped CI scheduling fix: sequential
solver-heavy test actions (`-j 1`), parallel builds, no retries, installations,
deadline changes or skipped tests. Preserve fast/full/conformance mode behavior
and clean-commit validation of the requested committed revision.

Docker-free command-mock tests must cover mode selection, force flags, failure
propagation, absence of later stages/success messages after failure, and retention
of clean-check failure artifacts. Toolchain diagnostics must not install or
silently select different tools.

## Integration and completion

Helpers use separate branches/worktrees and non-overlapping ownership. Shared
interfaces and Dune files are integrated centrally. No helper commits or pushes.
Conformance receives the sole Docker lease; full regression/solver-heavy checks
are serialized so parallel development does not recreate deadline contention.

Completion requires focused package tests and negative controls, a full forced
sequential regression run retaining all 50 golden cases, the complete expanded
pinned real-Kong matrix on both flavors, independent implementation/semantic
review, whitespace/shell checks, and candidate validation in a fresh detached
worktree. Until commits are approved, that last check validates the applied
candidate diff, not an invented committed revision. Any approved later commit
must also pass `scripts/check-commit.sh` for its exact SHA before push.

The final package reports actual checks, unchanged public boundaries, synthetic
versus target evidence, remaining coverage gaps, and real-pilot prerequisites.
Do not call M11/M12 universally finished, M13 pilots performed, or production
security certified. Record evidence and unresolved decisions here as work proceeds.

## Local acceptance before commit

- Baseline and existing roadmap inspected; three independent scope reviews done.
- Goal created; focused branch and isolated worktrees created.
- Synthetic-only evaluation choice confirmed by Sourav.
- Packages A–D integrated locally; no commits or pushes. Shared Dune rules and
  README are coordinated in the root checkout.
- Focused plugin target checks passed twice (140 observations each); independent
  review checked pinned plugin selection, priorities and credential fixtures.
  Source-IP protocol checks: 22; mocked harness checks: 35.
- Inventory: 42 features (18 source-only, 23 modeled-sample, one boundary-sample),
  with 50 rejected corruptions and three permitted-literal parser controls.
  Peer review checked probe/class/flavor references and evidence limitations.
- Advisory tooling: 107 unit checks and 60 actual-process CLI checks passed on
  synthetic inputs. Peer review found no remaining implementation blocker.
- Review fixes contain decoded-NUL truncation in the new internal metadata
  readers by rejecting raw NUL/backslash syntax, clarify per-case reads, and make
  the harness's owned mutation copy writable under Dune. Shared parsing and
  verifier semantics are untouched. The shared YAML dependency's scalar-fidelity
  concern needs separate assessment; no false verifier verdict was established.
- Independent review found inherited Git environment could redirect synthetic
  fixture operations. The test now clears ambient Git routing/configuration;
  all 28 wrapper checks pass, including an owned-repository isolation control.
- `bash scripts/check.sh full` passed: parallel build, complete forced sequential
  regressions (all 50 unchanged corpus cases), and the full pinned Kong 3.9.3
  matrix on both flavors: 282 observations (160 exact, 52 conservative, 70
  unsupported-boundary). The test-only Git-environment follow-up was integrated
  afterward and is included in fresh candidate-worktree validation.
- Fresh detached candidate worktree `/private/tmp/soundcheck-readiness.1Lj30B/candidate`
  received all 19 tracked modifications and 27 new files, compared byte-for-byte
  with root. Its `dune build @all` and `dune test --force -j 1` passed, including
  all 50 corpus cases and the final 28 wrapper checks. This validates the applied
  candidate, not a committed revision. Dune 3.24.0 and Z3 4.16.0 were used.
- Shell syntax and whitespace checks pass. Independent reviews of target
  expectations, inventory, pilot runner and wrappers have no remaining blockers;
  the Git-isolation reviewer confirmed the fix. No owned harness containers
  remain. Core/connector semantics, schemas, original contracts/goldens and CI
  workflow are unchanged.
- The bounded local review package is complete. Changes and worktrees remain
  available for Sourav's review; no commit, push, PR or merge was performed.
  Hosted CI has not run for this uncommitted candidate. A later approved commit
  still requires exact-SHA clean-commit validation before pushing.

Sourav approved committing this reviewed batch on 2026-10-11. The next check
validates that exact committed revision; pushing and PR creation are not part
of this approval.

## Remaining evidence gaps

This batch does not close the 18 source-only feature rows or claim feature-wide
semantic mutation coverage. Basic/JWT negative probes use malformed credentials,
not well-formed wrong passwords/signatures. Query-trigger termination, runtime
quota/storage behavior, broader providers/identity, commercial plugin semantics,
and production source-IP integrity remain explicit gaps. See the checked
inventory for feature-specific details, including missing focused mixed-CIDR and
quota/definite-allow lowering regressions. Actual authorized deployment inputs,
owner-reviewed contracts and independently adjudicated usefulness/accuracy
measurements remain prerequisites for M13; synthetic preparation supplies none
of those conclusions.
