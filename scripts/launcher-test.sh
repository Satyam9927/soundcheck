#!/usr/bin/env bash
# Regression tests for start.sh/stop.sh process ownership, using mocks only:
# no Docker, no engine, no real web app. Runs on Linux, macOS and Windows (Git
# Bash). Uses its own run directory, so it never touches a real session.
#
#   bash scripts/launcher-test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;; *) WINDOWS=0 ;; esac
# shellcheck source=scripts/launcher-common.sh
. "$ROOT/scripts/launcher-common.sh"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/soundcheck-launcher-test.XXXXXX")"
export SOUNDCHECK_RUN_DIR="$SCRATCH/run" SOUNDCHECK_NO_PAUSE=1 NO_COLOR=1
mkdir -p "$SOUNDCHECK_RUN_DIR"
PORT="${SOUNDCHECK_TEST_PORT:-4109}"
failures=0
started=()

cleanup() {
  local pid
  for pid in ${started[@]+"${started[@]}"}; do kill_tree "$pid"; done
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

check() {
  if eval "$2"; then printf 'ok    %s\n' "$1"; else printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); fi
}

# The PID other tools see: the Windows PID under Git Bash.
os_pid() {
  if [ "$WINDOWS" = 1 ] && [ -r "/proc/$1/winpid" ]; then cat "/proc/$1/winpid"; else printf '%s' "$1"; fi
}

# An unrelated Node application listening on $PORT, as another project would.
cat >"$SCRATCH/other-app.js" <<'EOF'
require("http").createServer((_, res) => res.end("someone else's app")).listen(Number(process.argv[2]), "127.0.0.1");
EOF
node "$SCRATCH/other-app.js" "$PORT" >/dev/null 2>&1 &
OTHER="$(os_pid $!)"
started+=("$OTHER")
for _ in $(seq 1 20); do curl -sf -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.5; done

check "the unrelated app is running" "pid_alive $OTHER"
check "the unrelated app is not recognised as Soundcheck" "! owned $OTHER"

# 1. stop.sh must not stop another app that took the recorded port.
echo "$PORT" >"$SOUNDCHECK_RUN_DIR/frontend.port"
bash "$ROOT/stop.sh" >"$SCRATCH/stop1.log" 2>&1
check "stop.sh leaves an unrelated app on the recorded port alone" "pid_alive $OTHER"
check "stop.sh says why it left it alone" "grep -q 'another application' '$SCRATCH/stop1.log'"

# 2. stop.sh must not stop a process that reused the recorded PID.
echo "$OTHER" >"$SOUNDCHECK_RUN_DIR/frontend.pid"
bash "$ROOT/stop.sh" >"$SCRATCH/stop2.log" 2>&1
check "stop.sh leaves a process that reused the recorded PID alone" "pid_alive $OTHER"
check "stop.sh forgets the stale PID" "[ ! -f '$SOUNDCHECK_RUN_DIR/frontend.pid' ]"

# 3. A start that never becomes ready must stop what it launched before
#    forgetting it. The mock "node" stays alive but never serves anything.
cat >"$SCRATCH/fake-node" <<'EOF'
#!/usr/bin/env bash
sleep 300 &
wait
EOF
chmod +x "$SCRATCH/fake-node"
mkdir -p "$ROOT/frontend/node_modules"
[ -f "$ROOT/frontend/node_modules/.soundcheck-installed" ] || touch "$ROOT/frontend/node_modules/.soundcheck-installed"
SOUNDCHECK_NODE="$SCRATCH/fake-node" SOUNDCHECK_READY_TIMEOUT=3 \
  bash "$ROOT/start.sh" --native --skip-engine --port "$((PORT + 1))" >"$SCRATCH/start.log" 2>&1
status=$?
check "start.sh fails when the web app never becomes ready" "[ $status -ne 0 ]"
check "start.sh reports the failure" "grep -q 'did not become ready' '$SCRATCH/start.log'"
check "start.sh stopped the web app it launched" "grep -q 'Stopping the web app that failed to start' '$SCRATCH/start.log'"
launched="$(sed -n 's/.*Stopping the web app that failed to start (pid \([0-9]*\)).*/\1/p' "$SCRATCH/start.log")"
check "the launched process is gone" "[ -n '$launched' ] && ! pid_alive '$launched'"
check "start.sh removed its PID file" "[ ! -f '$SOUNDCHECK_RUN_DIR/frontend.pid' ]"

# 4. And stop.sh does stop a web app this checkout launched: ownership must not
#    simply always say no. The mock carries the absolute Next.js path, as start.sh passes it.
next_path="$ROOT/frontend/node_modules/next/dist/bin/next"
if [ "$WINDOWS" = 1 ]; then next_path="$(cygpath -w "$next_path")"; fi
"$SCRATCH/fake-node" "$next_path" dev -H 127.0.0.1 -p "$((PORT + 2))" >/dev/null 2>&1 &
OURS="$(os_pid $!)"
started+=("$OURS")
sleep 1
check "a launcher-started web app is recognised as Soundcheck" "owned $OURS"
echo "$OURS" >"$SOUNDCHECK_RUN_DIR/frontend.pid"
bash "$ROOT/stop.sh" >"$SCRATCH/stop3.log" 2>&1
check "stop.sh stops the web app this checkout launched" "! pid_alive $OURS"

if [ "$failures" -ne 0 ]; then
  printf '\n%d check(s) failed. start.sh output:\n' "$failures"
  cat "$SCRATCH/start.log"
  exit 1
fi
printf '\nAll launcher checks passed.\n'
