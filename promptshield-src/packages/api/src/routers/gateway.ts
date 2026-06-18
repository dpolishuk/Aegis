import { readFile, writeFile } from "fs/promises";
import { lookup } from "dns/promises";
import { isIP } from "net";
import { z } from "zod";
import { TRPCError } from "@trpc/server";
import { env } from "@promptshield/env/server";

import { protectedProcedure, router } from "../index";
import { requireConfigAdmin } from "../admin-auth";
import {
  getEffectiveGatewayUrl,
  getEffectiveEngineUrl,
  writeRuntimeConfig,
  readRuntimeConfig,
  deleteRuntimeConfigKey,
} from "../runtime-config";

/* .env file helpers */

const gatewayConfigInputSchema = z.object({
  mode: z.enum(["gateway", "security"]),
  engineUrl: z.string(),
  port: z.string().optional(),
  chatRoute: z.string().optional(),
  policyPath: z.string().optional(),
});

type GatewayConfigSource = "local_env" | "gateway_api";

const remoteGatewayConfigSchema = z.object({
  mode: z.enum(["gateway", "security"]).default("security"),
  engineUrl: z.string().default(""),
  provider: z.string().default("gemini"),
  upstreamUrl: z.string().default(""),
  providerMode: z.enum(["single", "multi"]).default("single"),
  providers: z.array(z.string()).default([]),
  providerUrls: z.record(z.string(), z.string()).default({}),
  models: z
    .object({
      global: z.string().default(""),
      gemini: z.string().default(""),
      openai: z.string().default(""),
      anthropic: z.string().default(""),
      selfhosted: z.string().default(""),
    })
    .default({
      global: "",
      gemini: "",
      openai: "",
      anthropic: "",
      selfhosted: "",
    }),
  modelRoutes: z
    .array(z.object({ model: z.string(), provider: z.string() }))
    .default([]),
  keyCounts: z
    .object({
      upstream: z.number().int().nonnegative().default(0),
      gemini: z.number().int().nonnegative().default(0),
      openai: z.number().int().nonnegative().default(0),
      anthropic: z.number().int().nonnegative().default(0),
    })
    .default({
      upstream: 0,
      gemini: 0,
      openai: 0,
      anthropic: 0,
    }),
  port: z.string().default("8080"),
  chatRoute: z.string().default("/v1/chat/completions"),
  policyPath: z.string().default("config/policy.yaml"),
});

function getGatewayConfigSource(): GatewayConfigSource {
  return env.GATEWAY_CONFIG_SOURCE;
}

function isLoopbackHost(host: string): boolean {
  const lower = host.toLowerCase();
  if (lower === "localhost") return true;
  const version = isIP(host);
  if (version === 4) return host.startsWith("127.");
  if (version === 6) return lower === "::1";
  return false;
}

function assertGatewayApiSecurity(): void {
  const target = buildGatewayConfigUrl();
  const parsed = new URL(target);

  if (!env.GATEWAY_ADMIN_TOKEN) {
    throw new TRPCError({
      code: "BAD_REQUEST",
      message:
        "GATEWAY_ADMIN_TOKEN is required when GATEWAY_CONFIG_SOURCE=gateway_api",
    });
  }

  if (parsed.protocol === "https:") return;
  if (parsed.protocol === "http:" && isLoopbackHost(parsed.hostname)) return;

  throw new TRPCError({
    code: "BAD_REQUEST",
    message:
      "Gateway config endpoint must use HTTPS unless targeting localhost/loopback",
  });
}

function buildGatewayConfigUrl(): string {
  return new URL(env.GATEWAY_CONFIG_ENDPOINT, `${env.GATEWAY_URL}/`).toString();
}

function gatewayAdminHeaders(contentType?: string): Record<string, string> {
  return {
    ...(contentType ? { "Content-Type": contentType } : {}),
    ...(env.GATEWAY_ADMIN_TOKEN
      ? { Authorization: `Bearer ${env.GATEWAY_ADMIN_TOKEN}` }
      : {}),
  };
}

function gatewayConfigError(status: number, bodyText: string): TRPCError {
  if (status === 401 || status === 403) {
    return new TRPCError({
      code: "FORBIDDEN",
      message: "Gateway config endpoint rejected credentials",
    });
  }

  if (status === 404) {
    return new TRPCError({
      code: "BAD_REQUEST",
      message:
        "Gateway config endpoint not found. Ensure promptshield-gateway exposes /admin/config",
    });
  }

  return new TRPCError({
    code: "BAD_REQUEST",
    message: `Gateway config request failed (${status})${bodyText ? `: ${bodyText.slice(0, 120)}` : ""}`,
  });
}

async function fetchGatewayConfig(): Promise<Record<string, unknown>> {
  assertGatewayApiSecurity();
  const url = buildGatewayConfigUrl();

  let res: Response;
  try {
    res = await fetch(url, {
      method: "GET",
      headers: gatewayAdminHeaders(),
      signal: AbortSignal.timeout(4000),
    });
  } catch {
    throw new TRPCError({
      code: "SERVICE_UNAVAILABLE",
      message: "Unable to reach gateway config endpoint",
    });
  }

  if (!res.ok) {
    const bodyText = await res.text().catch(() => "");
    throw gatewayConfigError(res.status, bodyText);
  }

  const data = (await res.json().catch(() => null)) as unknown;
  const parsed = remoteGatewayConfigSchema.safeParse(data);
  if (!parsed.success) {
    throw new TRPCError({
      code: "BAD_GATEWAY",
      message: "Gateway config endpoint returned invalid payload",
    });
  }
  return parsed.data;
}

async function updateGatewayConfigViaApi(input: z.infer<typeof gatewayConfigInputSchema>) {
  assertGatewayApiSecurity();
  const url = buildGatewayConfigUrl();
  const securityConfig = {
    mode: input.mode,
    engineUrl: input.engineUrl,
    port: input.port,
    chatRoute: input.chatRoute,
    policyPath: input.policyPath,
  };

  const putRes = await fetch(url, {
    method: "PUT",
    headers: gatewayAdminHeaders("application/json"),
    body: JSON.stringify(securityConfig),
    signal: AbortSignal.timeout(5000),
  }).catch(() => null);

  if (putRes?.ok) return;

  if (putRes && ![400, 404, 405].includes(putRes.status)) {
    const bodyText = await putRes.text().catch(() => "");
    throw gatewayConfigError(putRes.status, bodyText);
  }

  const postRes = await fetch(url, {
    method: "POST",
    headers: gatewayAdminHeaders("application/json"),
    body: JSON.stringify(securityConfig),
    signal: AbortSignal.timeout(5000),
  }).catch(() => null);

  if (postRes?.ok) return;

  if (!postRes) {
    throw new TRPCError({
      code: "SERVICE_UNAVAILABLE",
      message: "Unable to reach gateway config endpoint",
    });
  }

  const bodyText = await postRes.text().catch(() => "");
  throw gatewayConfigError(postRes.status, bodyText);
}

function hasUnsafeEnvChars(value: string): boolean {
  return value.includes("\n") || value.includes("\r") || value.includes("\0");
}

function toEnvValue(value: string): string {
  // Quote values that include characters with special meaning in .env files.
  if (/^[A-Za-z0-9_./:@,+-]+$/.test(value)) return value;
  const escaped = value.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
  return `"${escaped}"`;
}

function assertSafeEnvValue(field: string, value: string) {
  if (hasUnsafeEnvChars(value)) {
    throw new TRPCError({
      code: "BAD_REQUEST",
      message: `${field} contains unsafe characters`,
    });
  }
}

function isLinkLocalIp(hostOrIp: string): boolean {
  const v = isIP(hostOrIp);
  if (v === 4) {
    return hostOrIp.startsWith("169.254.") || hostOrIp === "168.63.129.16";
  }
  if (v === 6) {
    const normalized = hostOrIp.toLowerCase();
    return (
      normalized.startsWith("fe8") ||
      normalized.startsWith("fe9") ||
      normalized.startsWith("fea") ||
      normalized.startsWith("feb")
    );
  }
  return false;
}

function normalizeHealthPath(healthPath: string): string {
  const trimmed = healthPath.trim();
  if (!trimmed) return "/health";
  if (trimmed.includes("://") || hasUnsafeEnvChars(trimmed)) {
    throw new TRPCError({
      code: "BAD_REQUEST",
      message: "Invalid health path",
    });
  }
  return trimmed.startsWith("/") ? trimmed : `/${trimmed}`;
}

async function validateSafeHttpUrl(
  rawUrl: string,
  fieldLabel: string,
): Promise<string> {
  if (hasUnsafeEnvChars(rawUrl)) {
    throw new TRPCError({
      code: "BAD_REQUEST",
      message: `${fieldLabel} contains unsafe characters`,
    });
  }

  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new TRPCError({
      code: "BAD_REQUEST",
      message: `${fieldLabel} must be a valid URL`,
    });
  }

  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    throw new TRPCError({
      code: "BAD_REQUEST",
      message: `${fieldLabel} must use http or https`,
    });
  }

  if (isLinkLocalIp(parsed.hostname)) {
    throw new TRPCError({
      code: "BAD_REQUEST",
      message: `${fieldLabel} cannot target link-local addresses`,
    });
  }

  if (isIP(parsed.hostname) === 0) {
    try {
      const records = await lookup(parsed.hostname, { all: true });
      if (records.some((record) => isLinkLocalIp(record.address))) {
        throw new TRPCError({
          code: "BAD_REQUEST",
          message: `${fieldLabel} resolves to a link-local address`,
        });
      }
    } catch (err) {
      if (err instanceof TRPCError) throw err;
      // DNS failures are handled when the connection is attempted later.
    }
  }

  return parsed.toString().replace(/\/+$/, "");
}

function parseEnvFile(content: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx === -1) continue;
    const key = trimmed.slice(0, idx).trim();
    let val = trimmed.slice(idx + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (key) result[key] = val;
  }
  return result;
}

function updateEnvFile(
  content: string,
  updates: Record<string, string>,
): string {
  const lines = content.split("\n");
  const seen = new Set<string>();

  const updated = lines.map((line) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) return line;
    const idx = trimmed.indexOf("=");
    if (idx === -1) return line;
    const key = trimmed.slice(0, idx).trim();
    if (key in updates) {
      seen.add(key);
      const val = updates[key];
      // If the update value is empty, comment out the line
      return val ? `${key}=${toEnvValue(val)}` : `# ${key}=`;
    }
    return line;
  });

  // Append keys that weren't in the file yet
  const appended: string[] = [];
  for (const [key, val] of Object.entries(updates)) {
    if (!seen.has(key) && val) appended.push(`${key}=${toEnvValue(val)}`);
  }

  return [...updated, ...appended].join("\n");
}

/* Router */

export const gatewayRouter = router({
  configSourceInfo: protectedProcedure.query(async () => {
    const source = getGatewayConfigSource();
    if (source === "gateway_api") {
      assertGatewayApiSecurity();
    }
    return {
      source,
      gatewayUrl: env.GATEWAY_URL,
      gatewayConfigEndpoint:
        source === "gateway_api" ? buildGatewayConfigUrl() : null,
      hasGatewayAdminToken: Boolean(env.GATEWAY_ADMIN_TOKEN),
    };
  }),

  health: protectedProcedure.query(async () => {
    const url = await getEffectiveGatewayUrl();
    const start = Date.now();
    try {
      const res = await fetch(`${url}/health`, {
        signal: AbortSignal.timeout(3000),
      });
      const latencyMs = Date.now() - start;
      return { online: res.ok, latencyMs, url };
    } catch {
      return { online: false, latencyMs: null, url };
    }
  }),

  engineHealth: protectedProcedure.query(async () => {
    const url = await getEffectiveEngineUrl();
    const start = Date.now();
    try {
      const res = await fetch(`${url}/health`, {
        signal: AbortSignal.timeout(3000),
      });
      const latencyMs = Date.now() - start;
      let data: unknown = null;
      try {
        data = await res.json();
      } catch {
        // Engine health endpoint may return non-JSON payloads.
      }
      return { online: res.ok, latencyMs, url, data };
    } catch {
      return { online: false, latencyMs: null, url, data: null };
    }
  }),

  getUrls: protectedProcedure.query(async () => {
    const cfg = await readRuntimeConfig();
    return {
      gatewayUrl: cfg.gatewayUrl ?? env.GATEWAY_URL,
      engineUrl: cfg.engineUrl ?? env.ENGINE_URL,
      gatewayDefault: env.GATEWAY_URL,
      engineDefault: env.ENGINE_URL,
    };
  }),

  saveGatewayUrl: protectedProcedure
    .input(z.object({ url: z.string().url("Must be a valid URL") }))
    .mutation(async ({ ctx, input }) => {
      requireConfigAdmin(ctx.session, env.CONFIG_ADMIN_EMAILS);
      const safeUrl = await validateSafeHttpUrl(input.url, "Gateway URL");
      await writeRuntimeConfig({ gatewayUrl: safeUrl });
      return { saved: true, url: safeUrl };
    }),

  saveEngineUrl: protectedProcedure
    .input(z.object({ url: z.string().url("Must be a valid URL") }))
    .mutation(async ({ ctx, input }) => {
      requireConfigAdmin(ctx.session, env.CONFIG_ADMIN_EMAILS);
      const safeUrl = await validateSafeHttpUrl(input.url, "Engine URL");
      await writeRuntimeConfig({ engineUrl: safeUrl });
      return { saved: true, url: safeUrl };
    }),

  resetGatewayUrl: protectedProcedure.mutation(async ({ ctx }) => {
    requireConfigAdmin(ctx.session, env.CONFIG_ADMIN_EMAILS);
    await deleteRuntimeConfigKey("gatewayUrl");
    return { reset: true, url: env.GATEWAY_URL };
  }),

  resetEngineUrl: protectedProcedure.mutation(async ({ ctx }) => {
    requireConfigAdmin(ctx.session, env.CONFIG_ADMIN_EMAILS);
    await deleteRuntimeConfigKey("engineUrl");
    return { reset: true, url: env.ENGINE_URL };
  }),

  checkUrl: protectedProcedure
    .input(
      z.object({
        url: z.string().url("Must be a valid URL"),
        healthPath: z.string().default("/health"),
      }),
    )
    .mutation(async ({ ctx, input }) => {
      requireConfigAdmin(ctx.session, env.CONFIG_ADMIN_EMAILS);
      const safeBaseUrl = await validateSafeHttpUrl(input.url, "URL");
      const safeHealthPath = normalizeHealthPath(input.healthPath);
      const target = new URL(safeHealthPath, `${safeBaseUrl}/`).toString();

      const start = Date.now();
      try {
        const res = await fetch(target, { signal: AbortSignal.timeout(4000) });
        return { online: res.ok, latencyMs: Date.now() - start };
      } catch {
        return { online: false, latencyMs: null };
      }
    }),

  getConfig: protectedProcedure.query(async () => {
    if (getGatewayConfigSource() === "gateway_api") {
      const remote = await fetchGatewayConfig();
      return {
        mode:
          remote.mode === "gateway" || remote.mode === "security"
            ? remote.mode
            : "security",
        engineUrl: typeof remote.engineUrl === "string" ? remote.engineUrl : "",
        provider: typeof remote.provider === "string" ? remote.provider : "gemini",
        upstreamUrl:
          typeof remote.upstreamUrl === "string" ? remote.upstreamUrl : "",
        providerMode:
          remote.providerMode === "single" || remote.providerMode === "multi"
            ? remote.providerMode
            : "single",
        providers: Array.isArray(remote.providers)
          ? remote.providers.filter((p) => typeof p === "string")
          : [],
        providerUrls:
          typeof remote.providerUrls === "object" && remote.providerUrls !== null
            ? (remote.providerUrls as Record<string, string>)
            : {},
        models:
          typeof remote.models === "object" && remote.models !== null
            ? (remote.models as Record<string, string>)
            : {
                global: "",
                gemini: "",
                openai: "",
                anthropic: "",
                selfhosted: "",
              },
        modelRoutes: Array.isArray(remote.modelRoutes)
          ? (remote.modelRoutes as { model: string; provider: string }[])
          : [],
        keyCounts:
          typeof remote.keyCounts === "object" && remote.keyCounts !== null
            ? (remote.keyCounts as {
                upstream: number;
                gemini: number;
                openai: number;
                anthropic: number;
              })
            : {
                upstream: 0,
                gemini: 0,
                openai: 0,
                anthropic: 0,
              },
        port: typeof remote.port === "string" ? remote.port : "8080",
        chatRoute:
          typeof remote.chatRoute === "string"
            ? remote.chatRoute
            : "/v1/chat/completions",
        policyPath:
          typeof remote.policyPath === "string"
            ? remote.policyPath
            : "config/policy.yaml",
      };
    }

    const content = await readFile(env.GATEWAY_ENV_PATH, "utf-8").catch(() => "");
    const e = parseEnvFile(content);

    const engineUrl = e.PROMPTSHIELD_ENGINE_URL ?? "none";

    return {
      mode: engineUrl === "none" ? "gateway" : "security",
      engineUrl: engineUrl === "none" ? "" : engineUrl,
      provider: "openai-compatible",
      upstreamUrl: "",
      providerMode: "single" as const,
      providers: [],
      providerUrls: {
        "openai-compatible":
          e.PROMPTSHIELD_OPENAI_COMPATIBLE_UPSTREAM_URL ?? "",
      },
      models: {
        global: "",
        gemini: "",
        openai: "",
        anthropic: "",
        selfhosted: "",
      },
      modelRoutes: [],
      keyCounts: {
        upstream: 0,
        gemini: 0,
        openai: 0,
        anthropic: 0,
      },
      port: e.PROMPTSHIELD_PORT ?? "8080",
      chatRoute: e.PROMPTSHIELD_CHAT_ROUTE ?? "/v1/chat/completions",
      policyPath: e.PROMPTSHIELD_POLICY_PATH ?? "config/policy.yaml",
    };
  }),

  updateConfig: protectedProcedure
    .input(gatewayConfigInputSchema)
    .mutation(async ({ ctx, input }) => {
      requireConfigAdmin(ctx.session, env.CONFIG_ADMIN_EMAILS);
      if (getGatewayConfigSource() === "gateway_api") {
        await updateGatewayConfigViaApi(input);
        return { success: true };
      }

      const content = await readFile(env.GATEWAY_ENV_PATH, "utf-8").catch(
        () => "",
      );

      const safeEngineUrl =
        input.mode === "gateway" || !input.engineUrl.trim()
          ? "none"
          : await validateSafeHttpUrl(input.engineUrl, "Engine URL");

      const updates: Record<string, string> = {
        PROMPTSHIELD_ENGINE_URL: safeEngineUrl,
      };

      if (input.port) updates.PROMPTSHIELD_PORT = input.port;
      if (input.chatRoute) updates.PROMPTSHIELD_CHAT_ROUTE = input.chatRoute;
      if (input.policyPath) updates.PROMPTSHIELD_POLICY_PATH = input.policyPath;

      for (const [key, value] of Object.entries(updates)) {
        if (value) assertSafeEnvValue(key, value);
      }

      const updated = updateEnvFile(content, updates);
      await writeFile(env.GATEWAY_ENV_PATH, updated, "utf-8");
      return { success: true };
    }),

  getEngineConfig: protectedProcedure.query(async () => {
    const engineUrl = await getEffectiveEngineUrl();
    try {
      const res = await fetch(`${engineUrl}/config`, {
        signal: AbortSignal.timeout(3000),
      });
      if (!res.ok) return { maskConfig: null };
      const data = (await res.json()) as {
        maskConfig?: Record<string, boolean>;
      };
      return { maskConfig: data.maskConfig ?? null };
    } catch {
      return { maskConfig: null };
    }
  }),

  updateEngineConfig: protectedProcedure
    .input(z.object({ maskConfig: z.record(z.string(), z.boolean()) }))
    .mutation(async ({ ctx, input }) => {
      requireConfigAdmin(ctx.session, env.CONFIG_ADMIN_EMAILS);
      const engineUrl = await getEffectiveEngineUrl();
      const res = await fetch(`${engineUrl}/config`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ maskConfig: input.maskConfig }),
        signal: AbortSignal.timeout(5000),
      });
      if (!res.ok)
        throw new TRPCError({
          code: "BAD_GATEWAY",
          message: "Engine config update failed",
        });
      return { success: true };
    }),
});
