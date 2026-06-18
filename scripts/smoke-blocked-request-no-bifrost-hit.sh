#!/usr/bin/env bash
set -euo pipefail

# Smoke test for the production invariant:
# a PromptShield-blocked request must not create a Bifrost/provider request.
#
# Usage:
#   bash scripts/smoke-blocked-request-no-bifrost-hit.sh
#
# The script creates a disposable compose override with a fake-bifrost counter.
# It expects Docker Compose and the normal production stack prerequisites.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

tmp_dir="$(mktemp -d)"
project_name="aegis-blocked-smoke-${RANDOM}"
counter_file="$tmp_dir/upstream_hits"
touch "$counter_file"

cleanup() {
  docker compose -p "$project_name" -f docker-compose.yml -f "$tmp_dir/compose.override.yml" down -v >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cat >"$tmp_dir/fake-bifrost.js" <<'NODE'
import { createServer } from "node:http";
import { appendFileSync } from "node:fs";

const counterFile = process.env.UPSTREAM_HITS;

createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ status: "ok", service: "fake-bifrost" }));
    return;
  }

  appendFileSync(counterFile, `${new Date().toISOString()} ${req.method} ${req.url}\n`);
  res.writeHead(200, { "content-type": "application/json" });
  res.end(JSON.stringify({
    id: "fake",
    object: "chat.completion",
    choices: [{ index: 0, message: { role: "assistant", content: "unexpected upstream hit" }, finish_reason: "stop" }],
  }));
}).listen(8081, "0.0.0.0");
NODE

cat >"$tmp_dir/compose.override.yml" <<YAML
services:
  bifrost:
    image: node:22-alpine
    command: ["node", "/fake-bifrost.js"]
    environment:
      UPSTREAM_HITS: /hits/upstream_hits
    volumes:
      - "$tmp_dir/fake-bifrost.js:/fake-bifrost.js:ro"
      - "$tmp_dir:/hits"
    expose:
      - "8081"
YAML

docker compose -p "$project_name" -f docker-compose.yml -f "$tmp_dir/compose.override.yml" up -d --build

for _ in $(seq 1 60); do
  if curl -fsS http://localhost/health >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

status="$(
  curl -sS -o "$tmp_dir/blocked-response.json" -w '%{http_code}' \
    -X POST http://localhost/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o","messages":[{"role":"user","content":"blocked request with OPENAI_API_KEY=sk-proj-abc123def4567890"}]}'
)"

if [[ "$status" != "403" && "$status" != "400" ]]; then
  echo "Expected blocked request status, got HTTP $status" >&2
  cat "$tmp_dir/blocked-response.json" >&2
  exit 1
fi

if [[ -s "$counter_file" ]]; then
  echo "Blocked request reached fake-bifrost upstream:" >&2
  cat "$counter_file" >&2
  exit 1
fi

echo "PASS: blocked request produced zero Bifrost/provider upstream hits"
