import { HttpError } from "./http.js";

// Downloads the collection from CellarTracker's export (`xlquery.asp`).
// The login is used for this one request and then dropped: it is never
// stored, logged or included in an error message. (The URL carries the
// password, so the URL is never logged either.)

export interface Credentials {
  username: string;
  password: string;
}

const ENDPOINT = "https://www.cellartracker.com/xlquery.asp";
const NOT_LOGGED_IN_MARKER = "You are currently not logged into CellarTracker";

/** Percent-encodes everything but `A–Z a–z 0–9 - . _ ~`, so `+` and `&` in passwords survive. */
function strictEncode(value: string): string {
  return encodeURIComponent(value).replace(/[!'()*]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase());
}

export function exportURL(credentials: Credentials): string {
  const query = [
    ["User", credentials.username],
    ["Password", credentials.password],
    ["Format", "csv"],
    ["Table", "List"],
    ["Location", "1"],
  ]
    .map(([k, v]) => `${strictEncode(k)}=${strictEncode(v)}`)
    .join("&");
  return `${ENDPOINT}?${query}`;
}

export interface ExportDownload {
  bytes: Uint8Array;
  contentType: string | null;
}

class Retryable extends Error {}

/** Fetches the raw export, retrying network errors and CellarTracker outages. */
export async function downloadExport(
  credentials: Credentials,
  options: { attempts?: number; delay?: (attempt: number) => Promise<void> } = {},
): Promise<ExportDownload> {
  const attempts = options.attempts ?? 3;
  const delay = options.delay ?? ((n) => new Promise((r) => setTimeout(r, n === 1 ? 1000 : 3000)));
  for (let attempt = 1; ; attempt++) {
    try {
      return await downloadOnce(credentials);
    } catch (e) {
      if (!(e instanceof Retryable) || attempt >= attempts) {
        if (e instanceof Retryable) throw new HttpError(502, e.message);
        throw e;
      }
      await delay(attempt);
    }
  }
}

async function downloadOnce(credentials: Credentials): Promise<ExportDownload> {
  let response: Response;
  try {
    response = await fetch(exportURL(credentials), {
      redirect: "manual",
      headers: { "User-Agent": "LiquorCabinet/1.0" },
      signal: AbortSignal.timeout(50_000),
    });
  } catch {
    throw new Retryable("Couldn't reach CellarTracker. Try again in a minute.");
  }

  if (response.status === 401 || response.status === 403) {
    throw new HttpError(401, "CellarTracker didn't accept the username or password.");
  }
  if (response.status >= 500) throw new Retryable("CellarTracker isn't responding properly right now. Try again later.");
  if (response.status !== 200) {
    throw new HttpError(502, `CellarTracker returned an unexpected response (HTTP ${response.status}).`);
  }

  const bytes = new Uint8Array(await response.arrayBuffer());
  // CT answers a bad login with an HTML page and HTTP 200. The marker is
  // plain ASCII, so a byte-level look is enough without decoding it all.
  const head = new TextDecoder("windows-1252").decode(bytes.subarray(0, 4096)).trimStart();
  if (head.startsWith("<")) {
    const page = new TextDecoder("windows-1252").decode(bytes);
    if (page.includes(NOT_LOGGED_IN_MARKER)) {
      throw new HttpError(401, "CellarTracker didn't accept the username or password.");
    }
    throw new Retryable("CellarTracker sent a web page instead of the collection. Try again later.");
  }
  return { bytes, contentType: response.headers.get("Content-Type") };
}
