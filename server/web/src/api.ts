import { buildSyncPayload, type SyncReport } from "../../src/rules/payload.js";
import type { Menu, Override } from "./model.js";

// Calls to the Worker. The session is an HttpOnly cookie set by
// POST /api/session, so the page never handles the token itself.

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function request(path: string, init: RequestInit = {}): Promise<Response> {
  let response: Response;
  try {
    response = await fetch(path, {
      ...init,
      credentials: "same-origin",
      headers: { ...(init.body ? { "Content-Type": "application/json" } : {}), ...init.headers },
    });
  } catch {
    throw new ApiError(0, "Couldn't reach the cabinet server. Check the connection and try again.");
  }
  if (!response.ok) {
    let message = `The server returned an error (HTTP ${response.status}).`;
    try {
      const body = (await response.json()) as { error?: string };
      if (body.error) message = body.error;
    } catch {
      // Not JSON: keep the generic message.
    }
    throw new ApiError(response.status, message);
  }
  return response;
}

export async function currentRole(): Promise<"admin" | "guest" | null> {
  const body = (await (await request("/api/session")).json()) as { role: "admin" | "guest" | null };
  return body.role;
}

export async function signIn(passcode: string): Promise<"admin" | "guest"> {
  const response = await request("/api/session", { method: "POST", body: JSON.stringify({ passcode }) });
  return ((await response.json()) as { role: "admin" | "guest" }).role;
}

export async function signOut(): Promise<void> {
  await request("/api/session", { method: "DELETE" });
}

export async function loadMenu(): Promise<Menu> {
  return (await (await request("/api/menu")).json()) as Menu;
}

export async function saveOverride(id: string, override: Override | null): Promise<void> {
  const path = `/api/items/${encodeURIComponent(id)}/override`;
  if (override) await request(path, { method: "PUT", body: JSON.stringify(override) });
  else await request(path, { method: "DELETE" });
}

export interface SyncHistoryEntry {
  syncedAt: string;
  productCount: number;
  bottleCount: number;
  report: SyncReport;
}

export async function syncHistory(): Promise<SyncHistoryEntry[]> {
  return (await (await request("/api/syncs")).json()) as SyncHistoryEntry[];
}

/**
 * The full sync: the server downloads the CellarTracker export with this
 * login (used once, not stored), this page works out the menu with the same
 * rules as the iPad, and uploads it for every device.
 */
export async function syncFromCellarTracker(
  username: string,
  password: string,
  current: Menu | undefined,
): Promise<SyncReport> {
  const download = await request("/api/sync/download", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
  const bytes = new Uint8Array(await download.arrayBuffer());
  const previous = current && current.products.length > 0 ? current : undefined;
  const payload = buildSyncPayload(bytes, download.headers.get("Content-Type"), previous, current?.overrides ?? {});
  await request("/api/sync/commit", { method: "POST", body: JSON.stringify(payload) });
  return payload.report;
}
