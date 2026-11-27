import type { Env, Role } from "./env.js";
import { HttpError } from "./http.js";

// Shared passcodes are exchanged for a signed session token. iPads keep the
// token in the Keychain and send it as a Bearer token; the web page gets it
// as an HttpOnly cookie.

export const COOKIE_NAME = "lc_session";
/** Sessions last a year; then the device asks for the passcode again. */
export const SESSION_SECONDS = 365 * 24 * 60 * 60;

const FAILURE_LIMIT = 10;
const FAILURE_WINDOW_SECONDS = 15 * 60;

interface TokenPayload {
  role: Role;
  /** Expiry, in seconds since 1970. */
  exp: number;
}

const encoder = new TextEncoder();

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64url(text: string): Uint8Array {
  const binary = atob(text.replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  if (!secret || secret.length < 32) throw new Error("SESSION_SECRET must be at least 32 characters.");
  return crypto.subtle.importKey("raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
    "verify",
  ]);
}

export async function signToken(role: Role, secret: string, now = Date.now()): Promise<string> {
  const payload: TokenPayload = { role, exp: Math.floor(now / 1000) + SESSION_SECONDS };
  const body = base64url(encoder.encode(JSON.stringify(payload)));
  const signature = await crypto.subtle.sign("HMAC", await hmacKey(secret), encoder.encode(body));
  return `${body}.${base64url(new Uint8Array(signature))}`;
}

/** The token's role, or `undefined` if it's missing, forged or expired. */
export async function verifyToken(token: string, secret: string, now = Date.now()): Promise<Role | undefined> {
  const [body, signature, extra] = token.split(".");
  if (!body || !signature || extra !== undefined) return undefined;
  try {
    const valid = await crypto.subtle.verify(
      "HMAC",
      await hmacKey(secret),
      fromBase64url(signature),
      encoder.encode(body),
    );
    if (!valid) return undefined;
    const payload = JSON.parse(new TextDecoder().decode(fromBase64url(body))) as TokenPayload;
    if (payload.role !== "guest" && payload.role !== "admin") return undefined;
    if (typeof payload.exp !== "number" || payload.exp * 1000 < now) return undefined;
    return payload.role;
  } catch {
    return undefined;
  }
}

/** Compares two strings without leaking where they differ through timing. */
async function sameSecret(a: string, b: string, key: CryptoKey): Promise<boolean> {
  const [x, y] = await Promise.all([
    crypto.subtle.sign("HMAC", key, encoder.encode(a)),
    crypto.subtle.sign("HMAC", key, encoder.encode(b)),
  ]);
  const ax = new Uint8Array(x);
  const by = new Uint8Array(y);
  let diff = 0;
  for (let i = 0; i < ax.length; i++) diff |= ax[i] ^ by[i];
  return diff === 0;
}

/** Which role a passcode grants, if any. The admin passcode wins a tie. */
export async function roleForPasscode(passcode: string, env: Env): Promise<Role | undefined> {
  const key = await hmacKey(env.SESSION_SECRET);
  if (env.ADMIN_PASSCODE && (await sameSecret(passcode, env.ADMIN_PASSCODE, key))) return "admin";
  if (env.GUEST_PASSCODE && (await sameSecret(passcode, env.GUEST_PASSCODE, key))) return "guest";
  return undefined;
}

/** The request's role from its Bearer token or session cookie. */
export async function requestRole(request: Request, env: Env): Promise<Role | undefined> {
  const header = request.headers.get("Authorization");
  const bearer = header?.startsWith("Bearer ") ? header.slice(7).trim() : undefined;
  const token = bearer ?? cookie(request, COOKIE_NAME);
  return token ? verifyToken(token, env.SESSION_SECRET) : undefined;
}

/** Throws 401/403 unless the request has at least `needed`. */
export async function requireRole(request: Request, env: Env, needed: Role): Promise<Role> {
  const role = await requestRole(request, env);
  // Without a guest passcode, reading is open to anyone.
  if (needed === "guest" && !env.GUEST_PASSCODE) return role ?? "guest";
  if (!role) throw new HttpError(401, "Enter the passcode to continue.");
  if (needed === "admin" && role !== "admin") throw new HttpError(403, "That needs the admin passcode.");
  return role;
}

function cookie(request: Request, name: string): string | undefined {
  for (const part of (request.headers.get("Cookie") ?? "").split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return rest.join("=");
  }
  return undefined;
}

export function sessionCookie(token: string): string {
  return `${COOKIE_NAME}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${SESSION_SECONDS}`;
}

export const clearedCookie = `${COOKIE_NAME}=; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=0`;

// MARK: Rate limiting

function clientAddress(request: Request): string {
  return request.headers.get("CF-Connecting-IP") ?? "unknown";
}

/** Throws 429 if this address has failed too often recently. */
export async function checkRateLimit(request: Request, env: Env, now = Date.now()): Promise<void> {
  const row = await env.DB.prepare("SELECT window_start, failures FROM login_attempts WHERE ip = ?")
    .bind(clientAddress(request))
    .first<{ window_start: number; failures: number }>();
  const nowSeconds = Math.floor(now / 1000);
  if (row && nowSeconds - row.window_start < FAILURE_WINDOW_SECONDS && row.failures >= FAILURE_LIMIT) {
    throw new HttpError(429, "Too many wrong passcodes. Try again in 15 minutes.");
  }
}

export async function recordFailure(request: Request, env: Env, now = Date.now()): Promise<void> {
  const nowSeconds = Math.floor(now / 1000);
  await env.DB.prepare(
    `INSERT INTO login_attempts (ip, window_start, failures) VALUES (?1, ?2, 1)
     ON CONFLICT(ip) DO UPDATE SET
       failures = CASE WHEN ?2 - window_start >= ?3 THEN 1 ELSE failures + 1 END,
       window_start = CASE WHEN ?2 - window_start >= ?3 THEN ?2 ELSE window_start END`,
  )
    .bind(clientAddress(request), nowSeconds, FAILURE_WINDOW_SECONDS)
    .run();
}

export async function clearFailures(request: Request, env: Env): Promise<void> {
  await env.DB.prepare("DELETE FROM login_attempts WHERE ip = ?").bind(clientAddress(request)).run();
}
