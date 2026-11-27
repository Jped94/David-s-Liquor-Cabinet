import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { signToken, verifyToken } from "../../src/auth.js";

const call = (path: string, init?: RequestInit) => exports.default.fetch(new Request(`https://cabinet.test${path}`, init));

async function login(passcode: string, ip = "203.0.113.1"): Promise<Response> {
  return call("/api/session", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify({ passcode }),
  });
}

async function tokenFor(passcode: string): Promise<string> {
  const response = await login(passcode);
  expect(response.status).toBe(200);
  return ((await response.json()) as { token: string }).token;
}

describe("sessions", () => {
  it("gives each passcode its role, and sets a secure cookie", async () => {
    const guest = await login("guest-pass");
    expect(await guest.json()).toMatchObject({ role: "guest" });
    expect(guest.headers.get("Set-Cookie")).toMatch(/HttpOnly; Secure; SameSite=Strict/);
    expect(await (await login("admin-pass")).json()).toMatchObject({ role: "admin" });
  });

  it("refuses a wrong passcode, then rate-limits", async () => {
    for (let i = 0; i < 10; i++) expect((await login("nope", "198.51.100.7")).status).toBe(401);
    const limited = await login("guest-pass", "198.51.100.7");
    expect(limited.status).toBe(429);
    // Other addresses are unaffected.
    expect((await login("guest-pass", "198.51.100.8")).status).toBe(200);
  });

  it("rejects forged, tampered and expired tokens", async () => {
    const secret = env.SESSION_SECRET;
    const token = await signToken("guest", secret);
    expect(await verifyToken(token, secret)).toBe("guest");
    expect(await verifyToken(token, "another-secret-that-is-also-32-characters")).toBeUndefined();
    const [body, sig] = token.split(".");
    const admin = btoa(JSON.stringify({ role: "admin", exp: 9e9 })).replace(/=+$/, "");
    expect(await verifyToken(`${admin}.${sig}`, secret)).toBeUndefined();
    expect(await verifyToken(`${body}.${sig}x`, secret)).toBeUndefined();
    const old = await signToken("guest", secret, Date.now() - 400 * 24 * 3600 * 1000);
    expect(await verifyToken(old, secret)).toBeUndefined();
  });
});

describe("menu", () => {
  it("needs a passcode", async () => {
    expect((await call("/api/menu")).status).toBe(401);
  });

  it("is empty before the first sync, and supports ETags", async () => {
    const token = await tokenFor("guest-pass");
    const response = await call("/api/menu", { headers: { Authorization: `Bearer ${token}` } });
    expect(response.status).toBe(200);
    const menu = (await response.json()) as Record<string, unknown>;
    expect(menu).toMatchObject({ products: [], bottles: [], overrides: {}, syncedAt: null });

    const etag = response.headers.get("ETag")!;
    const again = await call("/api/menu", { headers: { Authorization: `Bearer ${token}`, "If-None-Match": etag } });
    expect(again.status).toBe(304);
  });

  it("works with the web page's cookie", async () => {
    const token = await tokenFor("guest-pass");
    const response = await call("/api/menu", { headers: { Cookie: `other=1; lc_session=${token}` } });
    expect(response.status).toBe(200);
  });
});

describe("without a guest passcode", () => {
  it("anyone can read the menu, but edits still need admin", async () => {
    const { default: worker } = await import("../../src/index.js");
    const open = { ...env, GUEST_PASSCODE: "" };
    const fetchOpen = (path: string, init?: RequestInit) =>
      worker.fetch(new Request(`https://cabinet.test${path}`, init), open);

    expect((await fetchOpen("/api/menu")).status).toBe(200);
    expect(await (await fetchOpen("/api/config")).json()).toEqual({ guestPasscodeRequired: false });
    expect((await fetchOpen("/api/items/1/override", { method: "PUT", body: "{}" })).status).toBe(401);
  });
});

describe("edits", () => {
  it("are admin only", async () => {
    const guest = await tokenFor("guest-pass");
    const response = await call("/api/items/123/override", {
      method: "PUT",
      headers: { Authorization: `Bearer ${guest}` },
      body: JSON.stringify({ title: "X" }),
    });
    expect(response.status).toBe(403);
  });

  it("are saved, show in the menu, change its version, and can be cleared", async () => {
    const admin = await tokenFor("admin-pass");
    const auth = { Authorization: `Bearer ${admin}` };
    const before = (await call("/api/menu", { headers: auth })).headers.get("ETag");

    const put = await call("/api/items/4833686/override", {
      method: "PUT",
      headers: auth,
      body: JSON.stringify({ title: "Aberfeldy 25", scotchStyle: "singleMalt", abv: 46, isHidden: true, junk: "dropped" }),
    });
    expect(put.status).toBe(200);

    const menuResponse = await call("/api/menu", { headers: auth });
    expect(menuResponse.headers.get("ETag")).not.toBe(before);
    const menu = (await menuResponse.json()) as { overrides: Record<string, unknown> };
    expect(menu.overrides["4833686"]).toEqual({ title: "Aberfeldy 25", scotchStyle: "singleMalt", abv: 46, isHidden: true });

    // An empty edit removes it.
    await call("/api/items/4833686/override", { method: "PUT", headers: auth, body: JSON.stringify({}) });
    const cleared = (await (await call("/api/menu", { headers: auth })).json()) as { overrides: object };
    expect(cleared.overrides).toEqual({});
  });

  it("are validated", async () => {
    const admin = await tokenFor("admin-pass");
    const bad = await call("/api/items/1/override", {
      method: "PUT",
      headers: { Authorization: `Bearer ${admin}` },
      body: JSON.stringify({ category: "moonshine" }),
    });
    expect(bad.status).toBe(400);
    expect(await bad.json()).toEqual({ error: `"category" isn't recognised.` });
  });
});
