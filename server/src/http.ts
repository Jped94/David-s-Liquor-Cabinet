/** A JSON response. */
export function json(body: unknown, init: ResponseInit = {}): Response {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", headers.get("Cache-Control") ?? "no-store");
  return new Response(JSON.stringify(body), { ...init, headers });
}

/** An error response with a message that's safe to show to people. */
export function error(status: number, message: string, headers?: HeadersInit): Response {
  return json({ error: message }, { status, headers });
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

/** Reads a JSON body, refusing anything over `maxBytes`. */
export async function readJSON(request: Request, maxBytes = 64 * 1024): Promise<unknown> {
  const length = Number(request.headers.get("Content-Length") ?? "0");
  if (length > maxBytes) throw new HttpError(413, "That request is too large.");
  const text = await request.text();
  if (text.length > maxBytes) throw new HttpError(413, "That request is too large.");
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(400, "The request wasn't valid JSON.");
  }
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
