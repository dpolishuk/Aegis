import { useMutation, useQuery } from "@tanstack/react-query";
import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import {
  AlertTriangle,
  ChevronDown,
  ChevronRight,
  RefreshCw,
  Server,
} from "lucide-react";
import { toast } from "sonner";

import { useTRPC } from "@/utils/trpc";

export const Route = createFileRoute("/_layout/gateway")({
  component: GatewayPage,
});

/* Helpers */
function Sk({ className = "" }: { className?: string }) {
  return (
    <div
      className={`animate-pulse rounded bg-muted/50 ${className}`}
      aria-hidden="true"
    />
  );
}

function getErrorMessage(error: unknown, fallback: string): string {
  if (typeof error === "object" && error !== null) {
    const maybeMessage = (error as { message?: unknown }).message;
    if (typeof maybeMessage === "string" && maybeMessage.trim()) {
      return maybeMessage;
    }

    const maybeShapeMessage = (error as { shape?: { message?: unknown } }).shape
      ?.message;
    if (typeof maybeShapeMessage === "string" && maybeShapeMessage.trim()) {
      return maybeShapeMessage;
    }
  }

  return fallback;
}

function Field({
  label,
  helper,
  children,
}: {
  label: string;
  helper?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="mb-1.5 block text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60">
        {label}
      </label>
      {children}
      {helper && (
        <p className="mt-1 text-[11px] text-muted-foreground/50">{helper}</p>
      )}
    </div>
  );
}

function Input({
  value,
  onChange,
  placeholder,
  mono = false,
  ...rest
}: React.InputHTMLAttributes<HTMLInputElement> & { mono?: boolean }) {
  return (
    <input
      value={value}
      onChange={onChange}
      placeholder={placeholder}
      className={`w-full rounded-md border border-border bg-background px-3 py-2 text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-primary/30 ${mono ? "font-mono" : ""}`}
      {...rest}
    />
  );
}

function SectionCard({
  title,
  description,
  children,
  defaultOpen = true,
}: {
  title: string;
  description?: string;
  children: React.ReactNode;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className="overflow-hidden rounded-lg border border-border bg-card">
      <button
        onClick={() => setOpen(!open)}
        className="flex w-full items-center justify-between border-b border-border px-5 py-3 text-left"
        aria-expanded={open}
      >
        <div>
          <h2 className="text-xs font-semibold text-foreground">{title}</h2>
          {description && (
            <p className="mt-0.5 text-[11px] text-muted-foreground">
              {description}
            </p>
          )}
        </div>
        {open ? (
          <ChevronDown size={13} className="shrink-0 text-muted-foreground" />
        ) : (
          <ChevronRight size={13} className="shrink-0 text-muted-foreground" />
        )}
      </button>
      {open && <div className="p-5 space-y-4">{children}</div>}
    </div>
  );
}

function BifrostControlPlaneCard() {
  return (
    <div className="rounded-md border border-primary/20 bg-primary/5 px-4 py-3">
      <div className="flex items-start gap-3">
        <Server
          size={15}
          className="mt-0.5 shrink-0 text-primary"
          aria-hidden="true"
        />
        <div className="min-w-0">
          <p className="text-xs font-semibold text-primary">
            Bifrost owns provider routing and secrets
          </p>
          <p className="mt-1 text-[11px] leading-relaxed text-muted-foreground">
            Configure provider credentials, model routes, key pools, fallback
            order, and router governance in the Bifrost provider/router control
            plane. This page only manages PromptShield policy and security
            gateway settings.
          </p>
          <a
            href="/bifrost/"
            className="mt-2 inline-flex items-center gap-1.5 rounded-md border border-primary/25 bg-background px-2.5 py-1.5 text-[11px] font-semibold text-primary transition-colors hover:bg-primary/10"
          >
            Open Bifrost router admin
            <ChevronRight size={11} aria-hidden="true" />
          </a>
        </div>
      </div>
    </div>
  );
}

/* Page */
function GatewayPage() {
  const trpc = useTRPC();

  const gatewayHealth = useQuery(
    trpc.gateway.health.queryOptions(undefined, { refetchInterval: 20_000 }),
  );
  const engineHealth = useQuery(
    trpc.gateway.engineHealth.queryOptions(undefined, {
      refetchInterval: 20_000,
    }),
  );
  const gatewayConfig = useQuery(trpc.gateway.getConfig.queryOptions());
  const configSourceInfo = useQuery(trpc.gateway.configSourceInfo.queryOptions());

  const updateConfig = useMutation(
    trpc.gateway.updateConfig.mutationOptions({
      onSuccess: () => toast.success("Config saved — restart gateway to apply"),
      onError: (error) =>
        toast.error(getErrorMessage(error, "Failed to save config")),
    }),
  );

  // Form state — initialised from fetched config
  const [mode, setMode] = useState<"gateway" | "security">("security");
  const [engineUrl, setEngineUrl] = useState("");
  const [port, setPort] = useState("8080");
  const [chatRoute, setChatRoute] = useState("/v1/chat/completions");
  const [policyPath, setPolicyPath] = useState("config/policy.yaml");
  const [isDirty, setIsDirty] = useState(false);

  // Populate form when config loads
  useEffect(() => {
    const d = gatewayConfig.data;
    if (!d) return;
    setMode(d.mode as "gateway" | "security");
    setEngineUrl(d.engineUrl);
    setPort(d.port);
    setChatRoute(d.chatRoute);
    setPolicyPath(d.policyPath);
    setIsDirty(false);
  }, [gatewayConfig.data]);

  function markDirty() {
    setIsDirty(true);
  }

  function handleSave() {
    updateConfig.mutate({
      mode,
      engineUrl,
      port,
      chatRoute,
      policyPath,
    });
    setIsDirty(false);
  }

  const gatewayOnline = gatewayHealth.data?.online ?? false;
  const engineOnline = engineHealth.data?.online ?? false;
  const isRefreshing =
    gatewayHealth.isFetching || engineHealth.isFetching || gatewayConfig.isFetching;
  const loading = gatewayConfig.status === "pending";
  const isGatewayApiConfig = configSourceInfo.data?.source === "gateway_api";

  return (
    <div className="flex min-h-full flex-col">
      {/* ─── Header ──────────────────────────────────────────────── */}
      <header className="sticky top-0 z-10 flex h-[52px] items-center justify-between border-b border-[var(--dev-border)] bg-[var(--dev-bg)]/95 px-6 backdrop-blur-sm">
        <div className="flex items-center gap-3">
          <span className="mono text-[10px] uppercase tracking-widest text-[var(--dev-text-mute)]">
            ~/
          </span>
          <h1 className="mono text-[13px] font-semibold text-[var(--dev-text)]">
            gateway
          </h1>
          {!configSourceInfo.isPending && (
            <span className="mono inline-flex items-center gap-1 rounded border border-[var(--dev-border)] bg-[var(--dev-panel)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--dev-text-dim)]">
              <Server size={10} aria-hidden="true" />
              {isGatewayApiConfig ? "gateway api" : "local env"}
            </span>
          )}
          {/* Live status pills */}
          <div
            className={`mono flex items-center gap-1.5 rounded border px-2 py-0.5 text-[10px] font-semibold ${
              gatewayOnline
                ? "border-[var(--dev-green)]/25 bg-[var(--dev-green)]/10 text-[var(--dev-green)]"
                : "border-[var(--dev-red,#F07A7A)]/25 bg-[var(--dev-red,#F07A7A)]/10 text-[var(--dev-red,#F07A7A)]"
            }`}
          >
            <span
              className={`h-1.5 w-1.5 rounded-full ${gatewayOnline ? "bg-[var(--dev-green)] motion-safe:animate-pulse" : "bg-[var(--dev-red,#F07A7A)]"}`}
              aria-hidden="true"
            />
            gateway
          </div>
          <div
            className={`mono flex items-center gap-1.5 rounded border px-2 py-0.5 text-[10px] font-semibold ${
              engineOnline
                ? "border-[var(--dev-green)]/25 bg-[var(--dev-green)]/10 text-[var(--dev-green)]"
                : "border-[var(--dev-border)] bg-[var(--dev-panel)] text-[var(--dev-text-mute)]"
            }`}
          >
            <span
              className={`h-1.5 w-1.5 rounded-full ${engineOnline ? "bg-[var(--dev-green)] motion-safe:animate-pulse" : "bg-[var(--dev-text-mute)]/40"}`}
              aria-hidden="true"
            />
            engine
          </div>
        </div>

        <div className="flex items-center gap-2">
          {isDirty && (
            <span className="mono rounded border border-[var(--dev-amber)]/30 bg-[var(--dev-amber)]/10 px-2 py-0.5 text-[10px] font-semibold text-[var(--dev-amber)]">
              unsaved
            </span>
          )}
          <button
            onClick={() => {
              gatewayHealth.refetch();
              engineHealth.refetch();
              gatewayConfig.refetch();
            }}
            disabled={isRefreshing}
            aria-label="Refresh"
            className="flex h-8 w-8 items-center justify-center rounded border border-[var(--dev-border)] text-[var(--dev-text-dim)] transition-colors hover:bg-[var(--dev-panel)] hover:text-[var(--dev-text)] disabled:opacity-40"
          >
            <RefreshCw
              size={13}
              aria-hidden="true"
              className={isRefreshing ? "motion-safe:animate-spin" : ""}
            />
          </button>
          <button
            onClick={handleSave}
            disabled={updateConfig.isPending || !isDirty}
            className="mono btn-press flex items-center gap-1.5 rounded px-4 py-1.5 text-[12px] font-semibold transition-colors disabled:opacity-50"
            style={{
              backgroundColor: "var(--dev-accent)",
              color: "var(--dev-bg)",
            }}
          >
            {updateConfig.isPending ? "saving…" : "save config →"}
          </button>
        </div>
      </header>

      <div className="mx-auto w-full max-w-3xl space-y-4 p-6">
        <div className="rounded-lg border border-primary/20 bg-primary/5 px-4 py-3">
          <div className="flex items-start gap-3">
            <AlertTriangle
              size={15}
              className="mt-0.5 shrink-0 text-primary"
              aria-hidden="true"
            />
            <div className="min-w-0">
              <p className="text-xs font-semibold text-primary">
                Provider routing is managed in Bifrost
              </p>
              <p className="mt-1 text-[11px] leading-relaxed text-muted-foreground">
                In this deployment, PromptShield stays inline for security policy
                and audit. Provider keys, model routing, and router governance are
                managed through the Bifrost provider/router control plane.
              </p>
              <a
                href="/bifrost/"
                className="mt-2 inline-flex items-center gap-1.5 rounded-md border border-primary/25 bg-background px-2.5 py-1.5 text-[11px] font-semibold text-primary transition-colors hover:bg-primary/10"
              >
                Open Bifrost router admin
                <ChevronRight size={11} aria-hidden="true" />
              </a>
            </div>
          </div>
        </div>

        {isGatewayApiConfig && (
          <div className="rounded-lg border border-primary/20 bg-primary/5 px-4 py-3">
            <p className="text-[11px] text-primary/90">
              Provider/model settings are managed via external gateway config endpoint.
            </p>
            {configSourceInfo.data?.gatewayConfigEndpoint && (
              <p className="mt-1 font-mono text-[10px] text-muted-foreground/60 break-all">
                {configSourceInfo.data.gatewayConfigEndpoint}
              </p>
            )}
          </div>
        )}

        {/* Overview section */}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div className="rounded-lg border border-border bg-card px-4 py-3.5">
            <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60">
              Public Inference
            </p>
            {loading ? (
              <Sk className="mt-2 h-5 w-full" />
            ) : (
              <p className="mt-2.5 font-mono text-[11px] text-muted-foreground break-all">
                /v1/*
              </p>
            )}
          </div>

          <div className="rounded-lg border border-border bg-card px-4 py-3.5">
            <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60">
              Provider Control
            </p>
            {loading ? (
              <Sk className="mt-2 h-5 w-full" />
            ) : (
              <p className="mt-2.5 text-[11px] leading-relaxed text-muted-foreground">
                Bifrost owns provider keys, key pools, fallback, and model routes.
              </p>
            )}
          </div>

          <div className="rounded-lg border border-border bg-card px-4 py-3.5">
            <p className="text-[10px] font-semibold uppercase tracking-wider text-muted-foreground/60">
              PromptShield Role
            </p>
            {loading ? (
              <Sk className="mt-2 h-5 w-full" />
            ) : (
              <div className="mt-2.5 space-y-2 text-[10px]">
                <div>
                  <p className="text-muted-foreground/60">Internal route</p>
                  <p className="font-mono text-muted-foreground break-all">
                    {`:${port}${chatRoute} -> Bifrost /v1`}
                  </p>
                </div>
                {mode === "security" && (
                  <div>
                    <p className="text-muted-foreground/60">Engine</p>
                    <p className="font-mono text-muted-foreground break-all">
                      {engineUrl || "not set"}
                    </p>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        {/* Status cards  */}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          {[
            {
              label: "Gateway",
              online: gatewayOnline,
              url: gatewayHealth.data?.url ?? "http://localhost:8080",
              latency: gatewayHealth.data?.latencyMs,
              loading: gatewayHealth.isPending,
            },
            {
              label: "Detection Engine",
              online: engineOnline,
              url: engineHealth.data?.url ?? "http://localhost:8000",
              latency: engineHealth.data?.latencyMs,
              loading: engineHealth.isPending,
              note:
                mode === "gateway" ? "Gateway mode — not in use" : undefined,
            },
          ].map((svc) => (
            <div
              key={svc.label}
              className="rounded-lg border border-border bg-card px-4 py-3.5"
            >
              <div className="flex items-start justify-between">
                <p className="text-xs font-semibold text-foreground">
                  {svc.label}
                </p>
                {svc.loading ? (
                  <Sk className="h-5 w-14 rounded-full" />
                ) : (
                  <span
                    className={`flex items-center gap-1.5 rounded-full border px-2 py-0.5 text-[10px] font-semibold ${
                      svc.online
                        ? "border-success/25 bg-success/10 text-success"
                        : "border-destructive/25 bg-destructive/10 text-destructive"
                    }`}
                  >
                    <span
                      className={`h-1.5 w-1.5 rounded-full ${svc.online ? "bg-success motion-safe:animate-pulse" : "bg-destructive"}`}
                      aria-hidden="true"
                    />
                    {svc.online ? "Online" : "Offline"}
                  </span>
                )}
              </div>
              <p className="mt-2 font-mono text-[11px] text-muted-foreground/60 break-all">
                {svc.url}
              </p>
              {svc.latency != null && (
                <p className="mt-0.5 font-mono text-[10px] tabular-nums text-muted-foreground/40">
                  {svc.latency}ms
                </p>
              )}
              {svc.note && (
                <p className="mt-1 text-[10px] text-muted-foreground/40 italic">
                  {svc.note}
                </p>
              )}
            </div>
          ))}
        </div>

        {/* Mode */}
        <SectionCard
          title="Mode"
          description="How the gateway processes requests"
        >
          {loading ? (
            <Sk className="h-16 w-full" />
          ) : (
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              {(
                [
                  {
                    id: "gateway" as const,
                    label: "Gateway Mode",
                    desc: "Transparent gateway — routing, rate limiting, token tracking. No PII scanning. Zero extra dependencies.",
                  },
                  {
                    id: "security" as const,
                    label: "Security Mode",
                    desc: "Full PII and secrets detection on every request via the detection engine.",
                  },
                ] as const
              ).map((opt) => (
                <button
                  key={opt.id}
                  onClick={() => {
                    setMode(opt.id);
                    markDirty();
                  }}
                  className={`rounded-lg border p-4 text-left transition-colors ${
                    mode === opt.id
                      ? "border-primary/40 bg-primary/5 ring-1 ring-primary/20"
                      : "border-border bg-background hover:bg-accent/40"
                  }`}
                >
                  <div className="flex items-center gap-2">
                    <span
                      className={`h-2 w-2 rounded-full ${mode === opt.id ? "bg-primary" : "bg-muted-foreground/30"}`}
                      aria-hidden="true"
                    />
                    <span className="text-xs font-semibold text-foreground">
                      {opt.label}
                    </span>
                  </div>
                  <p className="mt-1.5 text-[11px] leading-relaxed text-muted-foreground">
                    {opt.desc}
                  </p>
                </button>
              ))}
            </div>
          )}

          {mode === "security" && !loading && (
            <Field
              label="Engine URL"
              helper="The detection engine endpoint (PROMPTSHIELD_ENGINE_URL)"
            >
              <Input
                value={engineUrl}
                onChange={(e) => {
                  setEngineUrl(e.target.value);
                  markDirty();
                }}
                placeholder="http://localhost:4321"
                mono
              />
            </Field>
          )}
        </SectionCard>

        <SectionCard
          title="Bifrost Router"
          description="Provider routing, model routing, and provider API keys"
        >
          {loading ? <Sk className="h-24 w-full" /> : <BifrostControlPlaneCard />}
        </SectionCard>

        {/* Advanced */}
        <SectionCard
          title="Advanced"
          description="Port, routing, policy path"
          defaultOpen={false}
        >
          {loading ? (
            <Sk className="h-16 w-full" />
          ) : (
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <Field label="Port" helper="PROMPTSHIELD_PORT">
                <Input
                  value={port}
                  onChange={(e) => {
                    setPort(e.target.value);
                    markDirty();
                  }}
                  placeholder="8080"
                  mono
                />
              </Field>
              <Field
                label="Chat completions route"
                helper="PROMPTSHIELD_CHAT_ROUTE"
              >
                <Input
                  value={chatRoute}
                  onChange={(e) => {
                    setChatRoute(e.target.value);
                    markDirty();
                  }}
                  placeholder="/v1/chat/completions"
                  mono
                />
              </Field>
              <div className="sm:col-span-2">
                <Field
                  label="Policy file path"
                  helper="PROMPTSHIELD_POLICY_PATH — relative to gateway working directory"
                >
                  <Input
                    value={policyPath}
                    onChange={(e) => {
                      setPolicyPath(e.target.value);
                      markDirty();
                    }}
                    placeholder="config/policy.yaml"
                    mono
                  />
                </Field>
              </div>
            </div>
          )}
        </SectionCard>

        {/* Restart note */}
        <div className="flex items-start gap-2 rounded-lg border border-warning/20 bg-warning/5 px-4 py-3">
          <AlertTriangle
            size={13}
            className="mt-0.5 shrink-0 text-warning"
            aria-hidden="true"
          />
          <p className="text-[11px] leading-relaxed text-muted-foreground">
            <span className="font-semibold text-foreground">
              Restart required.
            </span>{" "}
            Config changes are written to the gateway{" "}
            <code className="rounded bg-muted/60 px-1 font-mono text-[10px]">
              .env
            </code>{" "}
            file. The gateway must be restarted to pick them up. Policy changes ({" "}
            <code className="rounded bg-muted/60 px-1 font-mono text-[10px]">
              policy.yaml
            </code>{" "}
            ) hot-reload automatically — no restart needed.
          </p>
        </div>
      </div>
    </div>
  );
}
