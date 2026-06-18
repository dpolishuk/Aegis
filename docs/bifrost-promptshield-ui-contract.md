# Bifrost PromptShield UI Contract

## Purpose

This contract defines the Bifrost-side PromptShield administration surface before implementation. It is source-backed by the current PromptShield dashboard routes in `promptshield-src/apps/web/src/routes`, PromptShield tRPC routers in `promptshield-src/packages/api/src/routers`, current production topology in `docker-compose.yml` and `nginx/nginx.conf`, and upstream Bifrost workspace/server patterns in `/tmp/bifrost-src`.

The integrated product state is:

- Browser users administer PromptShield from Bifrost workspace pages under `/workspace/promptshield/*`.
- Browser JavaScript calls same-origin Bifrost APIs under `/api/promptshield/*` only.
- Bifrost server handlers proxy PromptShield dashboard, gateway, and engine operations over the Compose network using server-side credentials or an internal trust boundary.
- PromptShield provider routing, model routes, fallback order, upstream provider keys, provider secret handling, and key pools remain Bifrost responsibilities and are excluded from PromptShield pages.
- Public inference traffic remains `client -> Nginx -> PromptShield Gateway -> Bifrost -> providers`; direct external `/bifrost/v1/*` inference access stays blocked.

## SRE Refinement Results

The task is a 4-8 hour contract task with a single deliverable, so it is correctly scoped. The source-backed contract below strengthens the implementation plan across the eight review categories:

- Granularity: this task writes only the contract and does not build the UI or proxy.
- Implementability: every route and endpoint includes concrete paths, payloads, auth, timeout, redaction, and upstream mapping.
- Success criteria: verification is command-driven and endpoint tests are measurable.
- Dependencies: implementation depends on this contract; the epic remains open.
- Safety standards: the contract rejects iframes, direct browser calls to PromptShield, browser-readable service credentials, and duplicated provider routing controls.
- Edge cases: missing credentials, forbidden mutation, invalid payloads, upstream timeout, upstream 401/403, upstream 404, service unavailable, empty audit results, and no revision support are covered.
- Red flags: there are no vague implementation slots in this document.
- Test meaningfulness: tests below exercise auth, redaction, proxy behavior, policy save errors, audit scoping, and topology, not just file existence.

## Source Inventory

### PromptShield UI Routes

| Current route | Source file | Current behavior | Bifrost classification | Bifrost route |
| --- | --- | --- | --- | --- |
| `/` | `promptshield-src/apps/web/src/routes/index.tsx` | Redirects authenticated users into the dashboard shell. | Migrate as default entry redirect. | `/workspace/promptshield` redirects to `/workspace/promptshield/overview`. |
| `/login` | `promptshield-src/apps/web/src/routes/login.tsx` | PromptShield Better Auth login page. | Exclude because Bifrost owns browser auth. | Use existing Bifrost login/session flow. |
| authenticated layout | `promptshield-src/apps/web/src/routes/_layout.tsx` | PromptShield-only shell, sidebar, auth redirect, and external Bifrost link. | Exclude because Bifrost workspace shell owns layout and sidebar. | Add a PromptShield group to Bifrost `ui/components/sidebar.tsx`. |
| `/dashboard` | `_layout.dashboard.tsx` | Overview metrics, recent blocked requests, entity breakdown, gateway health, engine health, Bifrost status, and links to policy/audit/Bifrost. | Migrate. | `/workspace/promptshield/overview`. |
| `/policy` | `_layout.policy.tsx` | Policy editor for global action, entity actions, raw YAML, current policy source, current policy file or gateway policy target, and save. | Migrate. | `/workspace/promptshield/policy`. |
| `/audit` | `_layout.audit.tsx` | Audit event list, action/key/entity/date filters, pagination, severity display, and JSON export of loaded results. | Migrate. | `/workspace/promptshield/audit`. |
| `/keys` | `_layout.keys.tsx` | Placeholder page for PromptShield gateway API keys, while the `keys` router already supports list/create/revoke/assign-policy. | Migrate because API-key parity is in scope. | `/workspace/promptshield/keys`. |
| `/gateway` | `_layout.gateway.tsx` | Gateway security mode, engine URL, gateway health, engine health, port, chat route, policy path, and Bifrost router callout. Provider routing controls are already absent from the current primary nav. | Migrate only security gateway controls. Exclude provider routing and provider secret controls. | `/workspace/promptshield/gateway`. |
| `/engine` | `_layout.engine.tsx` | Engine health, detection tester, mask configuration, and save mask settings. The current tester posts to `/internal/engine/detect`. | Migrate, replacing direct internal browser call with Bifrost `/api/promptshield/engine/detect`. | `/workspace/promptshield/engine`. |
| `/config` | `_layout.config.tsx` | Gateway service URL, policy path, engine service URL, health checks, and reset overrides. | Migrate into PromptShield settings/config. | `/workspace/promptshield/settings`. |
| `/settings` | `_layout.settings.tsx` | PromptShield user email, user id, and sign out. | Exclude because Bifrost owns user identity and sign out. | Existing Bifrost account/session UI. |

### PromptShield API Router Methods

| Current router method | Source file | Current input | Current output | Contract classification |
| --- | --- | --- | --- | --- |
| `healthCheck` | `routers/index.ts` | none | `"OK"` | Replace with Bifrost proxy health under `/api/promptshield/status`; do not expose PromptShield dashboard health as a browser target. |
| `dashboard.stats` | `routers/dashboard.ts` | `{ dateFrom?: string, dateTo?: string }` | counts for total, blocked, allowed, masked, warned, key coverage, all-time total | Migrate into overview endpoint. Preserve user scoping and config-admin unkeyed event visibility. |
| `dashboard.recentBlocks` | `routers/dashboard.ts` | `{ dateFrom?: string, dateTo?: string }` | latest blocked audit events, max 10 | Migrate into overview endpoint. |
| `dashboard.entityBreakdown` | `routers/dashboard.ts` | `{ dateFrom?: string, dateTo?: string }` | top entity counts, max 8 | Migrate into overview endpoint. |
| `dashboard.engineStatus` | `routers/dashboard.ts` | none | `{ online, latencyMs, url }` | Migrate. Return redacted internal URL metadata. |
| `dashboard.gatewayStatus` | `routers/dashboard.ts` | none | `{ online, latencyMs, url }` | Migrate. Return redacted internal URL metadata. |
| `dashboard.bifrostStatus` | `routers/dashboard.ts` | none | `{ online, latencyMs, url }` | Replace with local Bifrost status, not a PromptShield upstream call. |
| `audit.list` | `routers/audit.ts` | `{ page, action, keyId?, entityType?, dateFrom?, dateTo? }` | 50 audit events for the page | Migrate. Preserve 7-day retention and config-admin unkeyed event visibility. |
| `audit.trend` | `routers/audit.ts` | none | 14-day aggregate rows | Migrate. Preserve owned-key scoping. |
| `keys.list` | `routers/keys.ts` | none | key metadata without raw key | Migrate. |
| `keys.create` | `routers/keys.ts` | `{ name: string, policyId?: string }` | created key plus one-time `rawKey` | Migrate. Raw key may be returned once to the authenticated operator and must not be logged or stored in browser storage. |
| `keys.revoke` | `routers/keys.ts` | `{ id: string }` | no body | Migrate. |
| `keys.assignPolicy` | `routers/keys.ts` | `{ id: string, policyId: string \| null }` | no body | Migrate. |
| `policies.sourceInfo` | `routers/policies.ts` | none | source, gateway URL, gateway policy endpoint, token presence | Migrate with redacted URLs and boolean token state only. |
| `policies.list` | `routers/policies.ts` | none | user-owned policies | Migrate. |
| `policies.get` | `routers/policies.ts` | `{ id: string }` | policy or null | Migrate. |
| `policies.create` | `routers/policies.ts` | `{ name: string, content: string, isDefault: boolean }` | created policy | Migrate. Requires config-admin semantics. |
| `policies.update` | `routers/policies.ts` | `{ id: string, name?: string, content?: string }` | updated policy | Migrate. Requires config-admin semantics. |
| `policies.syncFromFile` | `routers/policies.ts` | none | default policy or null | Migrate. Requires config-admin semantics. |
| `policies.fileMeta` | `routers/policies.ts` | none | source, target path, exists, size, modified time | Migrate with target redaction for service URLs and server paths. |
| `policies.checkFilePath` | `routers/policies.ts` | `{ path: string }` | file metadata | Migrate only for non-`gateway_api` environments. Requires config-admin semantics. |
| `policies.saveFilePath` | `routers/policies.ts` | `{ path: string }` | `{ saved: true, path }` | Migrate only for non-`gateway_api` environments. Requires config-admin semantics. |
| `policies.getCurrentFile` | `routers/policies.ts` | none | `{ content, source, target }` | Migrate. |
| `policies.saveToFile` | `routers/policies.ts` | `{ content: string }` | `{ success: true }` | Migrate. Must support production `gateway_api`. Requires config-admin semantics. |
| `gateway.configSourceInfo` | `routers/gateway.ts` | none | source, gateway URL, config endpoint, token presence | Migrate with redacted URLs and boolean token state only. |
| `gateway.health` | `routers/gateway.ts` | none | `{ online, latencyMs, url }` | Migrate. |
| `gateway.engineHealth` | `routers/gateway.ts` | none | `{ online, latencyMs, url, data }` | Migrate. |
| `gateway.getUrls` | `routers/gateway.ts` | none | gateway/engine URL overrides and defaults | Migrate with server-side redaction. |
| `gateway.saveGatewayUrl` | `routers/gateway.ts` | `{ url: string }` | `{ saved: true, url }` | Migrate. Requires config-admin semantics and SSRF-safe URL validation. |
| `gateway.saveEngineUrl` | `routers/gateway.ts` | `{ url: string }` | `{ saved: true, url }` | Migrate. Requires config-admin semantics and SSRF-safe URL validation. |
| `gateway.resetGatewayUrl` | `routers/gateway.ts` | none | `{ reset: true, url }` | Migrate. Requires config-admin semantics. |
| `gateway.resetEngineUrl` | `routers/gateway.ts` | none | `{ reset: true, url }` | Migrate. Requires config-admin semantics. |
| `gateway.checkUrl` | `routers/gateway.ts` | `{ url: string, healthPath?: string }` | `{ online, latencyMs }` | Migrate. Requires config-admin semantics and SSRF-safe URL validation. |
| `gateway.getConfig` | `routers/gateway.ts` | none | security config plus read-only provider/model/key-count metadata | Migrate only security fields. Provider routing, model routes, upstream provider keys, provider secret state, fallback order, and key pools are Bifrost-owned exclusions. |
| `gateway.updateConfig` | `routers/gateway.ts` | `{ mode, engineUrl, port?, chatRoute?, policyPath? }` | `{ success: true }` | Migrate. Requires config-admin semantics. Must not accept provider routing, model routes, upstream provider keys, provider secrets, fallback order, or key pools. |
| `gateway.getEngineConfig` | `routers/gateway.ts` | none | `{ maskConfig: Record<string, boolean> \| null }` | Migrate. |
| `gateway.updateEngineConfig` | `routers/gateway.ts` | `{ maskConfig: Record<string, boolean> }` | `{ success: true }` | Migrate. Requires config-admin semantics. |
| `/internal/engine/detect` | dashboard internal route consumed by `_layout.engine.tsx` | `{ text: string }` | `{ entities?: Detection[] }` | Migrate to Bifrost proxy endpoint. Browser must not call `/internal/*`. |

## Bifrost UI Contract

### Sidebar Grouping

Add a Bifrost sidebar group in `ui/components/sidebar.tsx` named `PromptShield`. It should sit after `Guardrails` and before lower-level cluster/config sections because it is an inference governance and security control plane.

| Sidebar item | Bifrost route | Page name | Access gate | Notes |
| --- | --- | --- | --- | --- |
| PromptShield | `/workspace/promptshield` | PromptShield | Any Bifrost admin/operator who can access workspace pages. Redirects to overview. | Group parent only. |
| Overview | `/workspace/promptshield/overview` | PromptShield Overview | Read access to PromptShield admin. | Replaces `/dashboard`. |
| Policy | `/workspace/promptshield/policy` | Security Policy | Read access for view; mutation access for save/sync/path operations. | Replaces `/policy`. |
| Audit | `/workspace/promptshield/audit` | Audit Events | Read access to PromptShield audit. | Replaces `/audit`. |
| API Keys | `/workspace/promptshield/keys` | Gateway API Keys | Read access for list; mutation access for create/revoke/assign. | Replaces `/keys`; these are PromptShield gateway API keys, not upstream provider keys. |
| Gateway | `/workspace/promptshield/gateway` | Gateway Security | Read access for health/config; mutation access for mode/engine/policy path. | Replaces security portions of `/gateway`. |
| Engine | `/workspace/promptshield/engine` | Detection Engine | Read access for health/config/test; mutation access for mask config. | Replaces `/engine`. |
| Settings | `/workspace/promptshield/settings` | PromptShield Settings | Read access for status; mutation access for service URL overrides and policy path. | Replaces `/config`. |

### Bifrost UI Implementation Shape

- Add app routes under `ui/app/workspace/promptshield/*` using existing Bifrost workspace route conventions: `layout.tsx`, `page.tsx`, and `views/` fragments when a page is substantial.
- Add `ui/lib/store/apis/promptshieldApi.ts` using `baseApi.injectEndpoints`. `baseApi` already calls same-origin `/api` in production and includes Bifrost dashboard auth with `credentials: "include"`.
- Use existing Bifrost components and icons from the current component system. Do not preserve PromptShield-only branding, terminal-style shell, or its Better Auth user menu.
- Do not add Compose hostnames to browser code. Pages call only relative RTK Query endpoints such as `promptshieldApi.endpoints.getPromptShieldOverview`.
- Keep polling bounded: overview service cards may poll every 20 seconds; engine page may poll health every 15 seconds; audit and key pages refresh on user action or after mutations.

## Bifrost API Contract

### Common Response and Error Shape

All endpoints use Bifrost's JSON error shape:

```json
{
  "error": {
    "message": "human readable message",
    "code": "PROMPTSHIELD_UPSTREAM_TIMEOUT"
  }
}
```

Common statuses:

| Status | Meaning |
| --- | --- |
| `401` | No valid Bifrost dashboard session or bearer token. |
| `403` | Bifrost session exists but lacks mutation/config-admin mapping. |
| `400` | Invalid request payload, unsafe URL/path, missing required token for an enabled upstream mode, or known upstream admin endpoint mismatch. |
| `404` | Unknown Bifrost proxy endpoint or entity not found. Upstream PromptShield admin endpoint 404 is returned as `400` with a configuration-mismatch message. |
| `502` | Upstream returned invalid JSON or a semantically invalid payload. |
| `503` | Required PromptShield service URL is absent or the service is unavailable. |
| `504` | Upstream request timed out. |

### Endpoint Matrix

| Bifrost endpoint | Method | Request shape | Response shape | Upstream touched | Auth requirement | Timeout | Redaction behavior |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `/api/promptshield/status` | `GET` | none | `{ dashboard: ServiceStatus, gateway: ServiceStatus, engine: ServiceStatus, bifrost: ServiceStatus, config: ConfigStatus }` | Dashboard health, gateway `/health`, engine `/health`, local Bifrost health | Bifrost admin/session read auth | 3s per service | Internal URLs returned as `{ configured: true, hostLabel }`; no tokens, DB URL, or cookies. |
| `/api/promptshield/overview` | `GET` | query `{ dateFrom?: string, dateTo?: string }` | `{ stats, recentBlocks, entityBreakdown, services }` | `dashboard.stats`, `dashboard.recentBlocks`, `dashboard.entityBreakdown`, gateway/engine/local health | Read auth | 5s dashboard aggregate, 3s health | Audit event payloads redact raw prompt/response fields if upstream includes them; service URLs redacted. |
| `/api/promptshield/audit` | `GET` | query `{ page?: number, action?: "all" \| "allowed" \| "blocked" \| "masked" \| "warned", keyId?: string, entityType?: string, dateFrom?: string, dateTo?: string }` | `{ events: AuditEvent[], page, pageSize: 50, hasMore, retentionDays: 7, scope: "owned" \| "admin_with_unkeyed" }` | `audit.list` | Read auth | 5s | Redact raw prompt text, raw completion text, request headers, authorization values, and provider keys; key id/prefix may remain. |
| `/api/promptshield/audit/trend` | `GET` | none | `{ rows: AuditTrendRow[], windowDays: 14 }` | `audit.trend` | Read auth | 5s | Same audit redaction. |
| `/api/promptshield/audit/export` | `GET` | same filters as audit list plus `{ format?: "json" }` | JSON file stream or `{ events }` | `audit.list` paginated server-side | Read auth | 15s total, 5s per upstream page | Same audit redaction; no service credentials in export metadata. |
| `/api/promptshield/policies` | `GET` | none | `{ policies: PolicySummary[] }` | `policies.list` | Read auth | 5s | Policy content omitted from summaries unless needed by UI. |
| `/api/promptshield/policies/{id}` | `GET` | path `{ id }` | `{ policy: Policy \| null }` | `policies.get` | Read auth | 5s | Return policy content because this page edits policy. No secrets embedded by server. |
| `/api/promptshield/policies` | `POST` | `{ name: string, content: string, isDefault?: boolean }` | `{ policy: Policy }` | `policies.create` | Mutating auth plus config-admin mapping | 7s, including gateway policy write if default | Logs include policy id/name and actor only; policy content is not logged. |
| `/api/promptshield/policies/{id}` | `PATCH` | `{ name?: string, content?: string }` | `{ policy: Policy \| null }` | `policies.update` | Mutating auth plus config-admin mapping | 7s | Do not log policy content. |
| `/api/promptshield/policies/sync` | `POST` | none | `{ policy: Policy \| null }` | `policies.syncFromFile` | Mutating auth plus config-admin mapping | 7s | Target path/URL redacted in response except host label and source type. |
| `/api/promptshield/policy-source` | `GET` | none | `{ source: "local_file" \| "gateway_api", targetLabel, hasGatewayAdminToken: boolean }` | `policies.sourceInfo` | Read auth | 4s | Do not return `GATEWAY_ADMIN_TOKEN`, full internal gateway URL, dashboard cookies, or server filesystem paths unless explicitly needed by a local admin-only view. |
| `/api/promptshield/policy-file` | `GET` | none | `{ content: string \| null, source, targetLabel }` | `policies.getCurrentFile` | Read auth | 4s gateway, 5s dashboard | Return content; redact full target path/URL to host label unless a local-file admin path view is enabled. |
| `/api/promptshield/policy-file` | `PUT` | `{ content: string }` | `{ success: true }` | `policies.saveToFile`, which writes local file or gateway `/admin/policy` | Mutating auth plus config-admin mapping | 5s gateway policy write, 7s total | Do not log content. Gateway admin token stays server-side. |
| `/api/promptshield/policy-file/meta` | `GET` | none | `{ source, exists, sizeBytes, modifiedAt, targetLabel }` | `policies.fileMeta` | Read auth | 4s | Redact full target path/URL. |
| `/api/promptshield/policy-path/check` | `POST` | `{ path: string }` | `{ exists, sizeBytes, modifiedAt }` or `400` for `gateway_api` | `policies.checkFilePath` | Mutating auth plus config-admin mapping | 4s | Do not log raw path when rejected; log normalized safe path only at debug. |
| `/api/promptshield/policy-path` | `PUT` | `{ path: string }` | `{ saved: true, pathLabel }` or `400` for `gateway_api` | `policies.saveFilePath` | Mutating auth plus config-admin mapping | 4s | Return redacted path label. |
| `/api/promptshield/keys` | `GET` | none | `{ keys: GatewayApiKey[] }` | `keys.list` | Read auth | 5s | Return id, name, keyPrefix, policyId, createdAt, revokedAt, lastUsedAt. Never return key hash. |
| `/api/promptshield/keys` | `POST` | `{ name: string, policyId?: string }` | `{ key: GatewayApiKey, rawKey: string }` | `keys.create` | Mutating auth | 5s | Raw key returned once only; never log raw key, never write to localStorage/sessionStorage. |
| `/api/promptshield/keys/{id}` | `DELETE` | path `{ id }` | `{ revoked: true }` | `keys.revoke` | Mutating auth | 5s | Log id and actor only. |
| `/api/promptshield/keys/{id}/policy` | `PUT` | `{ policyId: string \| null }` | `{ assigned: true }` | `keys.assignPolicy` | Mutating auth | 5s | Log id, policyId, and actor only. |
| `/api/promptshield/gateway/health` | `GET` | none | `ServiceStatus` | `gateway.health` or direct gateway `/health` | Read auth | 3s | Redact internal URL to host label. |
| `/api/promptshield/gateway/config-source` | `GET` | none | `{ source: "local_env" \| "gateway_api", hasGatewayAdminToken: boolean, targetLabel }` | `gateway.configSourceInfo` | Read auth | 4s | Do not return token or full admin endpoint. |
| `/api/promptshield/gateway/config` | `GET` | none | `{ mode, engineUrlLabel, port, chatRoute, policyPathLabel, readOnlyProviderSummary }` | `gateway.getConfig` | Read auth | 5s | Do not return upstream provider keys, provider secret values, full internal engine URL, model route edit data, fallback order, or key pool values. |
| `/api/promptshield/gateway/config` | `PUT` | `{ mode: "gateway" \| "security", engineUrl: string, port?: string, chatRoute?: string, policyPath?: string }` | `{ success: true }` | `gateway.updateConfig`, gateway `/admin/config` when source is `gateway_api` | Mutating auth plus config-admin mapping | 5s gateway write, 7s total | Accept security fields only. Reject provider routing, model routes, upstream provider keys, provider secret fields, fallback order, and key pool fields with `400`. |
| `/api/promptshield/gateway/urls` | `GET` | none | `{ gatewayUrlLabel, engineUrlLabel, gatewayDefaultLabel, engineDefaultLabel }` | `gateway.getUrls` | Read auth | 4s | Redact full URLs to host labels unless edit form is mutation-authorized and explicitly opens the value. |
| `/api/promptshield/gateway/url` | `PUT` | `{ url: string }` | `{ saved: true, urlLabel }` | `gateway.saveGatewayUrl` | Mutating auth plus config-admin mapping | 4s | Validate URL server-side; log host only. |
| `/api/promptshield/gateway/url` | `DELETE` | none | `{ reset: true, urlLabel }` | `gateway.resetGatewayUrl` | Mutating auth plus config-admin mapping | 4s | Redact full URL. |
| `/api/promptshield/engine/url` | `PUT` | `{ url: string }` | `{ saved: true, urlLabel }` | `gateway.saveEngineUrl` | Mutating auth plus config-admin mapping | 4s | Validate URL server-side; log host only. |
| `/api/promptshield/engine/url` | `DELETE` | none | `{ reset: true, urlLabel }` | `gateway.resetEngineUrl` | Mutating auth plus config-admin mapping | 4s | Redact full URL. |
| `/api/promptshield/url-check` | `POST` | `{ url: string, healthPath?: string }` | `{ online: boolean, latencyMs: number \| null }` | `gateway.checkUrl` | Mutating auth plus config-admin mapping | 4s | Validate URL server-side; response omits URL. |
| `/api/promptshield/engine/health` | `GET` | none | `ServiceStatus & { data?: unknown }` | `gateway.engineHealth` or direct engine `/health` | Read auth | 3s | Redact internal URL and any key-bearing fields in health JSON. |
| `/api/promptshield/engine/config` | `GET` | none | `{ maskConfig: Record<string, boolean> \| null }` | `gateway.getEngineConfig`, engine `/config` | Read auth | 3s | No tokens returned. |
| `/api/promptshield/engine/config` | `PUT` | `{ maskConfig: Record<string, boolean> }` | `{ success: true }` | `gateway.updateEngineConfig`, engine `/config` | Mutating auth plus config-admin mapping | 5s | Validate booleans only; no token in response. |
| `/api/promptshield/engine/detect` | `POST` | `{ text: string }` | `{ entities: Detection[], elapsedMs }` | Engine detect service currently reached through dashboard `/internal/engine/detect` | Read auth; rate-limited | 10s | Do not log input text or detected snippets. Enforce max text length of 10000 UTF-8 bytes. |

### ServiceStatus Shape

```ts
type ServiceStatus = {
  online: boolean;
  latencyMs: number | null;
  target: {
    configured: boolean;
    hostLabel: string | null;
  };
  checkedAt: string;
};
```

### Selected Domain Shapes

```ts
type AuditEvent = {
  id: string;
  action: "allowed" | "blocked" | "masked" | "warned";
  keyId: string | null;
  entityTypes: string[];
  timestamp: string;
  reason?: string | null;
  metadata?: Record<string, unknown>;
};

type GatewayApiKey = {
  id: string;
  name: string;
  keyPrefix: string;
  policyId: string | null;
  createdAt: string;
  revokedAt: string | null;
  lastUsedAt: string | null;
};

type ConfigStatus = {
  policySource: "local_file" | "gateway_api";
  gatewayConfigSource: "local_env" | "gateway_api";
  hasGatewayAdminToken: boolean;
  hasEngineApiKey: boolean;
  dashboardReachable: boolean;
};
```

## Server-Side Credential Handling

### Environment and Runtime Sources

Bifrost must read PromptShield service configuration from server-side Bifrost environment variables and, if Bifrost already has a secure config store for server secrets, from that store. The browser must never receive these values directly.

| Value | Required for | Proposed Bifrost env/config key | Browser exposure |
| --- | --- | --- | --- |
| PromptShield dashboard API base URL | DB-backed tRPC router parity: overview, audit, keys, policies | `PROMPTSHIELD_DASHBOARD_URL`, default `http://dashboard:3000` in Compose | Never; return host label only. |
| PromptShield dashboard service credential or internal trust marker | Server-to-server dashboard router access | `PROMPTSHIELD_ADMIN_TOKEN` or mTLS/internal network trust | Never. |
| PromptShield database URL | Only if a future Bifrost handler bypasses dashboard APIs, which this contract does not prefer | No browser-facing key; reuse dashboard APIs first | Never. |
| PromptShield gateway base URL | Gateway health/config/policy fallback | `PROMPTSHIELD_GATEWAY_URL`, default `http://promptshield-gateway:8080` | Never; return host label only. |
| PromptShield gateway admin token | Gateway `/admin/policy` and `/admin/config` in `gateway_api` mode | `PROMPTSHIELD_GATEWAY_ADMIN_TOKEN` | Never. |
| PromptShield engine base URL | Engine health/config/detect | `PROMPTSHIELD_ENGINE_URL`, default `http://promptshield-engine:4321` | Never; return host label only. |
| PromptShield engine API key | Engine calls when auth is enabled | `PROMPTSHIELD_ENGINE_API_KEY` | Never. |
| PromptShield config-admin identity map | Mutating policy/gateway/engine operations | `PROMPTSHIELD_CONFIG_ADMIN_EMAILS` or Bifrost RBAC role mapping | Return only booleans such as `{ canMutate: true }`. |

### Redaction Rules

- Logs must redact `PROMPTSHIELD_ADMIN_TOKEN`, `PROMPTSHIELD_GATEWAY_ADMIN_TOKEN`, `PROMPTSHIELD_ENGINE_API_KEY`, `DATABASE_URL`, Better Auth cookies, Bifrost dashboard bearer tokens, raw PromptShield gateway API keys, upstream provider keys, and provider secret fields.
- Responses must not include service tokens, dashboard cookies, database URLs, raw upstream URLs containing credentials, upstream provider key values, or engine API keys.
- Policy content and detection input text are operationally sensitive. They may be returned only on policy/detection endpoints that need them, and must not be logged.
- `POST /api/promptshield/keys` is the only endpoint allowed to return a raw PromptShield gateway API key. It returns the raw key once in the response body, with `Cache-Control: no-store`.
- All `/api/promptshield/*` responses should set `Cache-Control: no-store` because they expose admin state.

### Missing Credential Failures

| Missing value | Affected endpoints | Status | Message requirement |
| --- | --- | --- | --- |
| `PROMPTSHIELD_DASHBOARD_URL` | dashboard-router-backed endpoints | `503` | "PromptShield dashboard URL is not configured". |
| Dashboard service credential when external service auth is enabled | dashboard-router-backed endpoints | `503` for reads, `400` for mutation preflight | "PromptShield dashboard service credential is not configured". |
| `PROMPTSHIELD_GATEWAY_ADMIN_TOKEN` in `gateway_api` source | policy save/read via gateway admin, gateway config read/write | `400` | "Gateway admin token is required for gateway_api source". |
| Gateway admin endpoint is HTTP and not loopback | policy/gateway admin write/read | `400` | "Gateway admin endpoint must use HTTPS unless targeting localhost/loopback". |
| `PROMPTSHIELD_ENGINE_URL` | engine health/config/detect | `503` | "PromptShield engine URL is not configured". |
| `PROMPTSHIELD_ENGINE_API_KEY` when engine requires auth | engine config/detect | `503` for reads, `400` for mutation preflight | "PromptShield engine API key is not configured". |

## Auth and Config-Admin Mapping

### Read Operations

Read endpoints require the same Bifrost dashboard/session authorization used for existing Bifrost `/api` admin routes. Implementation must register the PromptShield handler in `transports/bifrost-http/server/server.go` with the same `apiMiddlewares` chain used by existing handlers such as config, providers, plugins, and session routes.

Read access preserves PromptShield user/admin scoping:

- If Bifrost can map the session to a PromptShield user id or email, audit and key queries use that identity.
- If the user has config-admin mapping, audit overview and audit list include unkeyed gateway events, matching current PromptShield development/config-admin behavior.
- If no one-to-one user mapping exists yet, the first implementation may use a dedicated PromptShield service admin for reads, but the response must report `scope: "admin_with_unkeyed"` and the implementation task must add an audit note for the Bifrost actor.

### Mutating Operations

Mutations include policy create/update/sync/save/path writes, gateway URL/config writes, engine URL/config writes, key create/revoke/assign, and URL health checks that allow arbitrary target input.

Required checks:

1. Bifrost dashboard/session authorization succeeds.
2. Bifrost grants write access. If Bifrost RBAC has distinct permissions, use a PromptShield write permission. If not, require Bifrost dashboard admin access for all mutations.
3. PromptShield config-admin semantics are preserved for policy, gateway, and engine mutations:
   - If PromptShield `CONFIG_ADMIN_EMAILS` is still authoritative, Bifrost must map the Bifrost actor email to that allowlist or use a service account email that is present in the allowlist.
   - If a service account performs the upstream call, the Bifrost actor id/email must be recorded in Bifrost logs and passed upstream in a non-secret audit header such as `X-Bifrost-Actor`.
   - When no config admin is configured, return `403` with "No PromptShield config admins configured".
   - When the Bifrost actor is not allowed, return `403` with "Only PromptShield config admins can change gateway, engine, or policy settings".
4. Mutations must not forward browser PromptShield cookies. Bifrost constructs upstream credentials from server-side config.

## Failure Handling Details

| Failure | Required Bifrost behavior | Test that catches it |
| --- | --- | --- |
| Unauthenticated browser request | Return `401`; no upstream request is made. | Handler test with no session and fake upstream call counter remains zero. |
| Authenticated read-only operator attempts mutation | Return `403`; no upstream request is made. | Handler test with read-only principal. |
| Missing gateway admin token in `gateway_api` mode | Return `400` with actionable message; no token value appears. | Policy save handler test with source `gateway_api` and empty token. |
| Non-HTTPS non-loopback gateway admin endpoint | Return `400`; reject before upstream call. | Unit test for URL validation with `http://promptshield-gateway:8080/admin/policy`. |
| Upstream timeout | Return `504`; include timeout class, not raw exception. | Fake upstream sleeps longer than handler timeout. |
| Upstream 401/403 | Return `403`; redact upstream response body if it contains credentials. | Fake gateway returns 401 with token-like body. |
| Upstream 404 for `/admin/policy` or `/admin/config` | Return `400` configuration mismatch, not generic 404. | Fake gateway returns 404. |
| Upstream invalid JSON | Return `502`. | Fake gateway config returns malformed JSON. |
| Policy save rejected by gateway | Return `400` with first 120 chars of sanitized upstream error. | Fake gateway returns 400 invalid payload. |
| Audit query has no rows | Return `{ events: [], hasMore: false }` with retention and scope metadata. | Handler test against empty DB/upstream response. |
| Browser token exposure | No service token in JSON, logs, localStorage, sessionStorage, or built JS bundle. | UI test and static scan for service env names in `ui/.next` or built assets. |

## Policy and Gateway Semantics

Policy writes must preserve the current PromptShield behavior:

- `POLICY_SOURCE=local_file`: read/write the configured policy path, after allowed-directory validation.
- `POLICY_SOURCE=gateway_api`: read/write gateway `/admin/policy` using the gateway admin token.
- `gateway_api` write uses JSON `{ content }` first and falls back to plain text only if the upstream returns a compatible client error.
- Missing token, non-HTTPS non-loopback target, 401/403, 404, invalid payload, timeout, and service unavailable each produce distinct operator-facing errors.

Gateway config writes must preserve the current PromptShield security-only schema:

```ts
type GatewayConfigUpdate = {
  mode: "gateway" | "security";
  engineUrl: string;
  port?: string;
  chatRoute?: string;
  policyPath?: string;
};
```

The Bifrost proxy must reject any request body containing provider routing fields, model routes, fallback order, upstream provider key values, provider secret fields, key pools, `providerUrls`, `models`, or raw `keyCounts`. Those are Bifrost-owned exclusions.

Current PromptShield APIs have no revision, ETag, or compare-and-swap behavior for policy or gateway writes. Until such support exists, the Bifrost UI must show last-write-wins behavior clearly after save by refetching current content/config and surfacing a "saved at" timestamp. Implementation tasks should add optimistic concurrency only when PromptShield exposes a revision source.

## Migration Strategy

### Target Build

Move from the digest-pinned upstream image:

```yaml
bifrost:
  image: maximhq/bifrost@sha256:240634280b374bf0fae11e888f5f9238bf30a2c323a75d905059902fea2c7a5d
```

to a project-owned Bifrost build:

```yaml
bifrost:
  build:
    context: ./bifrost-src
    dockerfile: Dockerfile
  image: aegis-bifrost:${AEGIS_BIFROST_TAG:-promptshield-admin}
  environment:
    APP_PORT: "8081"
    APP_HOST: "0.0.0.0"
    LOG_LEVEL: ${BIFROST_LOG_LEVEL:-info}
    PROMPTSHIELD_DASHBOARD_URL: http://dashboard:3000
    PROMPTSHIELD_GATEWAY_URL: http://promptshield-gateway:8080
    PROMPTSHIELD_ENGINE_URL: http://promptshield-engine:4321
    PROMPTSHIELD_ADMIN_TOKEN: ${PROMPTSHIELD_ADMIN_TOKEN}
    PROMPTSHIELD_GATEWAY_ADMIN_TOKEN: ${GATEWAY_ADMIN_TOKEN}
    PROMPTSHIELD_ENGINE_API_KEY: ${PROMPTSHIELD_ENGINE_API_KEY}
```

Compose changes:

- Keep Bifrost internal with `expose: ["8081"]` and no host `ports`.
- Keep PromptShield gateway upstream default `http://bifrost:8081/v1`.
- Add Bifrost `depends_on` entries for dashboard, promptshield-gateway, and promptshield-engine if the proxy handler performs startup validation. Otherwise handlers can fail per request with `503` while services boot.
- Keep Nginx blocking `location = /bifrost/v1` and `location ^~ /bifrost/v1/` before `location /bifrost/`.
- Route `/bifrost/` to Bifrost exactly as today; after integration, the root PromptShield web app can be removed from primary admin navigation in a later task.

### Rollback Path

Rollback must be a one-line Compose image switch plus restart:

1. Stop the project-owned Bifrost container.
2. Restore `image: maximhq/bifrost@sha256:240634280b374bf0fae11e888f5f9238bf30a2c323a75d905059902fea2c7a5d`.
3. Remove PromptShield-specific Bifrost env vars or leave them unused.
4. Restart Bifrost and Nginx.
5. Confirm `/bifrost/` existing provider/model/routing workflows still load and public `/v1/*` still routes through PromptShield.

The rollback does not change PromptShield dashboard, gateway, engine, Postgres, policy, or Bifrost data volumes.

## Test Plan

### Unit Tests

| Test | Location | Bug caught |
| --- | --- | --- |
| `TestPromptShieldRedactSecretsFromResponseAndLogs` | `transports/bifrost-http/handlers/promptshield_test.go` | Accidental exposure of admin token, engine API key, DB URL, cookies, raw gateway key, or upstream provider keys. |
| `TestPromptShieldRejectsProviderRoutingFields` | same | Regression where gateway config accepts provider routing, model routes, upstream provider keys, provider secret fields, fallback order, or key pools. |
| `TestPromptShieldGatewayApiRequiresAdminToken` | same | Policy/gateway writes in `gateway_api` mode proceed without token. |
| `TestPromptShieldRejectsNonHttpsNonLoopbackAdminEndpoint` | same | SSRF or insecure admin endpoint accepted. |
| `TestPromptShieldConfigAdminMapping` | same | Read-only Bifrost actor mutates policy/gateway/engine config. |
| `TestPromptShieldDetectRejectsOversizedText` | same | Engine detect endpoint logs or forwards unbounded user text. |

### Handler Tests

| Test | Setup | Expected result |
| --- | --- | --- |
| `TestPromptShieldUnauthenticatedAccessReturns401` | No Bifrost session, fake upstream counter. | `401`; counter is zero. |
| `TestPromptShieldForbiddenMutationReturns403` | Authenticated read-only session, fake upstream counter. | `403`; counter is zero. |
| `TestPromptShieldPolicySaveGatewayTimeoutReturns504` | Fake gateway sleeps past 5s. | `504`, no token in body/log. |
| `TestPromptShieldGateway401MapsToForbidden` | Fake gateway returns `401` with secret-looking body. | `403`, sanitized message. |
| `TestPromptShieldGateway404MapsToConfigMismatch` | Fake gateway returns `404` on `/admin/policy`. | `400`, message names missing admin endpoint. |
| `TestPromptShieldPolicyInvalidPayloadReturns400` | Fake gateway returns `400` invalid policy. | `400`, sanitized payload error. |
| `TestPromptShieldAuditEmptyResultIncludesMetadata` | Fake dashboard returns empty list. | `{ events: [], hasMore: false, retentionDays: 7 }`. |
| `TestPromptShieldKeyCreateReturnsRawKeyOnceNoStore` | Fake dashboard key create. | Response contains one-time `rawKey`, `Cache-Control: no-store`, logs do not contain raw key. |

### UI Tests

| Test | Location | Expected result |
| --- | --- | --- |
| PromptShield sidebar navigation | Bifrost UI Playwright spec | Sidebar has PromptShield group with Overview, Policy, Audit, API Keys, Gateway, Engine, Settings. |
| Same-origin API usage | Bifrost UI Playwright route interception | Pages call `/api/promptshield/*`; no calls to `dashboard:3000`, `promptshield-gateway:8080`, `promptshield-engine:4321`, `/trpc/*`, or `/internal/*`. |
| Policy save errors | Bifrost UI Playwright spec with mocked API | Missing token, 403, timeout, and invalid payload show distinct operator messages. |
| Audit empty state | Bifrost UI Playwright spec with empty API response | Table shows empty state while preserving filters/export controls. |
| No browser token storage | Playwright plus static scan | `localStorage`, `sessionStorage`, window globals, and built JS contain no PromptShield admin token, gateway admin token, engine API key, DB URL, or dashboard cookie. |

### Production Topology Smoke Tests

| Test | Command or file | Expected result |
| --- | --- | --- |
| Existing topology guard | `scripts/verify-production-topology.sh` | Public `/v1/` routes to PromptShield, `/bifrost/v1/*` is blocked, Bifrost remains internal. |
| Blocked request zero Bifrost hit | `scripts/smoke-blocked-request-no-bifrost-hit.sh` | A PromptShield-blocked request does not hit Bifrost. |
| Integrated admin API auth gate | New smoke script after implementation | Unauthenticated `curl /bifrost/api/promptshield/status` fails with `401` or redirects through Bifrost auth. |
| Integrated policy save via gateway API | New smoke script after implementation | Authenticated config admin saves policy through `/bifrost/api/promptshield/policy-file`; gateway receives no browser-origin token. |
| Direct browser token exposure scan | New smoke script after implementation | Built Bifrost assets do not contain PromptShield service env var values or Compose hostnames. |

## Acceptance Mapping

- Every current PromptShield dashboard route is listed in the UI route inventory.
- Every current PromptShield router method relevant to admin parity is listed in the API inventory.
- `/workspace/promptshield/*` routes and `/api/promptshield/*` endpoints are concrete and source-mapped.
- Provider routing, model routes, provider secret controls, upstream provider key editing, fallback order, and key pools are explicitly Bifrost-owned exclusions.
- Tests cover unauthenticated access, forbidden mutation, missing token, upstream timeout, upstream 401/403, policy save failure, audit empty result, and no direct browser token exposure.
- The migration plan keeps PromptShield in front of Bifrost for public inference and provides a rollback path to the digest-pinned Bifrost image.
