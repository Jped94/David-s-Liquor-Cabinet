import { downloadExport, type Credentials } from "./cellartracker.js";
import type { Env } from "./env.js";
import { HttpError, isRecord, readJSON } from "./http.js";
import { bumpVersion } from "./menu.js";

// Sync, split in two so the server stays within the free plan's CPU limit:
//
// 1. POST /api/sync/download: the server fetches the CellarTracker export
//    with the login it's given (browsers can't call CT directly) and hands
//    the raw file back. The login is used once and dropped.
// 2. The device reads the file and works out the menu (CellarKit on the
//    iPad, src/rules on the web page).
// 3. POST /api/sync/commit: the device uploads the result, which is checked
//    and stored.

/** Largest upload accepted by commit (the real collection is about 0.8 MB). */
const MAX_COMMIT_BYTES = 6 * 1024 * 1024;
/** Stored values are split into pieces this size, well under D1's limits. */
const CHUNK_CHARS = 90_000;

export async function handleDownload(request: Request): Promise<Response> {
  const body = await readJSON(request, 2048);
  if (!isRecord(body) || typeof body.username !== "string" || typeof body.password !== "string") {
    throw new HttpError(400, "Send the CellarTracker username and password.");
  }
  const credentials: Credentials = { username: body.username.trim(), password: body.password };
  if (!credentials.username || !credentials.password) {
    throw new HttpError(400, "Enter the CellarTracker username and password.");
  }
  const download = await downloadExport(credentials);
  return new Response(download.bytes, {
    headers: {
      "Content-Type": download.contentType ?? "text/csv; charset=windows-1252",
      "Cache-Control": "no-store",
    },
  });
}

export async function handleCommit(request: Request, env: Env): Promise<Response> {
  const body = await readJSON(request, MAX_COMMIT_BYTES);
  if (!isRecord(body)) throw new HttpError(400, "The sync upload should be an object.");
  const products = checkProducts(body.products);
  const bottles = checkBottles(body.bottles, new Set(products.map((p) => p.id as string)));
  const report = checkReport(body.report);

  const syncedAt = new Date().toISOString();
  const productsText = JSON.stringify(products);
  const bottlesText = JSON.stringify(bottles);
  const bottleCount = bottles.reduce((sum, b) => sum + (b.quantity as number), 0);

  const statements = [
    env.DB.prepare("DELETE FROM menu_parts"),
    ...chunks("products", productsText).map(([key, value]) =>
      env.DB.prepare("INSERT INTO menu_parts (key, value) VALUES (?, ?)").bind(key, value),
    ),
    ...chunks("bottles", bottlesText).map(([key, value]) =>
      env.DB.prepare("INSERT INTO menu_parts (key, value) VALUES (?, ?)").bind(key, value),
    ),
    env.DB.prepare("INSERT INTO menu_parts (key, value) VALUES ('syncedAt#0000', ?)").bind(syncedAt),
    env.DB.prepare(
      "INSERT INTO syncs (synced_at, product_count, bottle_count, report) VALUES (?, ?, ?, ?)",
    ).bind(syncedAt, products.length, bottleCount, JSON.stringify(report)),
    bumpVersion(env),
  ];
  if (statements.length > 45) throw new HttpError(413, "The collection is too large to store in one sync.");
  await env.DB.batch(statements);

  return Response.json({ ok: true, syncedAt, productCount: products.length, bottleCount });
}

function chunks(name: string, text: string): [string, string][] {
  const out: [string, string][] = [];
  for (let i = 0, n = 0; i < text.length; i += CHUNK_CHARS, n++) {
    out.push([`${name}#${String(n).padStart(4, "0")}`, text.slice(i, i + CHUNK_CHARS)]);
  }
  return out;
}

// MARK: Validation
// The upload comes from an admin's device, so this is a sanity check that
// keeps a buggy client from breaking the menu, not a defence against attack.

const CATEGORIES = new Set([
  "scotch", "bourbon", "rye", "americanWhiskey", "irish", "japanese", "worldWhisky",
  "rum", "agave", "brandy", "gin", "vodka", "liqueur", "other",
]);

function isID(value: unknown): value is string {
  return typeof value === "string" && /^[0-9A-Za-z_-]{1,40}$/.test(value);
}

function checkProducts(value: unknown): Record<string, unknown>[] {
  if (!Array.isArray(value) || value.length > 20_000) throw new HttpError(400, "products should be a list.");
  const seen = new Set<string>();
  for (const p of value) {
    if (
      !isRecord(p) ||
      !isID(p.id) ||
      typeof p.name !== "string" ||
      typeof p.title !== "string" ||
      typeof p.category !== "string" ||
      !CATEGORIES.has(p.category)
    ) {
      throw new HttpError(400, "A product in the upload is missing its id, name, title or category.");
    }
    if (seen.has(p.id)) throw new HttpError(400, `Product ${p.id} appears twice.`);
    seen.add(p.id);
  }
  return value;
}

function checkBottles(value: unknown, productIDs: Set<string>): Record<string, unknown>[] {
  if (!Array.isArray(value) || value.length > 100_000) throw new HttpError(400, "bottles should be a list.");
  for (const b of value) {
    if (
      !isRecord(b) ||
      typeof b.inventoryID !== "string" ||
      !isID(b.wineID) ||
      !Number.isInteger(b.quantity) ||
      (b.quantity as number) < 1
    ) {
      throw new HttpError(400, "A bottle in the upload is missing its id, product or quantity.");
    }
    if (!productIDs.has(b.wineID)) throw new HttpError(400, `Bottle ${b.inventoryID} has no product.`);
  }
  return value;
}

function checkReport(value: unknown): Record<string, unknown> {
  if (!isRecord(value) || typeof value.isInitial !== "boolean") throw new HttpError(400, "The sync report is missing.");
  for (const key of ["added", "increased", "decreased", "removed"]) {
    if (!Array.isArray(value[key])) throw new HttpError(400, `The sync report is missing "${key}".`);
  }
  return value;
}
