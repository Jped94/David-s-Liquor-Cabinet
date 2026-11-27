import {
  checkRateLimit,
  clearFailures,
  clearedCookie,
  recordFailure,
  requireRole,
  roleForPasscode,
  sessionCookie,
  signToken,
} from "./auth.js";
import type { Env } from "./env.js";
import { error, HttpError, isRecord, json, readJSON } from "./http.js";
import { bumpVersion, menuJSON, menuVersion } from "./menu.js";
import { isEmptyOverride, validateOverride } from "./overrides.js";
import { handleCommit, handleDownload } from "./sync.js";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (e) {
      if (e instanceof HttpError) return error(e.status, e.message);
      // Never echo internal errors: they could include request details.
      console.error("Unhandled error", e instanceof Error ? e.name : typeof e);
      return error(500, "Something went wrong on the server.");
    }
  },
} satisfies ExportedHandler<Env>;

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  const method = request.method;

  if (path === "/api/session" && method === "POST") return createSession(request, env);
  if (path === "/api/session" && method === "DELETE") {
    return json({ ok: true }, { headers: { "Set-Cookie": clearedCookie } });
  }
  if (path === "/api/menu" && method === "GET") return getMenu(request, env);
  if (path === "/api/config" && method === "GET") {
    // Tells clients whether reading the menu needs a passcode.
    return json({ guestPasscodeRequired: Boolean(env.GUEST_PASSCODE) });
  }
  if (path === "/api/syncs" && method === "GET") return getSyncs(request, env);
  if (path === "/api/sync/download" && method === "POST") {
    await requireRole(request, env, "admin");
    return handleDownload(request);
  }
  if (path === "/api/sync/commit" && method === "POST") {
    await requireRole(request, env, "admin");
    return handleCommit(request, env);
  }

  const item = path.match(/^\/api\/items\/([0-9A-Za-z_-]{1,40})\/override$/);
  if (item && (method === "PUT" || method === "DELETE")) return putOverride(request, env, item[1], method);

  if (path.startsWith("/api/")) return error(404, "Not found.");
  return error(404, "Not found.");
}

/** Passcode → session token (JSON for iPads, cookie for the web page). */
async function createSession(request: Request, env: Env): Promise<Response> {
  await checkRateLimit(request, env);
  const body = await readJSON(request, 1024);
  const passcode = isRecord(body) && typeof body.passcode === "string" ? body.passcode : "";
  const role = passcode ? await roleForPasscode(passcode, env) : undefined;
  if (!role) {
    await recordFailure(request, env);
    return error(401, "That passcode isn't right.");
  }
  await clearFailures(request, env);
  const token = await signToken(role, env.SESSION_SECRET);
  return json({ token, role }, { headers: { "Set-Cookie": sessionCookie(token) } });
}

async function getMenu(request: Request, env: Env): Promise<Response> {
  await requireRole(request, env, "guest");
  const version = await menuVersion(env);
  const etag = `"${version}"`;
  const headers = { ETag: etag, "Cache-Control": "private, no-cache" };
  if (request.headers.get("If-None-Match") === etag) return new Response(null, { status: 304, headers });
  const body = await menuJSON(env, version);
  return new Response(body, { headers: { ...headers, "Content-Type": "application/json; charset=utf-8" } });
}

async function putOverride(request: Request, env: Env, wineID: string, method: string): Promise<Response> {
  await requireRole(request, env, "admin");
  const override = method === "DELETE" ? undefined : validateOverride(await readJSON(request, 16 * 1024));
  const write =
    override === undefined || isEmptyOverride(override)
      ? env.DB.prepare("DELETE FROM overrides WHERE wine_id = ?").bind(wineID)
      : env.DB.prepare(
          `INSERT INTO overrides (wine_id, data, updated_at) VALUES (?1, ?2, ?3)
           ON CONFLICT(wine_id) DO UPDATE SET data = ?2, updated_at = ?3`,
        ).bind(wineID, JSON.stringify(override), new Date().toISOString());
  await env.DB.batch([write, bumpVersion(env)]);
  return json({ ok: true, override: override && !isEmptyOverride(override) ? override : null });
}

async function getSyncs(request: Request, env: Env): Promise<Response> {
  await requireRole(request, env, "admin");
  const { results } = await env.DB.prepare(
    "SELECT synced_at, product_count, bottle_count, report FROM syncs ORDER BY id DESC LIMIT 20",
  ).all<{ synced_at: string; product_count: number; bottle_count: number; report: string }>();
  return json(
    results.map((r) => ({
      syncedAt: r.synced_at,
      productCount: r.product_count,
      bottleCount: r.bottle_count,
      report: JSON.parse(r.report),
    })),
  );
}
