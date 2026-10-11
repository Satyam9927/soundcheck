#!/usr/bin/env bash
set -euo pipefail

soundcheck_command="${0##*/}"
printf '%s|%s|%s\n' "$soundcheck_command" "$*" "$PWD" >> "$SOUNDCHECK_WRAPPER_LOG"
case "$soundcheck_command" in
  opam)
    [[ "$*" == env ]] || exit 99
    [[ "$SOUNDCHECK_WRAPPER_CASE" != opam-failure ]] || exit 39
    ;;
  dune)
    case "$*" in
      --version)
        [[ "$SOUNDCHECK_WRAPPER_CASE" != dune-version-failure ]] || exit 37
        printf 'fixture-dune\n'
        ;;
      'build @all')
        IFS= read -r soundcheck_marker < marker.txt
        printf 'snapshot|%s|%s|%s\n' "$(git rev-parse HEAD)" "$soundcheck_marker" "$PWD" >> "$SOUNDCHECK_WRAPPER_LOG"
        case "$SOUNDCHECK_WRAPPER_CASE" in
          *build-failure) exit 41 ;;
        esac
        ;;
      'test -j 1'|'test --force -j 1')
        case "$SOUNDCHECK_WRAPPER_CASE" in
          *test-failure) exit 42 ;;
          clean-dirty-success) printf 'unexpected file\n' > unexpected.txt ;;
        esac
        ;;
      *) echo "Unexpected Dune command: $*" >&2; exit 99 ;;
    esac
    ;;
  z3)
    [[ "$*" == -version ]] || exit 99
    [[ "$SOUNDCHECK_WRAPPER_CASE" != z3-version-failure ]] || exit 38
    printf 'Z3 version fixture-z3\n'
    ;;
  docker)
    [[ "$*" == info ]] || exit 99
    case "$SOUNDCHECK_WRAPPER_CASE" in
      *docker-failure) exit 44 ;;
    esac
    ;;
  curl)
    echo 'Wrapper tests must not send network requests' >&2
    exit 99
    ;;
  run.sh)
    [[ $# -eq 0 ]] || exit 99
    case "$SOUNDCHECK_WRAPPER_CASE" in
      *conformance-failure) exit 43 ;;
    esac
    ;;
  *) echo "Unexpected mock command: $soundcheck_command" >&2; exit 99 ;;
esac
