# Kong corpus timeout: rationale and acceptance

## Problem and preserved boundary

`plain-path-punctuation` returned `unknown` on solver timeout instead of its
required `violated` result. CI already pinned Z3 4.16.0 and ran forced tests with
`-j 1`. The [earlier contention experiment](2026-10-kong-hardening.md#ci-contention-decision-2026-10-10)
showed little Linux deadline headroom; sequential scheduling removed competition
within the suite without simplifying the query. The failure log does not
establish the hosted runner's exact resource load.

The fix preserves the request language, fixtures/goldens, frozen contracts,
profile v11, report schema 9, and fail-closed timeout behavior. Status checking
and SAT model replay still share one ten-second solver budget.

## Change and semantic evidence

Factor the [normalized-path language](../../connectors/kong/path_normalization.ml)
from `"/" | "/" suffix` to `"/" suffix?`, using regular-language distributivity
and `suffix? = epsilon | suffix`. Suffix, segment, alphabet and percent-escape
rules remain identical; no solver process/protocol change is needed.

The [regression](../../test/path_normalization_t.ml) retains the complete
pre-change v11 AST and asks Z3 whether its language differs from the new AST,
without restricting path length or scope. Direct language inequality returns
UNSAT. A preliminary membership-XOR diagnostic timed out; direct equality
establishes the same preservation obligation without that search.

Separately, 33 explicit positive/negative paths test concrete and SMT membership
against URI-normalization expectations: root/trailing slashes, dot-prefixed and
dot-only segments, punctuation, reserved/malformed percent escapes, duplicate
slashes and UTF-8. The equality check establishes model-language preservation;
the 33 paths check finite expected boundaries. Neither supplies comprehensive
target conformance.

## Historical local acceptance (2026-10-13)

Build and forced sequential regressions passed, including all 50 unchanged
corpus cases, the language-equivalence/33-path checks and existing deadline,
protocol, witness, frozen-adapter and pilot regressions. Toolchain: OCaml 5.5.0,
Dune 3.24.0, Z3 4.16.0, macOS arm64. Independent review found no blocker.

Three sequential measurements per version, each including status checking and
full SAT model replay under one ten-second budget, gave median totals of
**3.69 seconds before** and **1.18 seconds after**. The candidate CLI returned a
validated `violated` result through `admin-dotted`, exit code 3.

These measurements do not establish Linux or hosted CI performance. Independent
Linux timing and live Kong conformance were not rerun in this local optimization
check; the unrestricted language-equivalence regression supplies preservation
evidence for the existing model.
