#!/usr/bin/env bash
set -euo pipefail

# Smoke test for the production invariant:
# a PromptShield detection-policy block must not create a Bifrost/provider
# request after a positive control proves the upstream path works.
#
# Usage:
#   bash scripts/smoke-blocked-request-no-bifrost-hit.sh
#
# The script creates a disposable minimal compose stack with production Nginx,
# PromptShield gateway, fake Bifrost, fake engine, and dummy dashboard/web
# upstreams.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

tmp_parent="${TMPDIR:-/tmp}"
tmp_dir="$(mktemp -d "$tmp_parent/aegis-blocked-smoke.XXXXXX")"
project_name="aegis-blocked-smoke-${RANDOM}"
compose_file="$tmp_dir/compose.yml"
host_port="$((18080 + RANDOM % 10000))"

cleanup() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    docker compose -p "$project_name" -f "$compose_file" logs promptshield-gateway >&2 || true
  fi
  docker compose -p "$project_name" -f "$compose_file" down -v >/dev/null 2>&1 || true
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cat >"$tmp_dir/fake-bifrost.py" <<'PY'
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

hits = []

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _text(self, status, payload):
        body = str(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "text/plain")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"status": "ok", "service": "fake-bifrost"})
            return
        if self.path == "/hits":
            self._text(200, len(hits))
            return
        if self.path == "/reset":
            hits.clear()
            self._text(200, "ok")
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        hits.append(f"{datetime.now(timezone.utc).isoformat()} {self.command} {self.path}")
        self._json(200, {
            "id": "fake",
            "object": "chat.completion",
            "choices": [{
                "index": 0,
                "message": {"role": "assistant", "content": "fake upstream hit"},
                "finish_reason": "stop",
            }],
        })

HTTPServer(("0.0.0.0", 8081), Handler).serve_forever()
PY

cat >"$tmp_dir/fake-engine.py" <<'PY'
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in {"/health", "/ready"}:
            self._json(200, {"status": "ok", "service": "fake-engine"})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/detect":
            length = int(self.headers.get("content-length", "0") or "0")
            body = self.rfile.read(length).decode("utf-8", errors="replace")
            if "blocked@example.com" in body:
                self._json(200, {
                    "pii_detected": True,
                    "injection_detected": False,
                    "entities": [{
                        "type": "EMAIL_ADDRESS",
                        "start": 0,
                        "end": 19,
                        "text": "blocked@example.com",
                        "score": 0.99,
                    }],
                    "language": "en",
                })
                return
            self._json(200, {
                "pii_detected": False,
                "injection_detected": False,
                "entities": [],
                "language": "en",
            })
            return
        self._json(404, {"error": "not found"})

HTTPServer(("0.0.0.0", 4321), Handler).serve_forever()
PY

cat >"$tmp_dir/fake-http.py" <<'PY'
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

port = int(os.environ["PORT"])
service = os.environ.get("SERVICE_NAME", "fake-http")

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self._json(200, {"status": "ok", "service": service})

    def do_POST(self):
        self._json(200, {"status": "ok", "service": service})

HTTPServer(("0.0.0.0", port), Handler).serve_forever()
PY

cat >"$tmp_dir/Dockerfile.fake-python" <<'DOCKER'
FROM python:3.12-alpine
COPY fake-*.py /
DOCKER

cat >"$compose_file" <<YAML
name: "$project_name"

services:
  nginx:
    image: nginx:alpine
    ports:
      - "$host_port:80"
    volumes:
      - "$ROOT_DIR/nginx/nginx.conf:/etc/nginx/nginx.conf:ro"
    depends_on:
      promptshield-gateway:
        condition: service_healthy
      dashboard:
        condition: service_started
      web:
        condition: service_started
    networks:
      - filter

  promptshield-gateway:
    build:
      context: https://github.com/promptshieldhq/promptshield-gateway.git#v1.0.0
      dockerfile: Dockerfile
    environment:
      PROMPTSHIELD_PORT: "8080"
      PROMPTSHIELD_PROVIDER: openai-compatible
      PROMPTSHIELD_OPENAI_COMPATIBLE_UPSTREAM_URL: http://bifrost:8081/v1
      PROMPTSHIELD_ENGINE_URL: http://promptshield-engine:4321
      PROMPTSHIELD_POLICY_PATH: /tmp/policy.yaml
    volumes:
      - "$ROOT_DIR/policy.yaml:/base-policy/policy.yaml:ro"
    entrypoint: ["/bin/sh", "-c"]
    command:
      - |
        sed 's/EMAIL_ADDRESS: mask/EMAIL_ADDRESS: block/' /base-policy/policy.yaml > /tmp/policy.yaml
        exec /app/promptshield
    expose:
      - "8080"
    depends_on:
      promptshield-engine:
        condition: service_started
      bifrost:
        condition: service_started
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:8080/health || exit 1"]
      interval: 2s
      timeout: 2s
      retries: 30
      start_period: 2s
    networks:
      - filter

  promptshield-engine:
    build:
      context: "$tmp_dir"
      dockerfile: Dockerfile.fake-python
    image: "${project_name}-fake-engine"
    command: ["python", "/fake-engine.py"]
    environment:
      PROMPTSHIELD_ALLOW_UNAUTH: "true"
    expose:
      - "4321"
    ports: []
    healthcheck:
      test: ["CMD", "true"]
      interval: 2s
      timeout: 2s
      retries: 15
      start_period: 1s
    networks:
      - filter

  bifrost:
    build:
      context: "$tmp_dir"
      dockerfile: Dockerfile.fake-python
    image: "${project_name}-fake-bifrost"
    command: ["python", "/fake-bifrost.py"]
    expose:
      - "8081"
    networks:
      - filter

  dashboard:
    build:
      context: "$tmp_dir"
      dockerfile: Dockerfile.fake-python
    image: "${project_name}-fake-dashboard"
    command: ["python", "/fake-http.py"]
    environment:
      PORT: "3000"
      SERVICE_NAME: fake-dashboard
    expose:
      - "3000"
    networks:
      - filter

  web:
    build:
      context: "$tmp_dir"
      dockerfile: Dockerfile.fake-python
    image: "${project_name}-fake-web"
    command: ["python", "/fake-http.py"]
    environment:
      PORT: "8000"
      SERVICE_NAME: fake-web
    expose:
      - "8000"
    networks:
      - filter

networks:
  filter:
YAML

docker compose -p "$project_name" -f "$compose_file" up -d --build nginx

bifrost_hits() {
  docker compose -p "$project_name" -f "$compose_file" exec -T bifrost \
    python -c 'import urllib.request; print(urllib.request.urlopen("http://localhost:8081/hits").read().decode().strip())'
}

reset_bifrost_hits() {
  docker compose -p "$project_name" -f "$compose_file" exec -T bifrost \
    python -c 'import urllib.request; urllib.request.urlopen("http://localhost:8081/reset").read()' >/dev/null
}

for _ in $(seq 1 60); do
  if curl --max-time 2 -fsS "http://localhost:$host_port/health" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

allowed_status="$(
  curl -sS -o "$tmp_dir/allowed-response.json" -w '%{http_code}' \
    --max-time 15 \
    -X POST "http://localhost:$host_port/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o","messages":[{"role":"user","content":"allowed request positive control"}]}'
)"

if [[ "$allowed_status" != "200" ]]; then
  echo "Expected allowed request to reach fake-bifrost, got HTTP $allowed_status" >&2
  cat "$tmp_dir/allowed-response.json" >&2
  exit 1
fi

if [[ "$(bifrost_hits)" == "0" ]]; then
  echo "Allowed request did not reach fake-bifrost; zero-hit assertion would be meaningless" >&2
  exit 1
fi

reset_bifrost_hits

status="$(
  curl -sS -o "$tmp_dir/blocked-response.json" -w '%{http_code}' \
    --max-time 15 \
    -X POST "http://localhost:$host_port/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d '{"model":"gpt-4o","messages":[{"role":"user","content":"blocked request contains blocked@example.com before Bifrost"}]}'
)"

if [[ "$status" != "400" && "$status" != "403" ]]; then
  echo "Expected detection-policy blocked request status, got HTTP $status" >&2
  cat "$tmp_dir/blocked-response.json" >&2
  exit 1
fi

if [[ "$(bifrost_hits)" != "0" ]]; then
  echo "Blocked request reached fake-bifrost upstream" >&2
  exit 1
fi

echo "PASS: detection-policy blocked request produced zero Bifrost/provider upstream hits"
