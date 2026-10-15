<p align="center">
  <img src="docs/assets/soundcheck-logo-readme.png" alt="" width="160">
</p>

<h1 align="center">Soundcheck</h1>

<p align="center">
  <strong>Solver-backed proof or counterexample for declarative security policy.</strong>
</p>

<p align="center">
  <a href="https://github.com/ph0smet/soundcheck/actions/workflows/ci.yml?query=branch%3Amain"><img src="https://github.com/ph0smet/soundcheck/actions/workflows/ci.yml/badge.svg?branch=main&amp;event=push" alt="CI status on main" height="20"></a>
  <a href="https://ocaml.org/"><img src="https://img.shields.io/badge/OCaml-5.0%2B-EC6813?logo=ocaml&amp;logoColor=white" alt="OCaml 5.0 or newer" height="20"></a>
  <a href="https://github.com/Z3Prover/z3"><img src="https://img.shields.io/badge/solver-Z3-137CBD" alt="Solver: Z3" height="20"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-009C95" alt="License: MIT" height="20"></a>
</p>

<p align="center">
  <a href="#quickstart">Quickstart</a> ·
  <a href="docs/getting-started.md">Full walkthrough</a> ·
  <a href="#supported-model">Supported model</a> ·
  <a href="#integrations">Integrations</a> ·
  <a href="CONTRIBUTING.md">Contributing</a>
</p>

Soundcheck checks a declarative policy against a precise security or functionality
requirement. It either proves that no violating request exists in the supported
model or returns a concrete, validated model-level counterexample in the policy's
own vocabulary.

Today, the shipped connector verifies **decK-style Kong configurations** for Kong
OSS 3.9.3 under the `traditional` and `traditional_compatible` HTTP routers.
Soundcheck is independent of any AI model: it contains no model client, prompt,
credentials, or nondeterministic repair logic. AI agents, CI jobs, and other
tools all consume the same verifier results.

> [!IMPORTANT]
> A `PROVED` result is relative to the asserted property or frozen contract,
> Soundcheck's versioned target model, and explicit assumptions. It is not a
> certification of every Kong deployment. Unsupported semantics fail closed as
> `unknown`; conservative counterexamples are investigation candidates, not
> guaranteed live-gateway reproductions.

```console
$ dune exec soundcheck -- verify \
    bench/kong/workflows/frozen-admin/unsafe.yaml \
    --contract bench/kong/contracts/admin-get.yaml
VIOLATED authenticated-access
         Conservative model-level candidate, not a guaranteed target replay:
         anonymous request GET /admin ... may be ALLOWED via route "admin-get"
$ echo $?
3
```

## What ships today

| Capability | Current support |
| --- | --- |
| Target | Kong OSS 3.9.3 decK YAML; `traditional` and `traditional_compatible` HTTP routing |
| Verification | Six property templates and two strict frozen contract kinds |
| Verdicts | `proved`, `violated`, `vacuous`, `inconsistent`, or `unknown` |
| Comparisons | Decision, route/service, service target, and upstream URI equivalence |
| Interfaces | CLI, schema-v9 JSON, GitHub annotations, frozen/manual MCP, and a reusable GitHub Action |
| Audit output | SMT-LIB2 emission for single queries and complete evidence bundles for frozen contracts |

Kubernetes RBAC, OPA/Rego, IAM, and app-level authorization are planned rather
than implemented. A new connector may extend the shared decision IR when its
target introduces a genuinely new concept; the core never depends on connectors.

## Why Soundcheck

Security policy is a good verification target because it has a formalizable
question: for every request, should this principal be allowed to perform this
action on this resource in this context?

Tests sample that request space and remain essential for validating the model,
but finite samples cannot establish the absence of every policy violation.
Soundcheck instead lowers the policy to a decision model, combines it with the
negation of the requested invariant, and asks Z3 whether a violating request
exists. The reviewed contract and verifier remain independent of the
probabilistic generator.

This machinery is intentionally narrow. If the intended behavior cannot be
written as a precise property, there is nothing meaningful for Soundcheck to
prove.

## Quickstart

Soundcheck currently builds from source. You need:

- Git and Bash.
- [opam](https://opam.ocaml.org/) with OCaml 5.0 or newer.
- Dune 3.11 or newer and the `yaml` OCaml package.
- The `z3` CLI on `PATH`. Z3 4.16.0 is the regression-tested baseline; other
  versions may produce different timeout or `unknown` behavior. The pinned
  binary is available from the [official Z3 4.16.0 release](https://github.com/Z3Prover/z3/releases/tag/z3-4.16.0).

```sh
git clone https://github.com/ph0smet/soundcheck.git
cd soundcheck

# Create or select an OCaml 5.x switch, then load it in this shell.
opam switch create . 5.2.1 --no-install
eval "$(opam env)"

opam install . --deps-only --with-test
dune build @all
```

Verify the included repaired configuration against its reviewed contract. The
`frozen-admin` files are minimal synthetic verifier fixtures, not complete
deployable Kong configurations:

```sh
eval "$(opam env)"
dune exec soundcheck -- verify \
  bench/kong/workflows/frozen-admin/repaired.yaml \
  --contract bench/kong/contracts/admin-get.yaml
```

Abridged expected result:

```text
PROVED   authenticated-access
         Anonymous requests must be denied and authenticated requests allowed for path prefix /admin, method GET
         Assurance: kong-traditional-http-v11 (within_profile)
```

The [complete getting-started guide](docs/getting-started.md) walks through an
unsafe config, its repair, a deny-all non-repair, JSON output, evidence bundles,
comparisons, MCP, and common failure modes. It reuses the repository's tested
fixtures rather than maintaining duplicate examples.

## How it works

```text
 decK YAML          shared verification core
     │
     ▼          ┌─────────────────────────────────────────────┐
 Kong connector │ Decision IR → property negation → SMT-LIB2 │ → Z3
  parse + lower └───────────────────────┬─────────────────────┘
     ▲                                  │
     └──────── checked witness + config-level counterexample ┘
```

1. **Parse and lower.** The Kong connector parses YAML, validates Soundcheck's
   accepted fragment, and lowers supported target behavior into the shared
   decision IR. It is not a replacement for Kong's full schema validation.
2. **Freeze the intent.** A reviewed contract identifies the invariant and its
   exact path, method, host, network scope, and assumptions.
3. **Encode the violation.** Soundcheck asks whether there exists a request that
   the policy allows but the contract forbids, or denies but the contract
   requires.
4. **Solve and validate.** `UNSAT` closes a policy-clause obligation in the
   modeled semantics; the separate inhabitance check must be `SAT`. Every
   decoded `SAT` witness is checked against its actual obligation, and an
   invalid witness becomes `unknown`.
5. **Lift the result.** A checked witness is reported as a principal, method,
   path, route, and service rather than raw solver values.

Soundcheck preserves the abstraction invariant:

```text
must_allow ⊆ actual_allow ⊆ may_allow
```

Safety checks use possible allowance so incomplete matching cannot hide a leak.
Functionality checks use definite allowance so an uncertain guard cannot prove
required access. That asymmetry is why a conservative model can still be sound
for both kinds of obligation.

## Understand the verdict

| Result | Meaning | Exit code |
| --- | --- | ---: |
| `proved` | All applicable inhabitance and consistency checks pass, and no modeled property or contract violation exists | 0 |
| `violated` | A validated modeled witness defeats a property or contract obligation | 3 |
| `unknown` | Unsupported semantics, solver failure/timeout, or an invalid decoded witness prevents a proof | 4 |
| `vacuous` | The required request class is empty, so no useful policy proof was established | 5 |
| `inconsistent` | Frozen must-allow and must-deny intent overlap | 6 |

Input, output, and verification errors exit `1`; invalid command usage exits
`2`. Only `proved` exits zero at the verification gate.

## Properties and frozen contracts

| Property | Kind | Question |
| --- | --- | --- |
| `no-anonymous-access` | Safety | Can an unauthenticated request reach a protected path prefix? |
| `rate-limit-on-public` | Safety | Is every anonymously reachable route covered by a general request-rate-limit plugin? |
| `no-shadowed-routes` | Structural safety | Can a permissive route intercept traffic that a stricter route was written to handle? |
| `admin-api-not-reachable` | Safety | Can an anonymous request outside a trusted address block reach a recognized Admin API target? |
| `authenticated-access` | Paired safety + functionality | Are anonymous requests denied while authenticated requests remain definitely allowed in one scope? |
| `network-restricted-access` | Paired safety + functionality | Are untrusted sources denied while authenticated requests inside a trusted IPv4 block remain definitely allowed? |

Manual property flags are useful for exploration. A gate should use a strict,
versioned contract loaded outside the repair loop. `--contract` rejects property
and scope overrides, and every report carries the contract's normalized identity.
See the shipped [`authenticated-access` contract](bench/kong/contracts/admin-get.yaml)
and [`network-restricted-access` contract](bench/kong/contracts/internal-get.yaml).

Paired contracts reject deny-all “repairs.” For example, the empty
[`deny-all.yaml`](bench/kong/workflows/frozen-admin/deny-all.yaml) still violates
the `must_allow` clause of the admin contract.

## Integrations

### Stable JSON

On `verify`, `--format json` emits the schema-v9 verification result used by
machine consumers. Its core result, property, assurance, frozen-spec, clause,
and counterexample keys are always present and use `null` when not applicable;
`reason` appears for `unknown` and `inconsistent`. `compare` and `profile` have
separately versioned JSON schemas.

```sh
eval "$(opam env)"
dune exec soundcheck -- verify \
  bench/kong/workflows/frozen-admin/unsafe.yaml \
  --contract bench/kong/contracts/admin-get.yaml \
  --format json
```

The report includes the verdict, property, assurance assessment, frozen-spec
identity, failed clause, and checked counterexample. The CLI and MCP adapter
share these report semantics; the GitHub Action uses the same verifier and exit
codes with native workflow annotations.

### Frozen MCP

Start an MCP server with the reviewed contract fixed for its lifetime:

```sh
eval "$(opam env)"
dune exec soundcheck -- mcp \
  --contract bench/kong/contracts/admin-get.yaml
```

The frozen `verify` tool accepts configuration only. An agent may repair that
configuration and retry, but it cannot replace the property or weaken its scope.
Running MCP without `--contract` remains a manual exploration mode.

### GitHub Action

The composite Action reads the approved contract from the immutable PR base
commit, or from the exact protected-default-branch push commit, rather than from
the candidate checkout.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: ph0smet/soundcheck@<reviewed-full-commit-sha>
    with:
      config: kong.yaml
      contract: soundcheck-contract.yaml
```

Use a reviewed full commit SHA in a fresh, trusted job before any candidate code
runs. The caller workflow, fixed contract path, and Action SHA must not be
candidate-controlled; `uses: ./` is only suitable for testing the Action and is
not an approval boundary. The adapter accepts `pull_request` and non-forced,
non-deleted protected-default-branch push events and fails closed elsewhere.
Required checks, branch protection, separate contract approval, and fresh-base
reruns are repository responsibilities; Soundcheck does not install them.
Pinning Soundcheck by SHA does not fully pin the transitive supply chain: the
setup Action, distro Z3 package, and resolved opam dependencies require their
own review or locking where that assurance is needed.

### Configuration comparison

Compare all modeled decisions, or select a stronger observation with
`--mode route-service`, `--mode service-target`, or `--mode upstream-uri`.
Binding the comparison to a
contract also proves the replacement satisfies the frozen intent and preserves
the selected behavior outside its scope.

```sh
eval "$(opam env)"
dune exec soundcheck -- compare \
  bench/kong/workflows/frozen-admin/unsafe.yaml \
  bench/kong/workflows/frozen-admin/repaired.yaml \
  --contract bench/kong/contracts/admin-get.yaml \
  --format json
```

That included example returns `valid_repair`. Incomplete predicates or
observations return `unknown` instead of an unjustified equivalence proof.

### Audit artifacts

Non-contract runs can retain the most recently executed SMT-LIB2 query with
`--emit-smt`. Inhabitance and shadowing may require more than one query, so that
file is not a complete trace. Frozen contracts reject `--emit-smt` and use
multiple ordered obligations; `--evidence-dir` writes their complete schema-v1
bundle with the normalized contract, assurance profile, report, every planned
query, execution status, digests, and provenance.

```sh
mkdir -p evidence
eval "$(opam env)"
dune exec soundcheck -- verify \
  bench/kong/workflows/frozen-admin/repaired.yaml \
  --contract bench/kong/contracts/admin-get.yaml \
  --evidence-dir evidence/run-001 \
  --format json
```

The destination must not already exist. Evidence permits formula replay; it is
not an independently checked UNSAT certificate or a proof of the parser,
encoder, or target model. If unsupported input is rejected before obligation
planning, the bundle records an unavailable plan rather than inventing queries.
Treat bundles as potentially sensitive: they omit raw config text but contain
the contract, report, formulas, witnesses or models, hashes, and operational
identifiers. Review them before retention or sharing.

## Supported model

The current assurance profile is `kong-traditional-http-v11`: Kong OSS 3.9.3
`traditional` and `traditional_compatible` HTTP routing. Inspect the complete
modeled, conservative, and unsupported feature lists directly:

```sh
eval "$(opam env)"
dune exec soundcheck -- profile kong --format human
```

Important boundaries include:

- Literal paths, normalized request paths, methods, lowercase exact hosts,
  exact headers, HTTP/HTTPS behavior, exact HTTPS SNI, known plugin precedence,
  top-level routes, disabled services, and default-deny behavior are modeled
  within the published profile.
- Route ordering retains only the partial order justified for both supported
  routers. Unresolved possible winners remain possible rather than being
  arbitrarily selected.
- Regex support is a bounded shared subset. Even accepted regex matches remain
  conservative because Kong's PCRE runtime can fail at its match limit.
- Unknown active HTTP plugins and unsupported relationship or regex forms make
  the whole verification result `unknown`.
- Authentication is a configuration-level guard model, not a proof of plugin
  implementations, credential stores, or identity-provider availability.
- Rate-limit verification establishes structural plugin coverage, not live
  quota behavior, datastore health, or throughput.
- Network contracts reason over the IPv4 client address supplied by Kong. The
  deployment must enforce the frozen `source_ip_integrity` assumption.
- Admin API recognition uses the declared default-port heuristic for 8001 and
  8444; it does not discover arbitrary administrative endpoints.
- Parser/lowering fidelity, the encoder, witness validator, Z3, the supported
  Kong assumptions, and trusted CI deployment remain in the trust boundary.

The [semantic evidence inventory](bench/kong/SEMANTIC-COVERAGE.md) maps every
profile feature to pinned Kong source, lowering ownership, regressions, available
target samples, and explicit gaps. It is evidence bookkeeping, not a public
result schema, a coverage percentage, or a completeness certificate.

## Testing

The repository keeps several kinds of evidence separate:

- `bench/kong/cases/` contains 50 labeled regression cases with reviewed
  expected results.
- An independent finite refinement oracle checks
  `must_allow ⊆ actual_allow ⊆ may_allow` across 91,200 worlds and includes
  deliberate broken controls.
- The semantic inventory tracks 42 assurance-profile features and their
  remaining evidence gaps.
- The pinned real-Kong harness executes 282 observations across both supported
  router flavors: 160 exact, 52 conservative, and 70 unsupported-boundary
  observations.

These are finite checks of the implementation and abstraction rules, not a
universal proof that the target model matches every deployment.

The fast gate requires `jq`. The full gate additionally requires Docker, a
running daemon, and `curl`.

```sh
eval "$(opam env)"
bash scripts/check.sh fast

# Also run pinned Kong 3.9.3 conformance; requires Docker and curl.
bash scripts/check.sh full
```

Solver-heavy tests and conformance runs are serialized because they share
timeouts, container names, and ports. See the
[conformance harness](bench/kong/conformance/README.md) and the experimental
[synthetic pilot workflow](bench/pilot/README.md) for their exact claims.

## Repository layout

```text
core/                 shared IR, properties, solver, witnesses, reports, evidence
connectors/kong/      Kong parsing, semantic lowering, assurance, and lifting
cli/                  verify, compare, profile, and mcp subcommands
mcp/                  config-only frozen verification adapter
ci/                   GitHub annotation formatting
bench/                corpus, semantic inventory, conformance, and pilot fixtures
test/                 regression, oracle, adapter, and acceptance tests
docs/plans/           approved technical scope and acceptance evidence
```

Connectors depend on core; core never depends on connectors. Adapters remain
thin wrappers over the same verification implementation.

## Roadmap

The immediate focus is trustworthy Kong-first verification: deeper semantic
coverage, target conformance, small authorized deployment pilots, and usability
feedback. Only public synthetic pilot examples ship today; no production-pilot
or accuracy claim is implied.

Additional connectors follow after the Kong verifier is ready for broader use.
External agents and training systems may consume Soundcheck, but model clients
and repair orchestration remain outside the verification core.

## Contributing

Bug reports, formalizable feature proposals, and focused pull requests are
welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md); coding agents should also
follow [AGENTS.md](AGENTS.md). Please sanitize configurations and never include
credentials, production evidence bundles, or confidential counterexamples in a
public issue.

## Design choices

Soundcheck is written in OCaml because its work is compiler-shaped: parse,
lower, encode, solve, validate, and lift. Z3 is invoked through inspectable
SMT-LIB2 text rather than language bindings. Interactive theorem proving is not
part of the runtime architecture; automated SMT fits the current decidable
policy fragment.

## License

MIT. See [LICENSE](LICENSE).
