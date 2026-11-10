import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// base "/admin/" because FastAPI serves the build at /admin/.
// `npm run dev` proxies /api to the backend so no CORS or IPs are needed.
export default defineConfig({
  base: "/admin/",
  plugins: [react()],
  server: { proxy: { "/api": "http://127.0.0.1:8000" } },
  build: { outDir: "dist", emptyOutDir: true },
});
