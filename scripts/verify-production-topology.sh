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

test_bifrost_admin_proxy_blocks_inference_subpath() {
  local exact_line prefix_line admin_line exact_block prefix_block
  exact_line="$(awk '$0 ~ /^[[:space:]]*location[[:space:]]+=[[:space:]]+\/bifrost\/v1[[:space:]]*\{/ { print NR; exit }' nginx/nginx.conf)"
  prefix_line="$(awk '$0 ~ /^[[:space:]]*location[[:space:]]+\^~[[:space:]]+\/bifrost\/v1\/[[:space:]]*\{/ { print NR; exit }' nginx/nginx.conf)"
  admin_line="$(awk '$0 ~ /^[[:space:]]*location[[:space:]]+\/bifrost\/[[:space:]]*\{/ { print NR; exit }' nginx/nginx.conf)"

  if [[ -z "$exact_line" ]]; then
    fail "test_bifrost_admin_proxy_blocks_inference_subpath: nginx/nginx.conf must block exact /bifrost/v1 before the admin proxy"
    return
  fi

  if [[ -z "$prefix_line" ]]; then
    fail "test_bifrost_admin_proxy_blocks_inference_subpath: nginx/nginx.conf must block /bifrost/v1/* before the admin proxy"
    return
  fi

  if [[ -z "$admin_line" ]]; then
    fail "test_bifrost_admin_proxy_blocks_inference_subpath: nginx/nginx.conf has no /bifrost/ admin proxy"
    return
  fi

  if (( exact_line >= admin_line || prefix_line >= admin_line )); then
    fail "test_bifrost_admin_proxy_blocks_inference_subpath: /bifrost/v1 blocks must appear before the broad /bifrost/ admin proxy"
    return
  fi

  exact_block="$(awk '
    $0 ~ /^[[:space:]]*location[[:space:]]+=[[:space:]]+\/bifrost\/v1[[:space:]]*\{/ { in_block=1; depth=0 }
    in_block {
      print
      opens=gsub(/\{/, "{")
      closes=gsub(/\}/, "}")
      depth += opens - closes
      if (depth <= 0) exit
    }
  ' nginx/nginx.conf)"
  prefix_block="$(awk '
    $0 ~ /^[[:space:]]*location[[:space:]]+\^~[[:space:]]+\/bifrost\/v1\/[[:space:]]*\{/ { in_block=1; depth=0 }
    in_block {
      print
      opens=gsub(/\{/, "{")
      closes=gsub(/\}/, "}")
      depth += opens - closes
      if (depth <= 0) exit
    }
  ' nginx/nginx.conf)"

  if ! grep -Eq 'return[[:space:]]+(403|404)[[:space:]]*;' <<<"$exact_block"; then
    fail "test_bifrost_admin_proxy_blocks_inference_subpath: exact /bifrost/v1 block must return 403 or 404"
    return
  fi

  if ! grep -Eq 'return[[:space:]]+(403|404)[[:space:]]*;' <<<"$prefix_block"; then
    fail "test_bifrost_admin_proxy_blocks_inference_subpath: /bifrost/v1/* block must return 403 or 404"
    return
  fi

  if grep -Eiq 'proxy_pass|rewrite' <<<"$exact_block$prefix_block"; then
    fail "test_bifrost_admin_proxy_blocks_inference_subpath: /bifrost/v1 blocks must not proxy or rewrite to Bifrost"
    return
  fi

  pass "test_bifrost_admin_proxy_blocks_inference_subpath"
}

test_bifrost_admin_proxy_has_access_control() {
  local admin_block
  admin_block="$(awk '
    $0 ~ /^[[:space:]]*location[[:space:]]+\/bifrost\/[[:space:]]*\{/ { in_block=1; depth=0 }
    in_block {
      print
      opens=gsub(/\{/, "{")
      closes=gsub(/\}/, "}")
      depth += opens - closes
      if (depth <= 0) exit
    }
  ' nginx/nginx.conf)"

  if [[ -z "$admin_block" ]]; then
    fail "test_bifrost_admin_proxy_has_access_control: nginx/nginx.conf has no /bifrost/ admin proxy"
    return
  fi

  if ! grep -Eq 'auth_basic|auth_request|allow[[:space:]]|deny[[:space:]]' <<<"$admin_block"; then
    fail "test_bifrost_admin_proxy_has_access_control: /bifrost/ admin proxy must be protected by explicit auth or allow/deny access control"
    return
  fi

  if ! grep -Eq 'deny[[:space:]]+all[[:space:]]*;' <<<"$admin_block"; then
    fail "test_bifrost_admin_proxy_has_access_control: /bifrost/ admin proxy must deny non-admin networks by default"
    return
  fi

  pass "test_bifrost_admin_proxy_has_access_control"
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

test_promptshield_gateway_is_internal() {
  local block
  block="$(awk '
    $0 ~ /^  promptshield-gateway:[[:space:]]*$/ { in_block=1 }
    in_block {
      print
      if (seen && $0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) exit
      seen=1
    }
  ' docker-compose.yml)"

  if grep -Eq '^[[:space:]]*ports:' <<<"$block"; then
    fail "test_promptshield_gateway_is_internal: PromptShield gateway must not publish a host port in production compose"
    return
  fi

  if ! grep -Eq '^[[:space:]]*expose:' <<<"$block"; then
    fail "test_promptshield_gateway_is_internal: PromptShield gateway should expose 8080 only on the Compose network"
    return
  fi

  pass "test_promptshield_gateway_is_internal"
}

test_non_nginx_components_are_internal() {
  local service port block
  for service in promptshield-engine dashboard web; do
    case "$service" in
      promptshield-engine) port="4321" ;;
      dashboard) port="3000" ;;
      web) port="8000" ;;
    esac

    block="$(awk -v svc="$service" '
      $0 ~ "^  " svc ":[[:space:]]*$" { in_block=1 }
      in_block {
        print
        if (seen && $0 ~ /^  [A-Za-z0-9_-]+:[[:space:]]*$/) exit
        seen=1
      }
    ' docker-compose.yml)"

    if grep -Eq '^[[:space:]]*ports:' <<<"$block"; then
      fail "test_non_nginx_components_are_internal: $service must not publish a host port in production compose"
      return
    fi

    if ! grep -Eq '^[[:space:]]*expose:' <<<"$block" || ! grep -Eq "\"?$port\"?" <<<"$block"; then
      fail "test_non_nginx_components_are_internal: $service should expose $port only on the Compose network"
      return
    fi
  done

  pass "test_non_nginx_components_are_internal"
}

test_docs_do_not_document_public_bifrost_inference() {
  local docs
  docs="$(cat README.md .env.example promptshield-src/README.md promptshield-src/apps/docs/content/docs/*.mdx)"

  if grep -Eiq 'curl[^\n]*(8081|/bifrost/[^[:space:]]*v1|bifrost:8081/v1)' <<<"$docs"; then
    fail "test_docs_do_not_document_public_bifrost_inference: docs/env must not show curl examples that call Bifrost /v1 directly"
    return
  fi

  if grep -Eiq 'your-server:8081|public[^\n]*(Bifrost[^/]|8081)|(use|call|set|configure)[^\n]*(Bifrost|8081)[^\n]*(public inference|public endpoint)' <<<"$docs"; then
    fail "test_docs_do_not_document_public_bifrost_inference: docs/env must not present Bifrost or :8081 as a public inference endpoint"
    return
  fi

  if grep -Eq '^(OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY)=' .env.example; then
    fail "test_docs_do_not_document_public_bifrost_inference: provider API key examples must not live in .env.example as PromptShield product env"
    return
  fi

  if grep -ERn '^(OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY)=' promptshield-src/README.md promptshield-src/apps/docs/content/docs >/dev/null; then
    fail "test_docs_do_not_document_public_bifrost_inference: product docs must not instruct users to store provider API keys in PromptShield"
    return
  fi

  if grep -ERn 'PROMPTSHIELD_PROVIDER=(gemini|openai|anthropic|selfhosted)([^-[:alnum:]_]|$)' promptshield-src/README.md promptshield-src/apps/docs/content/docs >/dev/null; then
    fail "test_docs_do_not_document_public_bifrost_inference: product docs must preserve Bifrost as provider control plane"
    return
  fi

  if grep -ERn 'localhost:8080/v1|:8080/v1|base_url="[^"]*8080/v1|baseUrl": "[^"]*8080/v1' promptshield-src/README.md promptshield-src/apps/docs/content/docs promptshield-src/apps/web/src/routes/_layout.dashboard.tsx >/dev/null; then
    fail "test_docs_do_not_document_public_bifrost_inference: product docs/UI must show public inference through Nginx /v1, not direct component gateway :8080/v1"
    return
  fi

  if grep -ERn 'localhost:8080|Gateway only|\./promptshield-gateway|listening on :8080|Gateway[[:space:]]+\|[[:space:]]+`:8080`' promptshield-src/README.md promptshield-src/apps/docs/content/docs >/dev/null; then
    fail "test_docs_do_not_document_public_bifrost_inference: product docs must not publish standalone/direct PromptShield gateway component surfaces"
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

  fail "test_secret_bearing_bifrost_runtime_state_is_flagged: remove tracked bifrost-data runtime files from git and keep them ignored"
}

test_dashboard_has_bifrost_router_status() {
  if ! grep -q 'BIFROST_URL' promptshield-src/packages/env/src/server.ts; then
    fail "test_dashboard_has_bifrost_router_status: server env must expose BIFROST_URL"
    return
  fi

  if ! grep -q 'bifrostStatus' promptshield-src/packages/api/src/routers/dashboard.ts; then
    fail "test_dashboard_has_bifrost_router_status: dashboard API must expose Bifrost router status"
    return
  fi

  if ! grep -q 'trpc.dashboard.bifrostStatus' promptshield-src/apps/web/src/routes/_layout.dashboard.tsx; then
    fail "test_dashboard_has_bifrost_router_status: dashboard UI must query Bifrost router status"
    return
  fi

  if ! grep -Eiq 'Bifrost|Router' promptshield-src/apps/web/src/routes/_layout.dashboard.tsx; then
    fail "test_dashboard_has_bifrost_router_status: dashboard UI must label the Bifrost/router status"
    return
  fi

  pass "test_dashboard_has_bifrost_router_status"
}

test_bifrost_url_is_configured() {
  if ! grep -q 'BIFROST_URL:.*http://bifrost:8081' docker-compose.yml; then
    fail "test_bifrost_url_is_configured: dashboard compose env must set BIFROST_URL=http://bifrost:8081"
    return
  fi

  if ! grep -q '^BIFROST_URL=http://bifrost:8081' .env.example; then
    fail "test_bifrost_url_is_configured: root .env.example must document BIFROST_URL"
    return
  fi

  if ! grep -q 'BIFROST_URL.*default("http://bifrost:8081")' promptshield-src/packages/env/src/server.ts; then
    fail "test_bifrost_url_is_configured: server env must default BIFROST_URL to http://bifrost:8081"
    return
  fi

  pass "test_bifrost_url_is_configured"
}

test_router_admin_link_is_not_public_inference() {
  local web_sources
  web_sources="$(cat promptshield-src/apps/web/src/routes/_layout.tsx promptshield-src/apps/web/src/routes/_layout.dashboard.tsx promptshield-src/apps/web/src/routes/_layout.gateway.tsx)"

  if ! grep -q 'href="/bifrost/"' <<<"$web_sources"; then
    fail "test_router_admin_link_is_not_public_inference: dashboard/navigation must link to /bifrost/ admin UI"
    return
  fi

  if grep -Eiq 'href="[^"]*/bifrost/[^"]*v1|href="[^"]*8081[^"]*/v1|to="/bifrost/[^"]*v1|Bifrost[^"]*(public inference|inference endpoint)' <<<"$web_sources"; then
    fail "test_router_admin_link_is_not_public_inference: Bifrost admin link/copy must not present public inference"
    return
  fi

  pass "test_router_admin_link_is_not_public_inference"
}

test_legacy_promptshield_provider_route_not_primary_nav() {
  local layout_source
  layout_source="$(cat promptshield-src/apps/web/src/routes/_layout.tsx)"

  if grep -Eq 'to: "/gateway"|to="/gateway"' <<<"$layout_source"; then
    fail "test_legacy_promptshield_provider_route_not_primary_nav: main nav must not expose legacy /gateway provider routing"
    return
  fi

  if ! grep -Eiq 'Bifrost|provider/router control plane|Provider routing is managed in Bifrost' promptshield-src/apps/web/src/routes/_layout.gateway.tsx; then
    fail "test_legacy_promptshield_provider_route_not_primary_nav: legacy /gateway route must explain provider routing belongs to Bifrost"
    return
  fi

  if grep -Eq 'trpc\.gateway\.(addApiKey|clearApiKeys)|<KeyRow|Add route|Custom model routes|Upstream API Keys|Active Providers|API Keys Configured' promptshield-src/apps/web/src/routes/_layout.gateway.tsx; then
    fail "test_legacy_promptshield_provider_route_not_primary_nav: legacy /gateway route must not expose PromptShield provider/model/key editing controls"
    return
  fi

  if grep -Eq 'addApiKey|clearApiKeys|splitKeys\(e\.PROMPTSHIELD_UPSTREAM_API_KEY\)|splitKeys\(e\.GEMINI_API_KEY\)|splitKeys\(e\.OPENAI_API_KEY\)|splitKeys\(e\.ANTHROPIC_API_KEY\)' promptshield-src/packages/api/src/routers/gateway.ts; then
    fail "test_legacy_promptshield_provider_route_not_primary_nav: gateway API must not expose competing provider key mutations"
    return
  fi

  if grep -Eq 'updates\.PROMPTSHIELD_(PROVIDER|PROVIDERS|MODEL_ROUTES|UPSTREAM_API_KEY|GEMINI_UPSTREAM_URL|OPENAI_UPSTREAM_URL|ANTHROPIC_UPSTREAM_URL|SELFHOSTED_UPSTREAM_URL)' promptshield-src/packages/api/src/routers/gateway.ts; then
    fail "test_legacy_promptshield_provider_route_not_primary_nav: gateway API updateConfig must not write provider routing/key ownership fields"
    return
  fi

  local input_schema update_api
  input_schema="$(awk '
    $0 ~ /^const gatewayConfigInputSchema = z\.object\(\{/ { in_block=1 }
    in_block {
      print
      if ($0 ~ /^\}\);$/) exit
    }
  ' promptshield-src/packages/api/src/routers/gateway.ts)"
  update_api="$(awk '
    $0 ~ /^async function updateGatewayConfigViaApi/ { in_block=1; depth=0 }
    in_block {
      print
      opens=gsub(/\{/, "{")
      closes=gsub(/\}/, "}")
      depth += opens - closes
      if (depth <= 0 && NR > 1) exit
    }
  ' promptshield-src/packages/api/src/routers/gateway.ts)"

  if grep -Eq 'providerMode|provider:|providers:|providerUrls|models:|modelRoutes|upstreamUrl' <<<"$input_schema"; then
    fail "test_legacy_promptshield_provider_route_not_primary_nav: gateway update input schema must not accept PromptShield provider/model routing fields"
    return
  fi

  if grep -Eq 'JSON\.stringify\(input\)' <<<"$update_api"; then
    fail "test_legacy_promptshield_provider_route_not_primary_nav: gateway API must send an explicit security config payload, not forward raw mutation input"
    return
  fi

  pass "test_legacy_promptshield_provider_route_not_primary_nav"
}

test_typecheck_covers_dashboard_and_api() {
  if ! grep -q '"check-types": "tsc -p tsconfig.json --noEmit"' promptshield-src/apps/web/package.json; then
    fail "test_typecheck_covers_dashboard_and_api: web package must run TypeScript in check-types"
    return
  fi

  if ! grep -q '"check-types": "tsc -p tsconfig.json --noEmit"' promptshield-src/packages/api/package.json; then
    fail "test_typecheck_covers_dashboard_and_api: @promptshield/api package must run TypeScript in check-types"
    return
  fi

  if ! (cd promptshield-src && bunx turbo check-types --filter=web --filter=@promptshield/api --force); then
    fail "test_typecheck_covers_dashboard_and_api: focused web/API TypeScript check failed"
    return
  fi

  pass "test_typecheck_covers_dashboard_and_api"
}

test_blocked_request_smoke_test_exists() {
  local script="scripts/smoke-blocked-request-no-bifrost-hit.sh"

  if [[ ! -f "$script" ]]; then
    fail "test_blocked_request_smoke_test_exists: missing blocked-request smoke test script"
    return
  fi

  if ! bash -n "$script"; then
    fail "test_blocked_request_smoke_test_exists: smoke test script has shell syntax errors"
    return
  fi

  if ! grep -Eq 'fake-bifrost|UPSTREAM_HITS|blocked request' "$script"; then
    fail "test_blocked_request_smoke_test_exists: smoke test must use a fake Bifrost upstream/counter and a blocked request"
    return
  fi

  if ! bash "$script"; then
    fail "test_blocked_request_smoke_test_exists: blocked-request smoke test failed"
    return
  fi

  pass "test_blocked_request_smoke_test_exists"
}

test_public_v1_routes_to_promptshield_not_bifrost
test_bifrost_admin_proxy_blocks_inference_subpath
test_bifrost_admin_proxy_has_access_control
test_promptshield_upstream_points_to_bifrost_v1
test_bifrost_is_internal_and_pinned
test_promptshield_gateway_is_internal
test_non_nginx_components_are_internal
test_docs_do_not_document_public_bifrost_inference
test_secret_bearing_bifrost_runtime_state_is_flagged
test_dashboard_has_bifrost_router_status
test_bifrost_url_is_configured
test_router_admin_link_is_not_public_inference
test_legacy_promptshield_provider_route_not_primary_nav
test_typecheck_covers_dashboard_and_api
test_blocked_request_smoke_test_exists

if (( failures > 0 )); then
  printf '\n%d production topology check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nProduction topology checks passed.\n'
