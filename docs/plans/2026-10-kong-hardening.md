# Kong semantic hardening: decisions and acceptance

## Accepted scope

Approved 2026-10-10 against baseline
`8cd7b804c74ee2d0f10248d82b428f1df6577cea` (PR #51): bounded semantic hardening
(M10), with pinned target conformance and semantic acceptance (M11/M12).
Deployment pilots, new connectors, model runtimes and branding were outside this
batch. Solver deadlines, the core/connector boundary, public schemas and frozen
contracts were preserved; changed corpus expectations required independent
target justification.

Two semantic decisions established the accepted boundary:

- **Approved contract authority:** the gate reads the exact immutable PR
  base-commit contract, or the protected-default-branch push commit. Candidate
  edits cannot approve a replacement specification; contract changes require
  separate approval. Repository protection and approval authority remain
  deployment responsibilities.
- **Shared router support:** retain both `traditional` and
  `traditional_compatible`, failing closed on unmodeled differences. Choosing
  one flavor or silently restricting requests to ASCII would conceal the
  PCRE-versus-Unicode-Regex and precedence differences.

Semantic acceptance requires a pinned target rule, lowering and approximation
direction, positive/negative expectations, and evidence that regressions detect
the original defect where practical. Agreement between readers of Soundcheck's
own IR does not supply independent target evidence. Standing workflow rules and
check commands live in [AGENTS.md](../../AGENTS.md) and
[Testing](../../README.md#testing).

## Decisions and their evidence

The resulting boundary is **`kong-traditional-http-v11`**, targeting Kong OSS
3.9.3 and both router flavors. Report schema 9, profile schema 1, comparison
schemas and frozen-contract schemas/artifacts are unchanged.

### Input fidelity and property recognition

- **Strict YAML:** the OCaml YAML reader and Kong's LYAML 6.2.8 disagreed on
  octal-looking numbers and single-letter booleans. Raw-style scalar decoding
  follows LYAML for accepted forms and rejects ambiguous numeric forms.
  Duplicate keys, malformed consumed structures, explicit tags, aliases/merges
  and extra documents reject consistently for configs and frozen contracts.
  This is not full Kong schema validation.
- **Solver strings:** byte-faithful, single-pass SMT escaping and model decoding
  replace handwritten escape handling. Defect controls reproduced literal
  escape text, Z3 interpreting literal `\\u0041` as `A`, and invalid diagnostic
  bytes producing invalid JSON. Unrepresentable model values fail closed;
  diagnostics remain UTF-8-safe, including truncation within multibyte text.
  Tests cover all modeled string fields, header bytes and process failures.
  SMT-LIB/Z3 source and direct queries establish raw UTF-8's byte representation.
- **Shadowing pruning:** authentication versus network guards and two different
  network guards reproduced false `proved` verdicts. Pruning requires sufficient
  guard implication; other pairs require a solver query. Distinct entities with
  the same display name fail closed rather than losing candidate pairs.
- **Admin API recognition:** explicit HTTP/HTTPS service targets, numeric and
  scheme-relative URL ports, and leading-zero ports are recognized while
  preserving URL-shorthand precedence and reading explicit service ports when
  shorthand is absent. Kong schemas and LuaSocket justified
  the fixes: `:8001/?x=1` is valid, whereas `:8001?x=1` is not.

### Routing, approximation and verification

| Area | Decision and acceptance evidence |
| --- | --- |
| Path migration | Modern format 3.0 `/a+b` stays literal; explicit 1.1/2.1 retains pinned migration, including percent handling and final-LF classification. Independently fixed literal-plus expectations passed both target flavors and failed the baseline model in two cases per flavor. |
| Regex | Strict escape/class/group/repetition parsing, anchor parity, typed class endpoints, checked limits and syntax metadata. Reject flavor-dependent languages and unsafe transformations. Initial 58 parser/boundary failures plus six class cases exposed defects; fixed tests include 5,000 deterministic malformed inputs and independently specified real-Z3 membership expectations. Syntax restrictions do not eliminate target runtime failures. |
| Route order | Keep common criterion-count precedence; detailed path ordering requires identical non-path predicates. Regex pattern length is not a rank. Accepted regexes are non-suppressing may-matches because runtime failure is unmodeled. Independent target observations reproduced reducer/category differences. |
| Possible/definite allowance | Union possible allowing winners rather than applying deny-overrides. Failed guards cannot invoke an allowing default; incomplete matches cannot suppress/prune; incomplete guards cannot prove functionality; shadowing negates a must-guard. The independent refinement oracle checks 91,200 worlds (2,160 exact deterministic worlds) and detects broken deny-overrides (4,872), default fallthrough (660), incomplete suppressor (84) and mixed-key-shape (112) controls. |
| Connector lowering | Remove disabled-service routes; respect plugin subsystem activation; reject unknown active HTTP plugins, unresolved nested relationships and consumer/consumer-group plugins. Weaken unknown allow lists without dropping possible members. Conditional termination, anonymous fallback and quota state cannot establish definite access. |
| Headers and Host | Mixed `~*` header arrays differ by flavor, so retain possible matches. Effective default Host ports and empty wildcard matches exposed false paired-contract proofs. Port-bearing hosts remain unconstrained/incomplete; wildcard hosts use a possibly empty upper bound. Regressions require conservative violations. |
| SAT witnesses | Validate inhabitance, consistency, safety, functionality, shadowing, exact-policy preflights and all four comparison obligations before verdicts/traces. Lift using selected match/guard and structural rule filters; do not invent ambiguous service ownership. Initial tests failed 23 checks; 101 focused checks pass, including real Z3 and frozen/manual MCP consistency. |
| Contract gate | Unsupported event contexts, malformed/missing Git objects, nonregular blobs and unsafe config paths fail closed. Candidate contract edits, deletion or symlinks cannot substitute the base contract. All 61 local-Git checks pass, including real-CLI weakening/repair and shallow-fetch controls. |
| Action build trust | Trusted Action source owns helper/verifier. Reject preexisting workspace `_opam`, disable candidate autopinning/caches and explicitly select a fresh switch. Five metadata guard cases pass. Smoke CI builds once and requires exit 3 for the negative case, preventing setup failure from masquerading as a successful rejection. |

Ordering-only assurance findings may proceed to comparison's exactness check:
complete predicates and identical observations, or solver-proved absence of
relevant overlap, are required. Identical-effect ties can prove decision
equivalence; unresolved route identity cannot prove stronger modes. Other
conservative/unsupported findings fail closed. Incomplete matches also cannot
justify shadowing pruning.

### Reviewed expectation changes

Original corpus YAML and frozen contracts were retained. The 50 expected reports
adopt profile v11, with these independently justified changes:

- Six regex fixtures become `unknown`: final `$`, shorthand classes or migrated
  dot syntax differ across flavors. Backreference rejection remains `unknown`.
- `host-scoped-ranking` becomes a conservative violation through `admin-narrow`:
  the guarded regex cannot reliably suppress in the upper bound. This candidate
  does not assert that the simple regex fails at runtime.
- `host-scoped-suppressor` retains its violating route with uncertainty findings.
  Equal-order shadowing gains an order finding without changing the verdict.
- General rate-limit cases retain structural coverage verdicts while reporting
  that runtime quota cannot guarantee functionality.
- `wrong-plugin` becomes `unknown`/unsupported: an unmodeled active plugin cannot
  safely be assumed to alter only an authorization guard.
- Generic matcher/SMT agreement includes the empty wildcard-host suffix in its
  upper bound; independent target observations remain separate. Header ranking
  retains alternatives across both flavors. Comparison expectations are
  preserved, with earlier, stricter rejection reasons.

## Primary semantic sources

Kong OSS 3.9.3 is pinned to
`a643428bc4d5397152164a63bcc0f8bc65fce69d`:

- [`traditional.lua`](https://github.com/Kong/kong/blob/a643428bc4d5397152164a63bcc0f8bc65fce69d/kong/router/traditional.lua): category sorting, request-global reduction, header arrays, raw/synthesized Host lookup, wildcards and PCRE execution.
- [`transform.lua`](https://github.com/Kong/kong/blob/a643428bc4d5397152164a63bcc0f8bc65fce69d/kong/router/transform.lua): compatible priority packing, wildcard predicates, per-value header regexes and source rewriting.
- [`migrate_path_280_300.lua`](https://github.com/Kong/kong/blob/a643428bc4d5397152164a63bcc0f8bc65fce69d/kong/db/migrations/migrate_path_280_300.lua): legacy classification and percent migration.
- [`plugins_iterator.lua`](https://github.com/Kong/kong/blob/a643428bc4d5397152164a63bcc0f8bc65fce69d/kong/runloop/plugins_iterator.lua), entity schemas (`services.lua`, `schema/init.lua`) and declarative lowering: plugin activation, disabled services, scoped relationships and URL shorthand.
- PCRE2 10.44 and pinned ATC router `ffd11db657115769bf94f0c4f915f98300bc26b6`
  (Rust regex 1.11.1): escape/Unicode/anchor differences and compile limits.
- LYAML 6.2.8 and LuaSocket 3.0-rc1 `src/url.lua`: scalar resolution and URL
  parsing. SMT-LIB Unicode Strings and Z3 4.16.0 `zstring.cpp`: literal/model
  boundaries.

An independent 26-observation target experiment confirmed Unicode dot,
shorthand/negated-class differences, `$` before final LF, top-level alternation
anchoring, reducer selection and wildcard-host/path category order. Rejection or
conservative bounding of these cases does not count as exact model agreement.

## Historical acceptance

The hardening matrix passed **188 observations: 82 exact, 36 conservative-bound
and 70 unsupported-boundary**, across eight configurations and both flavors.
Fixed target identities, decisions and statuses were mandatory in every class;
unsupported checks required public `unknown` plus `unsupported` assurance,
never a timeout. Original routing expectations were retained in their now
unsupported mixed configuration, with separate supported fixtures.

Two new fixture assumptions were corrected from pinned target semantics:
`/exact` also prefixes `/exact-escaped`, so isolation requires `/exact/`;
traditional plain-host final lookup does not reuse the category's synthesized
port, whereas compatible can use the effective destination port. The host
fixture pins `port_maps=80:8000,443:8443`. Model output did not establish either
correction.

The 21 Docker-free harness controls covered lifecycle failures, wrong tuples or
statuses, class substitution, invalid candidates, empty matrices and escapes
from identity/may/must bounds. The must-bound control uses two candidates so
another class condition cannot mask a missing bound check.

Integrated build and forced regressions passed: all 50 corpus cases, refinement
worlds and witness/gate checks above, four comparison modes and CLI/MCP/evidence
consistency. Independent semantic, implementation and harness reviews found no
remaining blocker. The target run used image digest
`sha256:ca71c5591eabaf18de96d26b7eed5e2fdb590dac141e467a779c38017e5bdf81`;
toolchain: OCaml 5.5.0, Dune 3.24.0, Z3 4.16.0 and Docker 28.4.0.

These counts describe the hardening batch, not the later
[expanded readiness matrix](2026-10-kong-pilot-readiness.md). Narrowed v11
coverage and passing finite checks are not universal target soundness.
Evidence bundles support audit/replay, not independently checked UNSAT
certificates. Deployment still requires trusted/pinned workflow and Action
sources, fixed approved contract selection, separate contract approval, required
non-bypassable checks and fresh-base reruns.

## CI contention decision (2026-10-10)

Hosted regressions timed out on `plain-path-punctuation` while the other 49
corpus cases passed. Z3 4.16.0 was already pinned. With that checksum-verified
Linux binary in an isolated one-CPU Ubuntu 24.04 container, the unchanged query's
status check plus SAT model replay took 8.99 seconds; a competing identical job
exhausted the shared ten-second budget at 10.03 seconds. This establishes
contention sensitivity, not the hosted runner's exact load.

The resulting CI change runs `dune test --force -j 1` while keeping builds
parallel, with no retries, query/golden changes or deadline increase. The full
forced sequential suite passed locally. Real-Kong conformance was unchanged and
not rerun for this scheduling-only change. Serialization removes suite-internal
competition but cannot guarantee arbitrary host performance; the later
[query simplification](2026-10-kong-corpus-timeout.md) addresses remaining cost.
