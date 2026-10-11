# Experimental local advisory evaluation

This prepares a small, local evaluation of explicitly selected configurations
against separately reviewed frozen contracts. It is not a production gate,
target replay tool, vulnerability scanner, or an agent repair loop. No partner
configurations or deployment results are included: the shipped examples are
public synthetic fixtures only. Real pilots remain a later authorized activity.

The runner delegates to the existing `Contract_spec`, `Verify`, and `Report`
implementation. It does not infer intended access from a configuration, weaken
contracts, duplicate lowering, or change solver deadlines. Public verifier
CLI/JSON/MCP interfaces, contract artifacts, and assurance profiles are unchanged.
The manifest and summary described here are experimental bench-tool formats,
not new stable public APIs.

## Synthetic walkthrough

Use the normal [Soundcheck toolchain](../../README.md#quickstart), including Z3
4.16.0 on `PATH`. From the repository root:

```sh
eval "$(opam env)"
dune exec bench/pilot/main.exe -- bench/pilot/examples/manifest.yaml
```

The four examples should produce one `proved`, two `violated`, and one
`unknown` result. The command intentionally exits **3** because not every case
proved. The expected unknown is an unmodeled plugin, not a solver timeout.
The unsafe/repaired/deny-all examples use the same reviewed intent as
[`admin-get.yaml`](../kong/contracts/admin-get.yaml). These synthetic results
are workflow acceptance evidence, not evidence of deployment accuracy.

The command prints one minimized JSON summary. It writes no results, evidence
bundles, temporary source copies, or modified inputs. It only reads explicit
manifest inputs and launches the existing local solver. It never searches
directories, downloads configurations, executes manifest commands, makes
network requests, or probes a gateway.

## Explicit manifest

```yaml
format_version: 1
cases:
  - id: case-001
    provenance: synthetic
    config: inputs/config.yaml
    contract: reviewed/contract.yaml
```

Both files must be regular files below the manifest's directory. Paths are
literal, relative names; spaces are permitted, but absolute paths, empty/dot
components, traversal, ASCII control characters, and backslashes are rejected.
Symlink components, directories, and special files are rejected. The manifest
itself must be a regular file. This is a local, stable-input workflow, **not a
race-resistant filesystem sandbox or contract-approval authority**: do not run
against files or directories concurrently controlled by another writer.

The manifest is a single-document YAML/JSON subset. Unknown/duplicate fields,
unknown versions, tags, aliases, merge keys, malformed entries, and empty case
lists fail closed. Backslash escape syntax and literal NUL are intentionally
unsupported anywhere in the manifest; use literal UTF-8 text instead. This
avoids the YAML binding's decoded-NUL truncation of explicit filename strings.
IDs must be unique, 1–64 ASCII letters/digits/hyphens/underscores, starting with
a letter or digit. They are user-chosen labels, not generated anonymization.

Each case has exactly the four fields shown. `provenance` must be `synthetic`,
`upstream-example`, or `authorized-deployment`. These are self-declared labels:
the runner cannot validate authorization, origin, representativeness, or human
approval. Do not relabel examples as deployment data. Preserve a private input
inventory and authorization record outside the summary if a real pilot is
approved later.

All distinct contract paths are read and parsed once before the first config
verification. Cases sharing a path use that same in-memory snapshot. Each
configuration is read once per case, and its exact bytes are both hashed and verified.
Cases then run sequentially. A bad contract prevents verification of its case;
other scheduled cases still run. There are no retries, repairs, mutable scope
flags, implicit default contracts, or automatic evidence retention.

## Interpreting the summary

`experimental_format_version: 1` and `kind: local_advisory_evaluation` identify
this internal format. `profile` identifies the compiled verifier baseline.
`scheduled` and `processed` include every manifest case, even input failures.
`counts` partitions them into proved/violated/vacuous/inconsistent/unknown/errors.
The ordered `cases` array contains:

- The ID and self-declared provenance.
- SHA-256 of the exact configuration bytes, when read, and SHA-256 of the
  existing canonical frozen-contract identity, when parsed. These are not file
  paths or proof certificates.
- The original verdict, assurance status, and sorted unique finding codes.
  Error rows have null verdict/assurance; they are never counted as proved.
- `uncertainty`: `unsupported` for an unsupported unknown, `unresolved` for
  other unknowns, and null otherwise. The runner does not guess whether an
  arbitrary diagnostic means timeout, decoding failure, or another limitation.
- A stable failure category or null: `contract_read_error`, `contract_invalid`,
  `config_read_error`, `verification_error`, `report_mismatch`, or
  `unexpected_error`. Raw diagnostics are intentionally omitted.
- `elapsed_seconds`: wall time for that case's input read/verification, not
  manifest or contract preloading. Timings vary and are not runtime guarantees;
  serialization order and non-timing data are deterministic for the same results.

When the manifest cannot be read/validated, the summary has a top-level
`failure`, `scheduled: null`, and no cases: no trustworthy schedule was loaded.
A fatal runner error likewise does not pretend to have completed a schedule.

Aggregate exit codes are deliberately separate from the public CLI's per-verdict
exit mapping:

| Exit | Meaning |
| --- | --- |
| 0 | A nonempty schedule completed, and every case proved. |
| 1 | Any input/tool failure, or a manifest/runner error. Per-case errors retain the complete scheduled summary. |
| 2 | Invalid runner invocation. |
| 3 | No input/tool errors, but at least one result is not proved. |

This fail-closed exit behavior does not turn the runner into a trusted CI gate.
Use Soundcheck's existing approved-base-contract Action for that separate
workflow, with its documented protection and approval prerequisites.

## Privacy and retention

Default output excludes raw configs, filesystem paths, route/service names,
hosts, witnesses, canonical contract text, raw diagnostics, credentials, and
SMT formulas. The runner projects an allowlisted subset of result fields rather
than serializing a complete report and attempting to redact it afterward.
Tests inject secret sentinels into those fields and exercise actual CLI errors.

IDs, digests, counts, timing, and finding codes can still identify sensitive
configurations or reveal operational information. **This is minimization, not
anonymization.** Review summaries before sharing. Decide access, retention,
deletion, and acceptable collection before running authorized private data.
Keep private manifests/configurations outside this repository and its CI logs.
No telemetry or automatic upload is included.

For local diagnostics, an authorized operator can separately invoke the
existing verifier with that exact config and reviewed contract. Its normal
output is richer and may contain sensitive values. Existing `--evidence-dir`
is also an explicit separate choice: omitting source config text does not make
its contracts, reports, witnesses, or formulas safe to publish. The runner
does not make that retention choice on the operator's behalf.

## Review before any real pilot

1. Obtain explicit permission for the chosen configurations and confirm what
   may be processed locally, retained, or shared. No production changes or
   target requests are part of this runner.
2. Record Kong version/router and check the published assurance profile's
   deployment assumptions. Unverified environment assumptions limit every
   conclusion; a manifest label does not establish them.
3. Have the policy owner review each actual frozen contract and its scope.
   Do not generate intended functionality from the candidate configuration.
   Network contracts require the existing source-IP-integrity acknowledgement.
4. Run advisory-only first and use the [review worksheet](review-worksheet.md).
   Examine conservative candidates and unknowns independently. A model-level
   violation is not automatically a production vulnerability, and a proof is
   relative to the stated model and assumptions.
5. Measure authoring effort, usefulness, confirmed false alarms, missed issues,
   and differences from existing review workflows only with human/independent
   evidence. The summary's coverage and verdict counts do not establish these
   metrics, and an unsupported case is not a negative finding.

The historical `bench/survey.exe` directory scanner is retired and exits 2
without scanning. Its stale parallel heuristics are not v11 assurance evidence.
Do not compare its old percentages with these contract-specific evaluations as
though they measure the same thing.

## Focused acceptance

```sh
eval "$(opam env)"
dune runtest bench/pilot --force -j 1
```

Unit tests inject a clock/verifier for deterministic aggregation, freezing,
privacy and failure controls. Process tests exercise the real pilot runner and
public verifier CLI on synthetic fixtures, checking verdict/assurance/finding
agreement and normalized identity without fixing solver-chosen witnesses or
timings. These tests do not contact partners, perform real deployment pilots,
or replace independent pinned-Kong conformance.
