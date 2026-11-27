import { HttpError, isRecord } from "./http.js";

// The owner's edits to one product. Same fields as CellarKit's ItemOverride,
// so iPads can decode them directly.

const CATEGORIES = [
  "scotch", "bourbon", "rye", "americanWhiskey", "irish", "japanese", "worldWhisky",
  "rum", "agave", "brandy", "gin", "vodka", "liqueur", "other",
];
const SCOTCH_REGIONS = ["islay", "speyside", "highlands", "lowlands", "campbeltown", "islands"];
const SCOTCH_STYLES = ["singleMalt", "blendedMalt", "blended", "singleGrain"];

const TEXT_LIMITS: Record<string, number> = { title: 200, subtitle: 300, style: 200, description: 4000 };

export interface ItemOverride {
  title?: string;
  subtitle?: string;
  category?: string;
  scotchRegion?: string;
  scotchStyle?: string;
  abv?: number;
  ageYears?: number;
  style?: string;
  description?: string;
  isHidden: boolean;
}

/** Checks an edit from a client, keeping only known fields. */
export function validateOverride(input: unknown): ItemOverride {
  if (!isRecord(input)) throw new HttpError(400, "The edit should be an object.");
  const out: ItemOverride = { isHidden: false };

  for (const [key, limit] of Object.entries(TEXT_LIMITS)) {
    const value = input[key];
    if (value === undefined || value === null) continue;
    if (typeof value !== "string" || value.length > limit) {
      throw new HttpError(400, `"${key}" should be text up to ${limit} characters.`);
    }
    (out as unknown as Record<string, unknown>)[key] = value;
  }

  const choice = (key: "category" | "scotchRegion" | "scotchStyle", allowed: string[]) => {
    const value = input[key];
    if (value === undefined || value === null) return;
    if (typeof value !== "string" || !allowed.includes(value)) throw new HttpError(400, `"${key}" isn't recognised.`);
    out[key] = value;
  };
  choice("category", CATEGORIES);
  choice("scotchRegion", SCOTCH_REGIONS);
  choice("scotchStyle", SCOTCH_STYLES);

  for (const key of ["abv", "ageYears"] as const) {
    const value = input[key];
    if (value === undefined || value === null) continue;
    if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 100) {
      throw new HttpError(400, `"${key}" should be a number from 0 to 100.`);
    }
    out[key] = value;
  }

  if (input.isHidden !== undefined && typeof input.isHidden !== "boolean") {
    throw new HttpError(400, `"isHidden" should be true or false.`);
  }
  out.isHidden = input.isHidden === true;
  return out;
}

/** True when nothing is overridden, so the edit can be deleted. */
export function isEmptyOverride(o: ItemOverride): boolean {
  return Object.keys(o).length === 1 && o.isHidden === false;
}
