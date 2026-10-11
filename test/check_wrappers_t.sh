#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo 'Usage: check_wrappers_t.sh <check.sh> <check-commit.sh> <mock-command.sh>' >&2
  exit 2
fi

# A fixture must never inherit routing into the caller's repository, index,
# object store, namespace or command-line configuration. Clear all Git-prefixed
# variables (including indexed GIT_CONFIG_KEY/VALUE entries) before ANY Git
# operation. PATH and the opam environment remain untouched.
while IFS= read -r soundcheck_git_variable; do
  unset "$soundcheck_git_variable"
done < <(compgen -A variable GIT_)
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null

soundcheck_fast_source="$1"
soundcheck_commit_source="$2"
soundcheck_mock_source="$3"
soundcheck_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/soundcheck-wrapper-test.XXXXXX")"
soundcheck_test_dir="$(cd "$soundcheck_test_dir" && pwd)"
readonly soundcheck_test_dir

cleanup() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 ]]; then
    printf 'Wrapper test diagnostics retained at %s\n' "$soundcheck_test_dir" >&2
    exit "$status"
  fi
  # This is the immutable fresh mktemp root above, including only our synthetic
  # Git repository, linked worktrees and mocked-command logs. No user checkout.
  rm -rf -- "$soundcheck_test_dir"
}
trap cleanup EXIT

soundcheck_fixture_repo="$soundcheck_test_dir/repo with spaces"
soundcheck_mock_bin="$soundcheck_test_dir/bin"
mkdir -p "$soundcheck_fixture_repo/scripts" "$soundcheck_fixture_repo/bench/kong/conformance" "$soundcheck_mock_bin"
cp "$soundcheck_fast_source" "$soundcheck_fixture_repo/scripts/check.sh"
cp "$soundcheck_commit_source" "$soundcheck_fixture_repo/scripts/check-commit.sh"
cp "$soundcheck_mock_source" "$soundcheck_mock_bin/mock-command"
chmod u+x "$soundcheck_mock_bin/mock-command"
for soundcheck_command in opam dune z3 docker curl; do
  ln -s mock-command "$soundcheck_mock_bin/$soundcheck_command"
done
cp "$soundcheck_mock_source" "$soundcheck_fixture_repo/bench/kong/conformance/run.sh"

# Only this newly created repository receives commits. Ignore user signing and
# hooks; marker snapshots distinguish requested commits from dirty source files.
git init --quiet "$soundcheck_fixture_repo"
git -C "$soundcheck_fixture_repo" config user.name 'Soundcheck wrapper test'
git -C "$soundcheck_fixture_repo" config user.email 'wrapper-test@example.invalid'
git -C "$soundcheck_fixture_repo" config core.hooksPath /dev/null
git -C "$soundcheck_fixture_repo" config commit.gpgsign false
printf 'first\n' > "$soundcheck_fixture_repo/marker.txt"
git -C "$soundcheck_fixture_repo" add -- scripts bench marker.txt
git -C "$soundcheck_fixture_repo" commit --quiet -m 'First fixture snapshot'
soundcheck_first_commit="$(git -C "$soundcheck_fixture_repo" rev-parse HEAD)"
printf 'second\n' > "$soundcheck_fixture_repo/marker.txt"
git -C "$soundcheck_fixture_repo" add -- marker.txt
git -C "$soundcheck_fixture_repo" commit --quiet -m 'Second fixture snapshot'
soundcheck_second_commit="$(git -C "$soundcheck_fixture_repo" rev-parse HEAD)"
printf 'dirty\n' > "$soundcheck_fixture_repo/marker.txt"

fail() {
  printf 'Wrapper case %s: %s\n' "$soundcheck_case" "$1" >&2
  exit 1
}

run_case() {
  soundcheck_case="$1"
  local wrapper="$2"
  shift 2
  soundcheck_case_tmp="$soundcheck_test_dir/$soundcheck_case-tmp"
  mkdir -p "$soundcheck_case_tmp"
  soundcheck_log="$soundcheck_test_dir/$soundcheck_case.commands"
  soundcheck_stdout="$soundcheck_test_dir/$soundcheck_case.stdout"
  soundcheck_stderr="$soundcheck_test_dir/$soundcheck_case.stderr"
  : > "$soundcheck_log"
  soundcheck_status=0
  PATH="$soundcheck_mock_bin:$PATH" TMPDIR="$soundcheck_case_tmp" \
    SOUNDCHECK_WRAPPER_CASE="$soundcheck_case" SOUNDCHECK_WRAPPER_LOG="$soundcheck_log" \
    bash "$soundcheck_fixture_repo/scripts/$wrapper" "$@" \
      > "$soundcheck_stdout" 2> "$soundcheck_stderr" || soundcheck_status=$?
}

expect_exit() {
  [[ "$soundcheck_status" -eq "$1" ]] || fail "expected exit $1, got $soundcheck_status"
  if [[ "$soundcheck_status" -ne 0 ]] && grep -Fq 'checks passed' "$soundcheck_stdout"; then
    fail 'failed validation printed a success message'
  fi
}

expect_count() {
  local count
  count="$(awk -v prefix="$1" 'index($0, prefix) == 1 { n++ } END { print n+0 }' "$soundcheck_log")"
  [[ "$count" -eq "$2" ]] || fail "expected $2 calls starting with $1, got $count"
}

expect_contains() {
  grep -Fq -- "$2" "$1" || fail "missing expected text: $2"
}

expect_no_temporary_worktree() {
  local retained
  retained="$(find "$soundcheck_case_tmp" -mindepth 1 -maxdepth 1 -type d -name 'soundcheck-check.*' -print)"
  [[ -z "$retained" ]] || fail 'successful or preflight-rejected run left temporary artifacts'
}

expect_retained_worktree() {
  local retained
  retained="$(find "$soundcheck_case_tmp" -mindepth 2 -maxdepth 2 -type d -name worktree -print)"
  [[ -n "$retained" && -f "$retained/.git" ]] || fail 'failure did not retain a linked worktree'
  [[ "$(git -C "$retained" rev-parse HEAD)" == "$soundcheck_first_commit" ]] || fail 'retained worktree is not the requested commit'
  IFS= read -r soundcheck_marker < "$retained/marker.txt"
  [[ "$soundcheck_marker" == first ]] || fail 'retained worktree included dirty workspace content'
  if [[ "$soundcheck_case" == clean-dirty-success ]]; then
    [[ -f "$retained/unexpected.txt" ]] || fail 'cleanup removed unexpected test output'
    expect_contains "$soundcheck_stderr" 'Could not clean up worktree; retained at'
  else
    expect_contains "$soundcheck_stderr" 'Validation failed; temporary files retained at'
  fi
}

for soundcheck_case in default fast full conformance; do
  if [[ "$soundcheck_case" == default ]]; then
    run_case "$soundcheck_case" check.sh
  else
    run_case "$soundcheck_case" check.sh "$soundcheck_case"
  fi
  expect_exit 0
  expect_count 'opam|env|' 1
  expect_count 'dune|--version|' 1
  expect_count 'z3|-version|' 1
  expect_contains "$soundcheck_stdout" 'Toolchain: Dune fixture-dune; Z3 version fixture-z3'
  case "$soundcheck_case" in
    default|fast)
      expect_count 'docker|' 0
      expect_count 'dune|build @all|' 1
      expect_count 'dune|test -j 1|' 1
      expect_count 'dune|test --force -j 1|' 0
      expect_count 'run.sh|' 0
      expect_contains "$soundcheck_stdout" 'Soundcheck fast checks passed.' ;;
    full)
      expect_count 'docker|info|' 1
      expect_count 'dune|build @all|' 1
      expect_count 'dune|test --force -j 1|' 1
      expect_count 'run.sh||' 1
      expect_contains "$soundcheck_stdout" 'Soundcheck full checks passed.' ;;
    conformance)
      expect_count 'docker|info|' 1
      expect_count 'dune|build ' 0
      expect_count 'dune|test ' 0
      expect_count 'run.sh||' 1
      expect_contains "$soundcheck_stdout" 'Soundcheck conformance checks passed.' ;;
  esac
  expect_count 'curl|' 0
  printf '[ok] validation wrapper: %s\n' "$soundcheck_case"
done

for soundcheck_case in help invalid-mode extra-argument; do
  case "$soundcheck_case" in
    help) run_case "$soundcheck_case" check.sh --help; expect_exit 0 ;;
    invalid-mode) run_case "$soundcheck_case" check.sh unknown; expect_exit 2 ;;
    extra-argument) run_case "$soundcheck_case" check.sh fast extra; expect_exit 2 ;;
  esac
  [[ ! -s "$soundcheck_log" ]] || fail 'argument handling invoked external tools'
  printf '[ok] validation wrapper: %s\n' "$soundcheck_case"
done

for soundcheck_case in fast-build-failure fast-test-failure full-build-failure full-test-failure \
    full-conformance-failure only-conformance-failure full-docker-failure only-docker-failure \
    opam-failure dune-version-failure z3-version-failure; do
  soundcheck_mode=fast
  case "$soundcheck_case" in
    full-*) soundcheck_mode=full ;;
    only-*) soundcheck_mode=conformance ;;
  esac
  run_case "$soundcheck_case" check.sh "$soundcheck_mode"
  case "$soundcheck_case" in
    *build-failure)
      expect_exit 41
      expect_count 'dune|build @all|' 1
      expect_count 'dune|test ' 0
      expect_count 'run.sh|' 0 ;;
    *test-failure)
      expect_exit 42
      expect_count 'dune|build @all|' 1
      expect_count 'dune|test ' 1
      expect_count 'run.sh|' 0 ;;
    *conformance-failure)
      expect_exit 43
      expect_count 'run.sh||' 1 ;;
    *docker-failure)
      expect_exit 1
      expect_count 'docker|info|' 1
      expect_count 'dune|build ' 0
      expect_count 'dune|test ' 0
      expect_count 'run.sh|' 0
      expect_contains "$soundcheck_stderr" 'Docker is unavailable; conformance was not run.' ;;
    opam-failure) expect_exit 39 ;;
    dune-version-failure) expect_exit 37 ;;
    z3-version-failure) expect_exit 38 ;;
  esac
  case "$soundcheck_case" in
    opam-failure|*-version-failure)
      expect_count 'dune|build ' 0
      expect_count 'dune|test ' 0
      expect_count 'docker|' 0
      expect_count 'run.sh|' 0 ;;
  esac
  printf '[ok] validation wrapper: %s\n' "$soundcheck_case"
done

for soundcheck_case in clean-requested clean-default clean-build-failure clean-test-failure clean-dirty-success; do
  if [[ "$soundcheck_case" == clean-default ]]; then
    run_case "$soundcheck_case" check-commit.sh
    soundcheck_expected_commit="$soundcheck_second_commit"
    soundcheck_expected_marker=second
  else
    run_case "$soundcheck_case" check-commit.sh "$soundcheck_first_commit"
    soundcheck_expected_commit="$soundcheck_first_commit"
    soundcheck_expected_marker=first
  fi
  expect_count "opam|env|$soundcheck_fixture_repo" 1
  expect_count 'dune|build @all|' 1
  expect_count "snapshot|$soundcheck_expected_commit|$soundcheck_expected_marker|" 1
  expect_count 'docker|' 0
  expect_count 'run.sh|' 0
  case "$soundcheck_case" in
    clean-requested|clean-default)
      expect_exit 0
      expect_count 'dune|test --force -j 1|' 1
      expect_contains "$soundcheck_stdout" "Clean-worktree regression checks passed for $soundcheck_expected_commit."
      expect_no_temporary_worktree ;;
    clean-build-failure)
      expect_exit 41
      expect_count 'dune|test ' 0
      expect_retained_worktree ;;
    clean-test-failure)
      expect_exit 42
      expect_count 'dune|test --force -j 1|' 1
      expect_retained_worktree ;;
    clean-dirty-success)
      expect_exit 1
      expect_count 'dune|test --force -j 1|' 1
      expect_retained_worktree ;;
  esac
  IFS= read -r soundcheck_marker < "$soundcheck_fixture_repo/marker.txt"
  [[ "$soundcheck_marker" == dirty ]] || fail 'clean validation changed the original dirty workspace'
  printf '[ok] clean-commit wrapper: %s\n' "$soundcheck_case"
done

for soundcheck_case in clean-help clean-extra-argument clean-invalid-revision clean-noncommit; do
  case "$soundcheck_case" in
    clean-help) run_case "$soundcheck_case" check-commit.sh --help; expect_exit 0 ;;
    clean-extra-argument) run_case "$soundcheck_case" check-commit.sh HEAD extra; expect_exit 2 ;;
    clean-invalid-revision) run_case "$soundcheck_case" check-commit.sh does-not-exist; expect_exit 128 ;;
    clean-noncommit) run_case "$soundcheck_case" check-commit.sh 'HEAD^{tree}'; expect_exit 128 ;;
  esac
  [[ ! -s "$soundcheck_log" ]] || fail 'invalid revision/argument invoked build tools'
  expect_no_temporary_worktree
  printf '[ok] clean-commit wrapper: %s\n' "$soundcheck_case"
done

soundcheck_check_count=27
if [[ "${SOUNDCHECK_WRAPPER_GIT_ISOLATION_CHILD:-0}" != 1 ]]; then
  soundcheck_case=ambient-git-isolation
  soundcheck_guard_repo="$soundcheck_test_dir/guard repo"
  soundcheck_guard_index="$soundcheck_test_dir/guard-index"
  soundcheck_guard_hooks="$soundcheck_test_dir/guard-hooks"
  soundcheck_guard_config="$soundcheck_test_dir/guard-config"
  mkdir -p "$soundcheck_guard_repo" "$soundcheck_guard_hooks" "$soundcheck_test_dir/isolation-child-tmp"
  git init --quiet "$soundcheck_guard_repo"
  git -C "$soundcheck_guard_repo" config user.name 'Owned isolation guard'
  git -C "$soundcheck_guard_repo" config user.email 'isolation-guard@example.invalid'
  git -C "$soundcheck_guard_repo" config core.hooksPath /dev/null
  git -C "$soundcheck_guard_repo" config commit.gpgsign false
  printf 'must remain unchanged\n' > "$soundcheck_guard_repo/guard.txt"
  git -C "$soundcheck_guard_repo" add -- guard.txt
  git -C "$soundcheck_guard_repo" commit --quiet -m 'Owned isolation guard'
  soundcheck_guard_head="$(git -C "$soundcheck_guard_repo" rev-parse HEAD)"
  soundcheck_guard_refs="$(git -C "$soundcheck_guard_repo" for-each-ref)"
  cp "$soundcheck_guard_repo/.git/index" "$soundcheck_guard_index"
  cp "$soundcheck_guard_index" "$soundcheck_test_dir/guard-index-before"
  cp "$soundcheck_guard_repo/.git/config" "$soundcheck_test_dir/guard-repo-config-before"
  printf '[core]\n\thooksPath = %s\n' "$soundcheck_guard_hooks" > "$soundcheck_guard_config"
  printf '#!/usr/bin/env bash\nprintf "unexpected hook\\n" > "%s"\nexit 98\n' \
    "$soundcheck_test_dir/guard-hook-ran" > "$soundcheck_guard_hooks/pre-commit"
  chmod u+x "$soundcheck_guard_hooks/pre-commit"

  # Every redirection target is owned by this test, never the user's checkout.
  # The nested invocation is bounded to one level and reruns only mocked tools.
  if ! GIT_DIR="$soundcheck_guard_repo/.git" \
      GIT_WORK_TREE="$soundcheck_guard_repo" GIT_COMMON_DIR="$soundcheck_guard_repo/.git" \
      GIT_INDEX_FILE="$soundcheck_guard_index" GIT_OBJECT_DIRECTORY="$soundcheck_guard_repo/.git/objects" \
      GIT_ALTERNATE_OBJECT_DIRECTORIES="$soundcheck_guard_repo/.git/objects" GIT_NAMESPACE=fixture-guard \
      GIT_CONFIG="$soundcheck_guard_config" GIT_CONFIG_GLOBAL="$soundcheck_guard_config" \
      GIT_CONFIG_SYSTEM="$soundcheck_guard_config" GIT_CONFIG_NOSYSTEM=0 \
      GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0="$soundcheck_guard_hooks" \
      GIT_CONFIG_KEY_1=core.worktree GIT_CONFIG_VALUE_1="$soundcheck_guard_repo" \
      GIT_CONFIG_PARAMETERS="'core.hooksPath'='$soundcheck_guard_hooks'" \
      SOUNDCHECK_WRAPPER_GIT_ISOLATION_CHILD=1 TMPDIR="$soundcheck_test_dir/isolation-child-tmp" \
      bash "$0" "$soundcheck_fast_source" "$soundcheck_commit_source" "$soundcheck_mock_source" \
        > "$soundcheck_test_dir/git-isolation.stdout" 2> "$soundcheck_test_dir/git-isolation.stderr"; then
    fail 'wrapper tests failed under owned ambient Git redirection'
  fi
  [[ "$(git -C "$soundcheck_guard_repo" rev-parse HEAD)" == "$soundcheck_guard_head" ]] || fail 'ambient repository HEAD changed'
  [[ "$(git -C "$soundcheck_guard_repo" for-each-ref)" == "$soundcheck_guard_refs" ]] || fail 'ambient repository refs changed'
  [[ -z "$(git -C "$soundcheck_guard_repo" status --porcelain)" ]] || fail 'ambient worktree or index changed'
  cmp -s "$soundcheck_guard_index" "$soundcheck_test_dir/guard-index-before" || fail 'ambient external index changed'
  cmp -s "$soundcheck_guard_repo/.git/config" "$soundcheck_test_dir/guard-repo-config-before" || fail 'ambient repository config changed'
  [[ ! -e "$soundcheck_test_dir/guard-hook-ran" ]] || fail 'ambient hook configuration was executed'
  expect_contains "$soundcheck_test_dir/git-isolation.stdout" 'All 27 validation-wrapper checks passed'
  soundcheck_check_count=28
  printf '[ok] validation wrapper: ambient-git-isolation\n'
fi

printf 'All %s validation-wrapper checks passed (mock commands, synthetic local Git, no Docker).\n' "$soundcheck_check_count"
