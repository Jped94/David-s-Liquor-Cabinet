import path from "node:path";
import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    projects: [
      {
        // Pure rules tests, in Node (they read the fixture files from disk).
        test: { name: "rules", include: ["test/*.test.ts"], environment: "node" },
      },
      {
        // API tests, inside the local Workers runtime with a fresh D1.
        plugins: [
          cloudflareTest(async () => ({
            wrangler: { configPath: "./wrangler.jsonc" },
            miniflare: {
              bindings: {
                GUEST_PASSCODE: "guest-pass",
                ADMIN_PASSCODE: "admin-pass",
                SESSION_SECRET: "test-secret-that-is-at-least-32-characters-long",
                TEST_MIGRATIONS: await readD1Migrations(path.join(import.meta.dirname, "migrations")),
              },
            },
          })),
        ],
        test: { name: "worker", include: ["test/worker/*.test.ts"], setupFiles: ["test/worker/setup.ts"] },
      },
    ],
  },
});
