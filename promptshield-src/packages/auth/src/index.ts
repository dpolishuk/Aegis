import { createDb } from "@promptshield/db";
import * as schema from "@promptshield/db/schema/auth";
import { env } from "@promptshield/env/server";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";

export function createAuth() {
  const db = createDb();

  return betterAuth({
    database: drizzleAdapter(db, {
      provider: "pg",
      schema: schema,
    }),
    trustedOrigins: [env.CORS_ORIGIN],
    emailAndPassword: {
      enabled: true,
    },
    secret: env.BETTER_AUTH_SECRET,
    baseURL: env.BETTER_AUTH_URL,
    advanced: {
      crossSubDomainCookies: { enabled: false },
      defaultCookieAttributes: {
        sameSite: "lax",
        // Secure cookies only when served over HTTPS. This lets the dashboard
        // work on plain HTTP (e.g. local/Lima) without disabling NODE_ENV=production.
        secure: env.BETTER_AUTH_URL.startsWith("https://"),
        httpOnly: true,
      },
    },
    plugins: [],
  });
}

export const auth = createAuth();
