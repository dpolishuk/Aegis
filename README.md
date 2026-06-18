# Filter — PromptShield + Bifrost

One production AI gateway with PromptShield inline security and Bifrost provider routing.

## Production Topology Contract

All OpenAI-compatible inference traffic enters the product through Nginx at `/v1/*`.
PromptShield is mandatory pre-routing enforcement: it screens requests before Bifrost
or any model provider can receive them. Bifrost is the downstream provider/router and
governance control plane.

Accepted production request path:

```
Client
    ↓
Nginx /v1/*
    ↓
PromptShield Gateway
    ↓ allowed requests only
Bifrost /v1
    ↓
LLM provider
```

Blocked PromptShield requests must stop at PromptShield and must not reach Bifrost.
Clients must not call Bifrost `/v1` directly in production.

`/bifrost/` is private/admin UI access for router/provider management only. It is
not the public inference URL; Nginx blocks `/bifrost/v1` and `/bifrost/v1/*` so
Bifrost inference cannot bypass PromptShield. The production Nginx config denies
public access to `/bifrost/` and only allows localhost/RFC1918 private networks;
tighten those ranges or place it behind your admin auth before exposing Nginx.

## Architecture

```
Client
    ↓
Nginx (:80/:443 public)
    ├── /v1/*       → PromptShield Gateway (:8080 internal) → Bifrost (:8081 internal) → LLM providers
    ├── /bifrost/   → Bifrost admin UI only; /bifrost/v1/* is blocked
    ├── /api, /trpc → Dashboard API (:3000 internal)
    ├── /           → Dashboard web (:8000 internal)
    └── /health     → PromptShield Gateway health
                     ↓
              PromptShield Engine (:4321 internal) - PII detection
                     ↓
              Postgres (:5432 internal)
```

## Health Checks

Production health checks are defined in `docker-compose.yml`:

- Nginx depends on healthy PromptShield Gateway and Dashboard services.
- PromptShield Gateway: `GET http://localhost:8080/health`.
- PromptShield Engine: `GET http://localhost:4321/ready`.
- Dashboard API: `GET http://localhost:3000/`.
- Postgres: `pg_isready -U postgres`.
- Bifrost starts before PromptShield forwards allowed inference traffic to `http://bifrost:8081/v1`.

Run static topology verification before deployment changes:

```bash
scripts/verify-production-topology.sh
```

## Quick Start

### 1. Configure

```bash
cp .env.example .env
# Edit .env: set strong secrets, admin emails, and domain.
nano .env
```

Provider API keys and routing configuration belong to Bifrost. Add provider keys
through the Bifrost admin UI or your approved secret-management workflow; do not
commit real provider secrets or `bifrost-data/*` runtime state to this repository.

### 2. Run

```bash
docker compose up -d
```

### 3. Configure Bifrost

After startup, open the Bifrost admin UI through Nginx from localhost or an
admin-only private network:

```bash
open http://localhost/bifrost/
```

Add OpenAI, Anthropic, Gemini, or other provider credentials in Bifrost. PromptShield
must stay in `openai-compatible` mode and forward allowed requests to Bifrost.

### 4. Verify

```bash
# Health check
curl http://your-server/health

# API-запрос через PromptShield → Bifrost → LLM
curl -X POST http://your-server/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "openai/gpt-4o-mini",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Ports

| Service | External | Internal |
|--------|---------|------------|
| Nginx | 80, 443 | - |
| PromptShield Gateway | local/admin only | 8080 |
| PromptShield Engine | local/admin only | 4321 |
| Bifrost | via `/bifrost/` admin UI only | 8081 |
| Dashboard API/Web | via Nginx | 3000, 8000 |
| Postgres | - | 5432 |

## SSL (Let's Encrypt)

```bash
# Установите certbot на сервер
apt install certbot

# Получите сертификат
certbot certonly --webroot -w /path/to/certbot-www -d your-domain.com

# Скопируйте сертификаты
cp /etc/letsencrypt/live/your-domain.com/fullchain.pem nginx/ssl/
cp /etc/letsencrypt/live/your-domain.com/privkey.pem nginx/ssl/

# Раскомментируйте ssl_* строки в nginx/nginx.conf
# Перезапустите
docker compose restart nginx
```

## PII Policy

Edit `policy.yaml` to configure PromptShield enforcement:

- **mask** - replace PII with placeholders, then restore in the response
- **block** - reject the request before Bifrost/provider routing
- **allow** - pass the request through without transformation

Supported types: CREDIT_CARD, US_SSN, EMAIL_ADDRESS, PHONE_NUMBER, IBAN_CODE,
IP_ADDRESS, PERSON, LOCATION, MEDICAL_LICENSE, US_PASSPORT, US_DRIVER_LICENSE

## PII Detection Languages

Set `SPACY_PROFILE` in `.env`:

| Value | Languages |
|----------|-------|
| minimal | English + Chinese |
| fr | minimal + French |
| de | minimal + German |
| ja | minimal + Japanese |
| multi | Все языки + мультиязычная модель |
