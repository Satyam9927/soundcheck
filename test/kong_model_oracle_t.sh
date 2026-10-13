#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo 'Usage: kong_model_oracle_t.sh <oracle> <ip-fixture>' >&2
  exit 2
fi
soundcheck_oracle="$1"
soundcheck_ip_fixture="$2"
soundcheck_checks=0

expect_request() {
  local path="$1" source="$2" decision="$3" route="$4" service="$5" actual expected
  actual="$("$soundcheck_oracle" "$soundcheck_ip_fixture" anonymous http GET "$path" localhost '' "$source")"
  expected="supported"$'\t'"$decision"$'\t'"$decision"$'\n'"$route"$'\t'"$service"
  [[ "$actual" == "$expected" ]] || {
    printf 'Oracle source protocol mismatch: %s from %s\nexpected: %s\nactual: %s\n' "$path" "$source" "$expected" "$actual" >&2
    exit 1
  }
  soundcheck_checks=$((soundcheck_checks + 1))
}

# These are protocol/model regressions, not independent target conformance.
# Real target expectations for the same requests live in ip-probes.tsv.
expect_request /ip-global 10.1.0.1 allow ip-global ip-global-service
expect_request /ip-global 10.2.0.1 deny ip-global ip-global-service
expect_request /ip-global 192.0.2.1 deny ip-global ip-global-service
expect_request /ip-zero 0.0.0.0 allow ip-zero ip-service
expect_request /ip-zero 255.255.255.255 allow ip-zero ip-service
expect_request /ip-single 203.0.113.7 allow ip-single ip-service
expect_request /ip-single 203.0.113.8 deny ip-single ip-service
expect_request /ip-combined 198.51.100.7 allow ip-combined ip-service
expect_request /ip-combined 203.0.113.7 deny ip-combined ip-service

for soundcheck_source in '' '-' '10.1.2' '10.1.2.256' '10.1.2.3/32' '010.1.2.3' \
    '10.1.2.3 ' ' 10.1.2.3' '10.1.2.-1' '+10.1.2.3' '::1' '10.1.2.3:80' '10.1.2.3.4'; do
  soundcheck_status=0
  soundcheck_output="$("$soundcheck_oracle" "$soundcheck_ip_fixture" anonymous http GET /ip-global localhost '' "$soundcheck_source" 2>&1)" || soundcheck_status=$?
  [[ "$soundcheck_status" -eq 2 && "$soundcheck_output" == *'invalid probe source IP'* ]] || {
    printf 'Invalid source accepted or misclassified: %s (status %s)\n' "$soundcheck_source" "$soundcheck_status" >&2
    exit 1
  }
  soundcheck_checks=$((soundcheck_checks + 1))
done
printf 'All %s model-oracle source protocol checks passed (no Docker).\n' "$soundcheck_checks"
