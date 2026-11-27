import { parseCSVRecords } from "./csv.js";

/**
 * One physical bottle: a row of the CellarTracker export (port of CellarKit's
 * BottleRecord). Prices, stores and purchase details are deliberately not
 * read, so they never reach the database.
 */
export interface Bottle {
  /** CellarTracker's per-bottle ID (`iInventory`). */
  inventoryID: string;
  /** CellarTracker's per-product ID (`iWine`). */
  wineID: string;
  name: string;
  producer?: string;
  designation?: string;
  /** For spirits CT puts the style and ABV here. */
  vineyard?: string;
  varietal?: string;
  masterVarietal?: string;
  country?: string;
  region?: string;
  subRegion?: string;
  appellation?: string;
  /** `undefined` for no vintage (CT uses 1001). */
  vintage?: number;
  size?: string;
  location?: string;
  bin?: string;
  note?: string;
  isPending: boolean;
  quantity: number;
  communityScore?: number;
  communityNoteCount?: number;
  likePercent?: number;
}

export type ExportErrorKind = "notLoggedIn" | "unexpectedHTML" | "missingColumns";

export class ExportError extends Error {
  constructor(
    readonly kind: ExportErrorKind,
    message: string,
  ) {
    super(message);
    this.name = "ExportError";
  }
}

const NOT_LOGGED_IN_MARKER = "You are currently not logged into CellarTracker";
const REQUIRED_COLUMNS = ["iWine", "Wine"];
const NON_VINTAGE = 1001;

/**
 * Decodes response bytes. CellarTracker serves windows-1252 rather than
 * UTF-8: a declared charset wins; otherwise valid UTF-8 is accepted and
 * anything else is read as windows-1252.
 */
export function decodeText(bytes: Uint8Array, contentType?: string | null): string {
  const declared = contentType ? charset(contentType) : undefined;
  const latin = ["windows-1252", "cp1252", "iso-8859-1", "latin1", "us-ascii"];
  if (declared && latin.includes(declared)) return new TextDecoder("windows-1252").decode(bytes);
  try {
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder("windows-1252").decode(bytes);
  }
}

function charset(contentType: string): string | undefined {
  for (const part of contentType.split(";")) {
    const [key, value] = part.split("=", 2);
    if (value !== undefined && key.trim().toLowerCase() === "charset") {
      return value.trim().replace(/^"|"$/g, "").toLowerCase();
    }
  }
  return undefined;
}

/** Parses decoded export text into bottles, detecting CT's HTML error pages. */
export function parseBottles(text: string): Bottle[] {
  const trimmed = text.replace(/^[\s﻿]+/, "");
  if (trimmed.startsWith("<")) {
    if (trimmed.includes(NOT_LOGGED_IN_MARKER)) {
      throw new ExportError("notLoggedIn", "CellarTracker didn't accept the username or password.");
    }
    throw new ExportError("unexpectedHTML", "CellarTracker sent a web page instead of the collection.");
  }
  const { header, records } = parseCSVRecords(text);
  const missing = REQUIRED_COLUMNS.filter((c) => !header.includes(c));
  if (missing.length > 0) {
    throw new ExportError("missingColumns", `The export is missing columns: ${missing.join(", ")}.`);
  }
  return records.map(bottleFromRow).filter((b): b is Bottle => b !== undefined);
}

export function decodeBottles(bytes: Uint8Array, contentType?: string | null): Bottle[] {
  return parseBottles(decodeText(bytes, contentType));
}

/** Builds a bottle from a CSV row keyed by header; `undefined` to skip it. */
export function bottleFromRow(row: Record<string, string>): Bottle | undefined {
  const text = (key: string): string | undefined => {
    const raw = row[key]?.trim();
    if (!raw || raw.toLowerCase() === "unknown") return undefined;
    return raw;
  };
  const int = (key: string): number | undefined => {
    const t = text(key);
    return t !== undefined && /^[+-]?\d+$/.test(t) ? Number(t) : undefined;
  };
  const double = (key: string): number | undefined => {
    const t = text(key);
    return t !== undefined && /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(t) ? Number(t) : undefined;
  };

  const wineID = text("iWine");
  const name = text("Wine");
  if (!wineID || !name) return undefined;
  // The Bottles table also lists consumed bottles (BottleState 0).
  if (text("BottleState") === "0") return undefined;
  const quantity = int("Quantity") ?? 1;
  if (quantity < 1) return undefined;

  const vintage = int("Vintage");
  const noteCount = int("CNotes");
  return dropUndefined({
    inventoryID: text("iInventory") ?? crypto.randomUUID(),
    wineID,
    name,
    producer: text("Producer"),
    designation: text("Designation"),
    vineyard: text("Vineyard"),
    varietal: text("Varietal"),
    masterVarietal: text("MasterVarietal"),
    country: text("Country"),
    region: text("Region"),
    subRegion: text("SubRegion"),
    appellation: text("Appellation"),
    vintage: vintage === NON_VINTAGE ? undefined : vintage,
    size: text("Size"),
    location: text("Location"),
    bin: text("Bin"),
    note: text("Note"),
    isPending: text("Pending") === "1",
    quantity,
    communityScore: double("CScore"),
    communityNoteCount: noteCount === 0 ? undefined : noteCount,
    likePercent: double("LikePercent"),
  });
}

function dropUndefined<T extends object>(value: T): T {
  for (const key of Object.keys(value) as (keyof T)[]) {
    if (value[key] === undefined) delete value[key];
  }
  return value;
}
