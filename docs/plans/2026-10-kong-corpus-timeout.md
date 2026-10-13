# Kong corpus timeout follow-up

## Scope and acceptance

Sourav reported the failed full regression step for the PR from
`feat/kong-pilot-readiness` to `main`. Only `plain-path-punctuation` failed:
its required `violated` result became `unknown` because the solver process
exhausted its deadline. The workflow already pins Z3 4.16.0 and runs
`dune test --force -j 1`.

This bounded fix reduces solver work without changing the request language,
verifier verdicts, corpus fixtures/goldens, frozen contracts, profile v11,
report schema 9, shared ten-second solver deadline, or timeout failure behavior.
The source branch remains the PR branch. Present the tested diff for review
before committing or pushing; opening or merging a PR is not delegated.

The prior investigation in `2026-10-kong-hardening.md` measured 8.99 seconds
for the same pinned Linux query's status check and SAT model replay. Sequential
test scheduling removed suite-internal competition but left little headroom.
The supplied log does not establish the hosted runner's exact resource load.

## Change and semantic evidence

Factor the normalized-path regular language from `"/" | "/" suffix` to
`"/" suffix?`. This is regular-language distributivity with optionality
(`suffix? = epsilon | suffix`). The suffix, segment rules, character alphabet,
and percent-escape rules stay identical. No solver process/protocol change is
needed.

Regression coverage retains the complete pre-change v11 AST and asks Z3 whether
its regular language differs from the new AST, without restricting path length
or scope. The required answer is UNSAT. Separate explicit URI-normalization
expectations test concrete and SMT membership for root/trailing slashes,
dot-prefixed and dot-only segments, punctuation, reserved and malformed percent
escapes, duplicate slashes, and a UTF-8 path. This proves preservation relative
to the existing model and checks finite target-derived boundaries; it is not
new comprehensive target conformance.

## Validation

- `dune build @all` and `dune test --force -j 1` passed locally, including all
  50 unchanged corpus cases, the new path-domain checks, and existing solver
  deadline/process/protocol, witness, frozen-adapter and pilot regressions.
  Toolchain: OCaml 5.5.0, Dune 3.24.0, Z3 4.16.0 on macOS arm64.
- The focused path-normalization test passed: full-language inequality returned
  UNSAT, and all 33 explicit positive/negative paths matched their expected
  membership in both the concrete evaluator and SMT encoding. A preliminary
  diagnostic using membership XOR instead of direct language inequality timed
  out; the direct equality obligation proves preservation without that costly
  search. No production timeout or acceptance criterion changed.
- Three sequential measurements of the original and candidate emitted
  obligations, each performing the status check and full SAT model replay under
  one ten-second budget, gave median totals of **3.69 seconds before** and
  **1.18 seconds after**. The candidate CLI also returned the required validated
  `violated` result via `admin-dotted`, with exit code 3.
- Independent read-only review found no blocking semantic, test or scope issue.
  Whitespace checks passed. The final comment-only wording refinement was
  followed by another successful `dune build @all`.

These local measurements do not establish Linux or hosted CI performance.
Docker remained stopped, so pinned Linux solver timing and live Kong
conformance were not rerun. Hosted CI has not run with this uncommitted fix.
At pre-commit review the diff remained on `feat/kong-pilot-readiness`; no commit,
push, PR creation or merge had been performed. Sourav subsequently approved
committing and pushing the reviewed fix on 2026-10-13. The exact new commit must
pass `scripts/check-commit.sh` before pushing to the existing PR branch.
