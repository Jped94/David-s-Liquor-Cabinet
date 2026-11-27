import { exports } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";

const call = (path: string, init?: RequestInit) => exports.default.fetch(new Request(`https://cabinet.test${path}`, init));

async function adminAuth(): Promise<Record<string, string>> {
  const response = await call("/api/session", {
    method: "POST",
    headers: { "CF-Connecting-IP": "192.0.2.50" },
    body: JSON.stringify({ passcode: "admin-pass" }),
  });
  const { token } = (await response.json()) as { token: string };
  return { Authorization: `Bearer ${token}` };
}

afterEach(() => vi.restoreAllMocks());

describe("sync download", () => {
  it("is admin only", async () => {
    const response = await call("/api/sync/download", { method: "POST", body: "{}" });
    expect(response.status).toBe(401);
  });

  it("passes the export through, with the login strictly encoded and never echoed", async () => {
    const csv = new TextEncoder().encode('"iWine","Wine"\r\n"1","Test"\r\n');
    const fetchSpy = vi
      .spyOn(globalThis, "fetch")
      .mockImplementation(async () => new Response(csv, { headers: { "Content-Type": "text/csv; charset=windows-1252" } }));

    const response = await call("/api/sync/download", {
      method: "POST",
      headers: await adminAuth(),
      body: JSON.stringify({ username: "david", password: "p+ss&word=1" }),
    });
    expect(response.status).toBe(200);
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(csv);
    const url = String(fetchSpy.mock.calls[0][0]);
    expect(url).toContain("User=david&Password=p%2Bss%26word%3D1&Format=csv&Table=List&Location=1");
  });

  it("reports a bad CellarTracker login without retrying", async () => {
    const page = "<html><body>You are currently not logged into CellarTracker.</body></html>";
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async () => new Response(page));
    const response = await call("/api/sync/download", {
      method: "POST",
      headers: await adminAuth(),
      body: JSON.stringify({ username: "david", password: "wrong-secret" }),
    });
    expect(response.status).toBe(401);
    const text = await response.text();
    expect(text).toContain("didn't accept the username or password");
    expect(text).not.toContain("wrong-secret");
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });
});

describe("sync commit", () => {
  const report = { date: "2026-11-27T00:00:00Z", isInitial: true, productCount: 0, bottleCount: 0, added: [], increased: [], decreased: [], removed: [] };

  it("stores a large collection and serves it back intact", async () => {
    // Bigger than the real collection, to exercise splitting into chunks.
    const products = Array.from({ length: 3000 }, (_, i) => ({
      id: String(100000 + i),
      name: `Distillery ${i} 12 Year Old Single Malt Scotch Whisky, 46% — «ünïcode»`,
      title: `Distillery ${i} 12 Year Old`,
      category: "scotch",
      style: "Single Malt Scotch Whisky",
    }));
    const bottles = products.map((p, i) => ({ inventoryID: `b${i}`, wineID: p.id, quantity: 1 + (i % 3), location: "Owl's Perch" }));
    const auth = await adminAuth();

    const commit = await call("/api/sync/commit", { method: "POST", headers: auth, body: JSON.stringify({ products, bottles, report }) });
    expect(commit.status).toBe(200);
    expect(await commit.json()).toMatchObject({ productCount: 3000, bottleCount: 6000 });

    const menu = (await (await call("/api/menu", { headers: auth })).json()) as { products: unknown[]; bottles: unknown[]; syncedAt: string };
    expect(menu.products).toEqual(products);
    expect(menu.bottles).toEqual(bottles);
    expect(menu.syncedAt).toMatch(/^\d{4}-/);

    const history = (await (await call("/api/syncs", { headers: auth })).json()) as { productCount: number }[];
    expect(history[0].productCount).toBe(3000);
  });

  it("rejects an upload that would break the menu", async () => {
    const auth = await adminAuth();
    const orphan = await call("/api/sync/commit", {
      method: "POST",
      headers: auth,
      body: JSON.stringify({
        products: [{ id: "1", name: "A", title: "A", category: "scotch" }],
        bottles: [{ inventoryID: "b", wineID: "2", quantity: 1 }],
        report,
      }),
    });
    expect(orphan.status).toBe(400);
    const badCategory = await call("/api/sync/commit", {
      method: "POST",
      headers: auth,
      body: JSON.stringify({ products: [{ id: "1", name: "A", title: "A", category: "beer" }], bottles: [], report }),
    });
    expect(badCategory.status).toBe(400);
  });
});
