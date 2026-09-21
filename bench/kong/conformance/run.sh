#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CONFIG="$SCRIPT_DIR/kong.yaml"
PROBES="$SCRIPT_DIR/probes.tsv"
KONG_IMAGE="kong:3.9.3@sha256:ca71c5591eabaf18de96d26b7eed5e2fdb590dac141e467a779c38017e5bdf81"
CONTAINER=""

cleanup() {
  if [[ -n "$CONTAINER" ]]; then
    docker rm --force "$CONTAINER" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cd "$REPO_ROOT"
eval "$(opam env)"
dune build bench/kong_model_oracle.exe
ORACLE="$REPO_ROOT/_build/default/bench/kong_model_oracle.exe"

run_flavor() {
  local flavor="$1"
  local port="$2"
  local failures=0
  CONTAINER="soundcheck-kong-conformance-${flavor}"

  docker run --detach --name "$CONTAINER" \
    --publish "127.0.0.1:${port}:8000" \
    --volume "$CONFIG:/kong/declarative/kong.yml:ro" \
    --env KONG_DATABASE=off \
    --env KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yml \
    --env KONG_ROUTER_FLAVOR="$flavor" \
    --env KONG_ALLOW_DEBUG_HEADER=on \
    "$KONG_IMAGE" >/dev/null

  local ready=false
  local attempt
  for attempt in {1..30}; do
    if curl --silent --output /dev/null --max-time 2 \
        "http://127.0.0.1:${port}/not-configured"; then
      ready=true
      break
    fi
    if [[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER")" != "true" ]]; then
      break
    fi
    sleep 1
  done
  if [[ "$ready" != "true" ]]; then
    echo "Kong failed to become ready for router flavor $flavor" >&2
    docker logs "$CONTAINER" >&2
    return 1
  fi

  while IFS='|' read -r name method path host header; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    local host_value="127.0.0.1"
    local curl_args=(--silent --output /dev/null --dump-header - \
      --request "$method" --header "Kong-Debug: 1")
    local oracle_args=("$CONFIG" "$method" "$path" "$host_value")
    if [[ "$host" != "-" ]]; then
      host_value="$host"
      curl_args+=(--header "Host: $host")
      oracle_args[3]="$host"
    fi
    if [[ "$header" != "-" ]]; then
      curl_args+=(--header "$header")
      oracle_args+=("$header")
    fi

    local response actual_route actual_service actual_decision expected
    response="$(curl "${curl_args[@]}" "http://127.0.0.1:${port}${path}")"
    actual_route="$(printf '%s\n' "$response" | awk -F ': *' \
      'tolower($1) == "kong-route-name" { sub("\\r$", "", $2); print $2 }' | tail -1)"
    actual_service="$(printf '%s\n' "$response" | awk -F ': *' \
      'tolower($1) == "kong-service-name" { sub("\\r$", "", $2); print $2 }' | tail -1)"
    actual_route="${actual_route:--}"
    actual_service="${actual_service:--}"
    if [[ "$actual_route" != "-" && "$actual_service" != "-" ]]; then
      actual_decision="allow"
    else
      actual_decision="deny"
    fi
    expected="$("$ORACLE" "${oracle_args[@]}")"
    if [[ "$expected" != "${actual_decision}"$'\t'"${actual_route}"$'\t'"${actual_service}" ]]; then
      echo "MISMATCH [$flavor/$name] $method $path host=$host header=$header" >&2
      echo "  model: $expected" >&2
      echo "  Kong:  ${actual_decision}"$'\t'"${actual_route}"$'\t'"${actual_service}" >&2
      failures=$((failures + 1))
    else
      echo "ok [$flavor] $name"
    fi
  done < "$PROBES"

  docker rm --force "$CONTAINER" >/dev/null
  CONTAINER=""
  [[ "$failures" -eq 0 ]]
}

run_flavor traditional 18000
run_flavor traditional_compatible 18001
echo "Kong differential conformance passed"
