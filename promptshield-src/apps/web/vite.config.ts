import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import viteReact from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";

function getBase() {
  const raw = process.env.VITE_SERVER_URL;
  if (!raw) return "/";
  try {
    const url = new URL(raw);
    return url.pathname.endsWith("/") ? url.pathname : `${url.pathname}/`;
  } catch {
    return raw.endsWith("/") ? raw : `${raw}/`;
  }
}

// In production the dashboard is served under /admin/ via nginx, so assets
// must be referenced under that base path. Development keeps the default '/'.
const base = getBase();

export default defineConfig({
  base,
  plugins: [tsconfigPaths(), tailwindcss(), tanstackStart(), viteReact()],
  server: {
    port: 8000,
  },
});
