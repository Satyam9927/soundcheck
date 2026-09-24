#!/usr/bin/env bash
# Start Soundcheck and wait until the web UI responds. Stop with ./stop.sh.
#
#   ./start.sh [--port N] [--skip-tests]                    Docker (default)
#   ./start.sh --native [--prod] [--port N] [--skip-engine] local toolchain
#
#   (default)      build and run the all-in-one image (engine + z3 + UI); needs
#                  only Docker. The CLI then works via ./soundcheck.sh.
#   --skip-tests   skip the `dune test` gate during the image build
#   --native       run the UI with Node and the engine from a local dune build
#   --prod         native: production build + `next start` (default: dev server)
#   --skip-engine  native: do not run `dune build`
#   --port N       web port (default: 3000, or $PORT)
#
# The engine is a CLI invoked per request, not a daemon, so there is no separate
# backend process. The MCP server (`soundcheck mcp`) is started on demand by the
# agent that uses it over stdio.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND="$ROOT/frontend"
RUN_DIR="$ROOT/.run"
PID_FILE="$RUN_DIR/frontend.pid"
LOG_FILE="$RUN_DIR/frontend.log"
IMAGE="${SOUNDCHECK_IMAGE:-soundcheck:local}"
CONTAINER="soundcheck-web"

DOCKER=1
MODE="dev"
PORT="${PORT:-3000}"
BUILD_ENGINE=1
RUN_TESTS=1

while [ $# -gt 0 ]; do
  case "$1" in
    --native) DOCKER=0 ;;
    --prod) MODE="prod" ;;
    --port) PORT="${2:?--port requires a value}"; shift ;;
    --skip-engine) BUILD_ENGINE=0 ;;
    --skip-tests) RUN_TESTS=0 ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done

if [ "$DOCKER" = 1 ] && { [ "$MODE" = prod ] || [ "$BUILD_ENGINE" = 0 ]; }; then
  echo "--prod and --skip-engine apply to --native only (the image is always a production build)" >&2
  exit 2
fi

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;; *) WINDOWS=0 ;; esac

info() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

pid_alive() {
  local pid="$1"
  if [ "$WINDOWS" = 1 ]; then
    tasklist //FI "PID eq $pid" 2>/dev/null | grep -q " $pid "
  else
    kill -0 "$pid" 2>/dev/null
  fi
}

port_busy() {
  if [ "$WINDOWS" = 1 ]; then
    netstat -ano 2>/dev/null | grep -E "[:.]$PORT[[:space:]].*LISTENING" >/dev/null
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1
  else
    (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null
  fi
}

container_running() {
  command -v docker >/dev/null 2>&1 &&
    [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" = "true" ]
}

# Polls the UI until it answers; $1 is a command that fails once the server died.
wait_until_ready() {
  local alive_check="$1" url="http://localhost:$PORT" status
  for _ in $(seq 1 90); do
    if ! $alive_check; then
      return 1
    fi
    if status="$(curl -fsS "$url/api/engine" 2>/dev/null)"; then
      info "Soundcheck is running at $url"
      case "$status" in
        *'"available":true'*'"solver":{"available":true'*) info "Engine ready ($(printf '%s' "$status" | sed -n 's/.*"profile":"\([^"]*\)".*/\1/p'))" ;;
        *) warn "engine not ready: $(printf '%s' "$status" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')" ;;
      esac
      return 0
    fi
    sleep 1
  done
  return 2
}

mkdir -p "$RUN_DIR"

if container_running; then
  info "Soundcheck is already running in Docker (container $CONTAINER). Use ./stop.sh first."
  exit 0
fi
if [ -f "$PID_FILE" ] && pid_alive "$(cat "$PID_FILE")"; then
  info "Soundcheck is already running (pid $(cat "$PID_FILE")). Use ./stop.sh first."
  exit 0
fi
rm -f "$PID_FILE"

port_busy && fail "port $PORT is already in use. Pick another with --port N."

# --- docker mode -------------------------------------------------------------

if [ "$DOCKER" = 1 ]; then
  command -v docker >/dev/null 2>&1 || fail "Docker is not installed. Install it, or run ./start.sh --native with a local toolchain."
  docker info >/dev/null 2>&1 || fail "the Docker daemon is not running. Start Docker Desktop (or dockerd), or use --native."

  info "Building image $IMAGE (cached layers make rebuilds fast)"
  docker build --build-arg RUN_TESTS="$RUN_TESTS" -t "$IMAGE" "$ROOT"

  # A stopped container with our name is a leftover from a previous run.
  docker rm "$CONTAINER" >/dev/null 2>&1 || true

  info "Starting container $CONTAINER on port $PORT"
  docker run -d --rm --name "$CONTAINER" -p "$PORT:3000" "$IMAGE" web >/dev/null
  echo docker >"$RUN_DIR/mode"
  echo "$PORT" >"$RUN_DIR/frontend.port"

  if wait_until_ready container_running; then
    echo "    logs: docker logs -f $CONTAINER"
    echo "    cli:  ./soundcheck.sh verify <config.yaml> [...]"
    echo "    stop: ./stop.sh"
    exit 0
  fi
  docker logs --tail 30 "$CONTAINER" >&2 2>&1 || true
  fail "the container did not become ready"
fi

# --- native mode: engine -----------------------------------------------------

if [ -n "${SOUNDCHECK_BIN:-}" ]; then
  info "Using engine from SOUNDCHECK_BIN=$SOUNDCHECK_BIN"
elif [ "$BUILD_ENGINE" = 1 ]; then
  if command -v opam >/dev/null 2>&1; then
    eval "$(opam env 2>/dev/null)" || true
  fi
  if command -v dune >/dev/null 2>&1; then
    info "Building the engine (dune build)"
    if ! (cd "$ROOT" && dune build 2>&1); then
      warn "dune build failed. The web app will start, but live verification is unavailable."
    fi
  else
    warn "dune not found. The web app will start read-only. Drop --native to run everything in Docker."
  fi
fi

command -v z3 >/dev/null 2>&1 || warn "z3 not found on PATH. Verification and comparison need it (or drop --native)."

# --- native mode: web app ----------------------------------------------------

command -v node >/dev/null 2>&1 || fail "Node.js is required (v20 or newer)."
command -v npm >/dev/null 2>&1 || fail "npm is required."

cd "$FRONTEND"
STAMP="node_modules/.soundcheck-installed"
if [ ! -f "$STAMP" ] || [ package.json -nt "$STAMP" ] || [ package-lock.json -nt "$STAMP" ]; then
  info "Installing frontend dependencies"
  npm install --no-audit --no-fund
  touch "$STAMP"
fi

NEXT="node_modules/next/dist/bin/next"
if [ "$MODE" = "prod" ]; then
  info "Building the web app for production"
  node "$NEXT" build
  ARGS=(start -p "$PORT")
else
  ARGS=(dev -p "$PORT")
fi

info "Starting the web app ($MODE) on port $PORT"
export SOUNDCHECK_REPO="$ROOT"
nohup node "$NEXT" "${ARGS[@]}" >"$LOG_FILE" 2>&1 &
PID=$!
if [ "$WINDOWS" = 1 ] && [ -r "/proc/$PID/winpid" ]; then
  PID="$(cat "/proc/$PID/winpid")"
fi
echo "$PID" >"$PID_FILE"
echo native >"$RUN_DIR/mode"
echo "$PORT" >"$RUN_DIR/frontend.port"

native_alive() { pid_alive "$PID"; }

if wait_until_ready native_alive; then
  echo "    pid:  $PID"
  echo "    logs: $LOG_FILE"
  echo "    stop: ./stop.sh"
  exit 0
fi
tail -n 30 "$LOG_FILE" >&2 || true
rm -f "$PID_FILE"
fail "the web app did not become ready (log: $LOG_FILE)"
