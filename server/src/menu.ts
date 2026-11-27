import type { Env } from "./env.js";

// The menu is stored pre-serialized (see migrations/0001_init.sql) and
// assembled by joining strings, so serving it uses almost no CPU.

/** Current menu version, used as the ETag. Changes on every sync or edit. */
export async function menuVersion(env: Env): Promise<string> {
  const row = await env.DB.prepare("SELECT value FROM meta WHERE key = 'version'").first<{ value: string }>();
  return row?.value ?? "empty";
}

/** A statement that gives the menu a new version. */
export function bumpVersion(env: Env): D1PreparedStatement {
  return env.DB.prepare("INSERT OR REPLACE INTO meta (key, value) VALUES ('version', ?)").bind(crypto.randomUUID());
}

/**
 * `{"version":…,"syncedAt":…,"products":[…],"bottles":[…],"overrides":{…}}`.
 * Before the first sync, products and bottles are empty.
 */
export async function menuJSON(env: Env, version: string): Promise<string> {
  const [parts, overrides] = await env.DB.batch<{ key?: string; value?: string; wine_id?: string; data?: string }>([
    env.DB.prepare("SELECT key, value FROM menu_parts"),
    env.DB.prepare("SELECT wine_id, data FROM overrides ORDER BY wine_id"),
  ]);
  const part = new Map(parts.results.map((r) => [r.key!, r.value!]));
  const overrideEntries = overrides.results.map((r) => `${JSON.stringify(r.wine_id)}:${r.data}`).join(",");
  return (
    `{"version":${JSON.stringify(version)}` +
    `,"syncedAt":${JSON.stringify(part.get("syncedAt") ?? null)}` +
    `,"products":${part.get("products") ?? "[]"}` +
    `,"bottles":${part.get("bottles") ?? "[]"}` +
    `,"overrides":{${overrideEntries}}}`
  );
}
