import type { Env } from "./env.js";

// The menu is stored pre-serialized (see migrations/0001_init.sql and
// sync.ts) and assembled by joining strings, so serving it uses almost no
// CPU. Large values are split across rows named `products#0000`,
// `products#0001`, … and rejoined in key order.

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
    env.DB.prepare("SELECT key, value FROM menu_parts ORDER BY key"),
    env.DB.prepare("SELECT wine_id, data FROM overrides ORDER BY wine_id"),
  ]);
  const joined = new Map<string, string>();
  for (const row of parts.results) {
    const name = row.key!.split("#")[0];
    joined.set(name, (joined.get(name) ?? "") + row.value!);
  }
  const syncedAt = joined.get("syncedAt");
  const overrideEntries = overrides.results.map((r) => `${JSON.stringify(r.wine_id)}:${r.data}`).join(",");
  return (
    `{"version":${JSON.stringify(version)}` +
    `,"syncedAt":${syncedAt ? JSON.stringify(syncedAt) : "null"}` +
    `,"products":${joined.get("products") ?? "[]"}` +
    `,"bottles":${joined.get("bottles") ?? "[]"}` +
    `,"overrides":{${overrideEntries}}}`
  );
}
