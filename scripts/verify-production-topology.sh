#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

failures=0

pass() {
  printf 'PASS: %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

test_public_v1_routes_to_promptshield_not_bifrost() {
  local block
  block="$(awk '
    $0 ~ /^[[:space:]]*location[[:space:]]+\/v1\/[[:space:]]*\{/ { in_block=1; depth=0 }
    in_block {
      print
      opens=gsub(/\{/, "{")
      closes=gsub(/\}/, "}")
      depth += opens - closes
      if (depth <= 0) exit
    }
  ' nginx/nginx.conf)"

  if [[ -z "$block" ]]; then
    fail "test_public_v1_routes_to_promptshield_not_bifrost: nginx/nginx.conf has no location /v1/ block"
    return
  fi

  if ! grep -q 'proxy_pass[[:space:]]\+http://promptshield' <<<"$block"; then
    fail "test_public_v1_routes_to_promptshield_not_bifrost: public /v1/ must proxy to PromptShield"
    return
  fi

  if grep -Eiq 'proxy_pass[[:space:]]+http://[^;]*bifrost|bifrost_ui|bifrost:8081' <<<"$block"; then
    fail "test_public_v1_routes_to_promptshield_not_bifrost: public /v1/ must not proxy directly to Bifrost"
    return
  fi

  pass "test_public_v1_routes_to_promptshield_not_bifrost"
}

test_promptshield_upstream_points_to_bifrost_v1() {
  if ! grep -q 'PROMPTSHIELD_PROVIDER:.*openai-compatible' docker-compose.yml; then
    fail "test_promptshield_upstream_points_to_bifrost_v1: PromptShield must run in openai-compatible provider mode"
    return
  fi

  if ! grep -q 'PROMPTSHIELD_OPENAI_COMPATIBLE_UPSTREAM_URL:.*http://bifrost:8081/v1' docker-compose.yml; then
    fail "test_promptshield_upstream_points_to_bifrost_v1: PromptShield upstream must default to http://bifrost:8081/v1"
    return
  fi

  if ! grep -q 'PROMPTSHIELD_PROVIDER=openai-compatible' .env.example; then
    fail "test_promptshield_upstream_points_to_bifrost_v1: .env.example must preserve openai-compatible mode"
    return
  fi

  if ! grep -q 'PROMPTSHIELD_OPENAI_COMPATIBLE_UPSTREAM_URL=http://bifrost:8081/v1' .env.example; then
    fail "test_promptshield_upstream_points_to_bifrost_v1: .env.example must point PromptShield upstream to Bifrost /v1"
    return
  fi

  pass "test_promptshield_upstream_points_to_bifrost_v1"
}

test_bifrost_is_internal_and_pinned() {
  local block
  block="$(awk '
    $0 ~ /^  bifrost:[[:space:]]*$/ { in_block=1 }
    in_block {
      print
      if (seen && $0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) exit
      seen=1
    }
  ' docker-compose.yml)"

  if grep -q 'maximhq/bifrost:latest' <<<"$block"; then
    fail "test_bifrost_is_internal_and_pinned: Bifrost production image must not use latest"
    return
  fi

  if ! grep -q 'image: maximhq/bifrost@sha256:' <<<"$block"; then
    fail "test_bifrost_is_internal_and_pinned: Bifrost image must be pinned by digest"
    return
  fi

  if grep -Eq '^[[:space:]]*ports:' <<<"$block"; then
    fail "test_bifrost_is_internal_and_pinned: Bifrost must not publish a host port in production compose"
    return
  fi

  if ! grep -Eq '^[[:space:]]*expose:' <<<"$block"; then
    fail "test_bifrost_is_internal_and_pinned: Bifrost should expose 8081 only on the Compose network"
    return
  fi

  pass "test_bifrost_is_internal_and_pinned"
}

test_docs_do_not_document_public_bifrost_inference() {
  local docs
  docs="$(cat README.md .env.example)"

  if grep -Eiq 'curl[^\n]*(8081|/bifrost/[^[:space:]]*v1|bifrost:8081/v1)' <<<"$docs"; then
    fail "test_docs_do_not_document_public_bifrost_inference: docs/env must not show curl examples that call Bifrost /v1 directly"
    return
  fi

  if grep -Eiq 'your-server:8081|public[^\n]*(Bifrost|8081)|(use|call|set|configure)[^\n]*(Bifrost|8081)[^\n]*(public inference|public endpoint)' <<<"$docs"; then
    fail "test_docs_do_not_document_public_bifrost_inference: docs/env must not present Bifrost or :8081 as a public inference endpoint"
    return
  fi

  if grep -Eq '^(OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY)=' .env.example; then
    fail "test_docs_do_not_document_public_bifrost_inference: provider API key examples must not live in .env.example as PromptShield product env"
    return
  fi

  pass "test_docs_do_not_document_public_bifrost_inference"
}

test_secret_bearing_bifrost_runtime_state_is_flagged() {
  local tracked_runtime
  tracked_runtime="$(git ls-files 'bifrost-data/*' 2>/dev/null || true)"

  if [[ -z "$tracked_runtime" ]]; then
    pass "test_secret_bearing_bifrost_runtime_state_is_flagged: no tracked bifrost-data runtime files"
    return
  fi

  warn "test_secret_bearing_bifrost_runtime_state_is_flagged: tracked Bifrost runtime state exists and may contain provider secrets:"
  printf '%s\n' "$tracked_runtime" | sed 's/^/WARN:   path: /'

  if command -v sqlite3 >/dev/null 2>&1 && [[ -f bifrost-data/config.db ]]; then
    local secret_tables
    secret_tables="$(sqlite3 bifrost-data/config.db '.tables' 2>/dev/null \
      | tr ' ' '\n' \
      | grep -E '(key|token|oauth|credential|session)' \
      | sort -u || true)"
    if [[ -n "$secret_tables" ]]; then
      warn "test_secret_bearing_bifrost_runtime_state_is_flagged: secret-related SQLite tables detected in bifrost-data/config.db:"
      printf '%s\n' "$secret_tables" | sed 's/^/WARN:   table: /'
    fi
  fi

  pass "test_secret_bearing_bifrost_runtime_state_is_flagged"
}

test_public_v1_routes_to_promptshield_not_bifrost
test_promptshield_upstream_points_to_bifrost_v1
test_bifrost_is_internal_and_pinned
test_docs_do_not_document_public_bifrost_inference
test_secret_bearing_bifrost_runtime_state_is_flagged

if (( failures > 0 )); then
  printf '\n%d production topology check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nProduction topology checks passed.\n'
