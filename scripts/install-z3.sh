#!/usr/bin/env bash
set -euo pipefail

# Shared by CI and the reusable Action. Run from the trusted Action checkout;
# the caller cannot override the solver release, URL, or checksum.
fail() { printf '::error title=Soundcheck solver setup::%s\n' "$1" >&2; exit 1; }
[[ $# -eq 0 ]] || fail 'This installer takes no arguments.'
[[ "$(uname -s)" == Linux ]] || fail 'The Action requires a Linux runner with glibc.'
case "$(uname -m)" in
  x86_64)
    soundcheck_z3_archive=z3-4.16.0-x64-glibc-2.39
    soundcheck_z3_sha256=7288c49a5bd6dbafd7b0b0d1f65956b91672da24b08f09242919af159be3418e
    soundcheck_glibc_minor=39
    ;;
  aarch64|arm64)
    soundcheck_z3_archive=z3-4.16.0-arm64-glibc-2.38
    soundcheck_z3_sha256=87fcd963d3eecb0f12cf1c3ef0ad74e84a3a7bd3caed5d94445645ef94ae6274
    soundcheck_glibc_minor=38
    ;;
  *) fail 'Supported runner architectures are x86-64 and ARM64.' ;;
esac

for soundcheck_command in getconf curl sha256sum unzip mktemp; do
  command -v "$soundcheck_command" >/dev/null || fail "Missing required command: $soundcheck_command"
done
soundcheck_glibc="$(getconf GNU_LIBC_VERSION)" || fail 'Cannot identify the runner glibc version.'
[[ "$soundcheck_glibc" =~ ^glibc\ ([0-9]+)\.([0-9]+)$ ]] || fail 'Cannot identify the runner glibc version.'
(( 10#${BASH_REMATCH[1]} > 2 ||
   (10#${BASH_REMATCH[1]} == 2 && 10#${BASH_REMATCH[2]} >= soundcheck_glibc_minor) )) ||
  fail "Z3 needs glibc 2.$soundcheck_glibc_minor or newer on this architecture; use Ubuntu 24.04 or newer."

[[ "${RUNNER_TEMP:-}" == /* && -d "$RUNNER_TEMP" ]] || fail 'RUNNER_TEMP must identify an existing absolute directory.'
[[ "${GITHUB_PATH:-}" == /* && -f "$GITHUB_PATH" ]] || fail 'GITHUB_PATH must identify the runner path file.'
soundcheck_z3_dir="$(mktemp -d "$RUNNER_TEMP/soundcheck-z3.XXXXXX")"
curl --fail --location --silent --show-error --retry 3 \
  --connect-timeout 10 --max-time 120 \
  "https://github.com/Z3Prover/z3/releases/download/z3-4.16.0/${soundcheck_z3_archive}.zip" \
  --output "$soundcheck_z3_dir/z3.zip"
# Verify the downloaded bytes before either extracting or executing them.
printf '%s  %s\n' "$soundcheck_z3_sha256" "$soundcheck_z3_dir/z3.zip" | sha256sum --check --strict
unzip -q "$soundcheck_z3_dir/z3.zip" -d "$soundcheck_z3_dir"
soundcheck_z3_bin="$soundcheck_z3_dir/$soundcheck_z3_archive/bin"
soundcheck_z3_version="$("$soundcheck_z3_bin/z3" -version)"
[[ "$soundcheck_z3_version" == 'Z3 version 4.16.0 - 64 bit' ]] || fail "Unexpected solver version: $soundcheck_z3_version"
printf '%s\n' "$soundcheck_z3_version"
# Subsequent Action steps receive this directory before the distro PATH.
printf '%s\n' "$soundcheck_z3_bin" >> "$GITHUB_PATH"
