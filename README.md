# Filter — PromptShield + Bifrost

AI-шлюз с PII-защитой для команды.

## Архитектура

```
Пользователь
    ↓
Nginx (:80/:443)
    ├── /v1/*    → PromptShield Gateway (:8080) → Bifrost (:8081) → LLM Providers
    ├── /admin/*  → Dashboard (:3000)
    └── /health   → PromptShield health
                     ↓
              PromptShield Engine (:4321) — PII-детекция (Presidio + spaCy)
                     ↓
              Postgres (:5432)
```

## Быстрый старт

### 1. Настройка

```bash
cp .env.example .env
# Отредактируйте .env — укажите пароли, ключи, домен
nano .env
```

### 2. Запуск

```bash
docker compose up -d
```

### 3. Настройка Bifrost

После запуска откройте Web UI Bifrost для добавления LLM-провайдеров:

```bash
# Bifrost Web UI доступен напрямую:
open http://your-server:8081
```

Добавьте API-ключи OpenAI, Anthropic и т.д. через интерфейс Bifrost.

### 4. Проверка

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

## Порты

| Сервис | Внешний | Внутренний |
|--------|---------|------------|
| Nginx  | 80, 443 | — |
| PromptShield Gateway | 8080 | 8080 |
| PromptShield Engine | 4321 | 4321 |
| Bifrost | 8081 | 8081 |
| Dashboard | 3000 | 3000 |
| Postgres | — | 5432 |

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

## Настройка PII-политики

Отредактируйте `policy.yaml` для настройки:

- **mask** — заменить PII на плейсхолдеры, затем восстановить в ответе
- **block** — отклонить запрос с PII
- **allow** — пропустить без обработки

Поддерживаемые типы: CREDIT_CARD, US_SSN, EMAIL_ADDRESS, PHONE_NUMBER, IBAN_CODE, IP_ADDRESS, PERSON, LOCATION, MEDICAL_LICENSE, US_PASSPORT, US_DRIVER_LICENSE

## Языки PII-детекции

В `.env` переменная `SPACY_PROFILE`:

| Значение | Языки |
|----------|-------|
| minimal | English + Chinese |
| fr | minimal + French |
| de | minimal + German |
| ja | minimal + Japanese |
| multi | Все языки + мультиязычная модель |
