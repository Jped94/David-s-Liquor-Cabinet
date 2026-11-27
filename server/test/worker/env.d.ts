/// <reference path="../../node_modules/@cloudflare/vitest-plugin/types/cloudflare-test.d.ts" />
import type { D1Migration } from "cloudflare:test";
import type { Env as WorkerEnv } from "../../src/env.js";

declare global {
  namespace Cloudflare {
    interface GlobalProps {
      mainModule: typeof import("../../src/index.js");
    }
    interface Env extends WorkerEnv {
      TEST_MIGRATIONS: D1Migration[];
    }
  }
}
