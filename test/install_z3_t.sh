#!/usr/bin/env bash
set -euo pipefail

# Exercise setup failures without network, root, or executing downloaded code.
soundcheck_installer="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
soundcheck_scratch="$(mktemp -d "${TMPDIR:-/tmp}/soundcheck-z3-test.XXXXXX")"
trap 'rm -rf "$soundcheck_scratch"' EXIT
mkdir -p "$soundcheck_scratch/bin"
cat > "$soundcheck_scratch/bin/mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
command_name="$(basename "$0")"
printf '%s\n' "$command_name" >> "$SOUNDCHECK_INSTALL_LOG"
case "$command_name" in
  uname)
    case "$1" in
      -s) if [[ "$SOUNDCHECK_INSTALL_CASE" == unsupported-os ]]; then echo Darwin; else echo Linux; fi ;;
      -m)
        case "$SOUNDCHECK_INSTALL_CASE" in
          arm64|arm64-old-glibc) echo aarch64 ;;
          unsupported-arch) echo riscv64 ;;
          *) echo x86_64 ;;
        esac ;;
    esac ;;
  getconf)
    case "$SOUNDCHECK_INSTALL_CASE" in
      old-glibc) echo 'glibc 2.38' ;;
      arm64) echo 'glibc 2.38' ;;
      arm64-old-glibc) echo 'glibc 2.37' ;;
      non-glibc) exit 1 ;;
      *) echo 'glibc 2.39' ;;
    esac ;;
  curl)
    [[ "$SOUNDCHECK_INSTALL_CASE" != download-failure ]] || exit 22
    for argument in "$@"; do
      case "$argument" in
        https://github.com/Z3Prover/z3/releases/download/z3-4.16.0/*.zip)
          archive="${argument##*/}"; archive="${archive%.zip}" ;;
      esac
    done
    [[ -n "${archive:-}" ]]
    while [[ $# -gt 0 && "$1" != --output ]]; do shift; done
    [[ $# -eq 2 ]]
    printf '%s\n' "$archive" > "$2" ;;
  sha256sum)
    cat > "$SOUNDCHECK_INSTALL_CHECKSUM"
    [[ "$SOUNDCHECK_INSTALL_CASE" != checksum-failure ]] || exit 1 ;;
  unzip)
    [[ "$SOUNDCHECK_INSTALL_CASE" != unzip-failure ]] || exit 1
    [[ "$1" == -q && "$3" == -d ]]
    archive="$(cat "$2")"
    mkdir -p "$4/$archive/bin"
    cp "$0" "$4/$archive/bin/z3"
    chmod +x "$4/$archive/bin/z3" ;;
  z3)
    [[ "$1" == -version ]]
    if [[ "$SOUNDCHECK_INSTALL_CASE" == wrong-version ]]; then
      echo 'Z3 version 4.8.12 - 64 bit'
    else
      echo 'Z3 version 4.16.0 - 64 bit'
    fi ;;
esac
MOCK
chmod +x "$soundcheck_scratch/bin/mock"
for soundcheck_command in uname getconf curl sha256sum unzip; do
  ln -s mock "$soundcheck_scratch/bin/$soundcheck_command"
done

export PATH="$soundcheck_scratch/bin:$PATH"
export SOUNDCHECK_INSTALL_LOG="$soundcheck_scratch/commands"
export SOUNDCHECK_INSTALL_CHECKSUM="$soundcheck_scratch/checksum"
# Spaces also check that the runner directory and path file stay single arguments.
export RUNNER_TEMP="$soundcheck_scratch/runner temp"
export GITHUB_PATH="$soundcheck_scratch/github path"
mkdir -p "$RUNNER_TEMP"

for SOUNDCHECK_INSTALL_CASE in x64 arm64 unsupported-os unsupported-arch old-glibc \
  arm64-old-glibc non-glibc download-failure checksum-failure unzip-failure wrong-version; do
  export SOUNDCHECK_INSTALL_CASE
  : > "$SOUNDCHECK_INSTALL_LOG"
  : > "$GITHUB_PATH"
  soundcheck_status=0
  bash "$soundcheck_installer" > "$soundcheck_scratch/output" 2>&1 || soundcheck_status=$?
  case "$SOUNDCHECK_INSTALL_CASE" in
    x64|arm64)
      [[ "$soundcheck_status" -eq 0 ]] || { cat "$soundcheck_scratch/output"; exit 1; }
      [[ "$(wc -l < "$GITHUB_PATH" | tr -d ' ')" == 1 ]]
      soundcheck_bin="$(cat "$GITHUB_PATH")"
      [[ -x "$soundcheck_bin/z3" ]]
      case "$SOUNDCHECK_INSTALL_CASE" in
        x64)
          [[ "$soundcheck_bin" == */z3-4.16.0-x64-glibc-2.39/bin ]]
          grep -q '^7288c49a5bd6dbafd7b0b0d1f65956b91672da24b08f09242919af159be3418e  ' "$SOUNDCHECK_INSTALL_CHECKSUM" ;;
        arm64)
          [[ "$soundcheck_bin" == */z3-4.16.0-arm64-glibc-2.38/bin ]]
          grep -q '^87fcd963d3eecb0f12cf1c3ef0ad74e84a3a7bd3caed5d94445645ef94ae6274  ' "$SOUNDCHECK_INSTALL_CHECKSUM" ;;
      esac
      # These operations must happen in this order; no unchecked execution.
      [[ "$(tail -n 4 "$SOUNDCHECK_INSTALL_LOG")" == $'curl\nsha256sum\nunzip\nz3' ]]
      ;;
    *)
      [[ "$soundcheck_status" -ne 0 && ! -s "$GITHUB_PATH" ]]
      case "$SOUNDCHECK_INSTALL_CASE" in
        unsupported-os|unsupported-arch|old-glibc|arm64-old-glibc|non-glibc)
          ! grep -q '^curl$' "$SOUNDCHECK_INSTALL_LOG" ;;
        download-failure)
          ! grep -q '^sha256sum$' "$SOUNDCHECK_INSTALL_LOG" ;;
        checksum-failure)
          ! grep -Eq '^(unzip|z3)$' "$SOUNDCHECK_INSTALL_LOG" ;;
        unzip-failure)
          ! grep -q '^z3$' "$SOUNDCHECK_INSTALL_LOG" ;;
      esac
      ;;
  esac
  printf 'PASS installer %s\n' "$SOUNDCHECK_INSTALL_CASE"
done
