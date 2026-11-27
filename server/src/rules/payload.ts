import { deriveBasics, type ProductBasics, type SpiritCategory } from "./enrich.js";
import { decodeBottles, type Bottle } from "./export.js";

// Builds what a sync uploads, on the device that pressed Sync (the web page
// uses this module; the iPad does the same with CellarKit). Doing it there
// keeps the server within the free plan's CPU allowance.

/** A product as stored and served in the menu. */
export interface MenuProduct extends ProductBasics {
  id: string;
  name: string;
  producer?: string;
  designation?: string;
  vineyard?: string;
  varietal?: string;
  masterVarietal?: string;
  vintage?: number;
  country?: string;
  region?: string;
  subRegion?: string;
  appellation?: string;
}

/** A bottle as stored and served in the menu. */
export interface MenuBottle {
  inventoryID: string;
  wineID: string;
  location?: string;
  bin?: string;
  quantity: number;
  size?: string;
  note?: string;
  communityScore?: number;
}

export interface SyncChange {
  id: string;
  title: string;
  subtitle?: string;
  category: SpiritCategory;
  before: number;
  after: number;
}

/** Same shape as CellarKit's SyncReport. */
export interface SyncReport {
  date: string;
  isInitial: boolean;
  productCount: number;
  bottleCount: number;
  added: SyncChange[];
  increased: SyncChange[];
  decreased: SyncChange[];
  removed: SyncChange[];
}

export interface SyncPayload {
  products: MenuProduct[];
  bottles: MenuBottle[];
  report: SyncReport;
}

/** The parts of an override that change how a product is listed. */
export interface OverrideWording {
  title?: string;
  subtitle?: string;
  category?: string;
}

/**
 * Turns a downloaded export into the upload for `POST /api/sync/commit`.
 * Pending ("on order") bottles are left out entirely.
 *
 * @param previous The menu before this sync, or `undefined` if there's never
 *   been one (the report is then marked as the first sync).
 */
export function buildSyncPayload(
  bytes: Uint8Array,
  contentType: string | null,
  previous: { products: MenuProduct[]; bottles: MenuBottle[] } | undefined,
  overrides: Record<string, OverrideWording> = {},
  now = new Date(),
): SyncPayload {
  const all = decodeBottles(bytes, contentType).filter((b) => !b.isPending);
  const bottles = all.map(menuBottle);

  const first = new Map<string, Bottle>();
  for (const bottle of all) if (!first.has(bottle.wineID)) first.set(bottle.wineID, bottle);
  const products = [...first.values()].map(menuProduct);

  return { products, bottles, report: compare(previous, { products, bottles }, overrides, now) };
}

function menuBottle(b: Bottle): MenuBottle {
  return clean({
    inventoryID: b.inventoryID,
    wineID: b.wineID,
    location: b.location,
    bin: b.bin,
    quantity: b.quantity,
    size: b.size,
    note: b.note,
    communityScore: b.communityScore,
  });
}

function menuProduct(b: Bottle): MenuProduct {
  return clean({
    id: b.wineID,
    name: b.name,
    producer: b.producer,
    designation: b.designation,
    vineyard: b.vineyard,
    varietal: b.varietal,
    masterVarietal: b.masterVarietal,
    vintage: b.vintage,
    country: b.country,
    region: b.region,
    subRegion: b.subRegion,
    appellation: b.appellation,
    ...deriveBasics(b),
  });
}

function clean<T extends object>(value: T): T {
  for (const key of Object.keys(value) as (keyof T)[]) if (value[key] === undefined) delete value[key];
  return value;
}

/** What changed between two menus, by bottle count per product. */
export function compare(
  previous: { products: MenuProduct[]; bottles: MenuBottle[] } | undefined,
  next: { products: MenuProduct[]; bottles: MenuBottle[] },
  overrides: Record<string, OverrideWording>,
  now: Date,
): SyncReport {
  const counts = (bottles: MenuBottle[]) => {
    const map = new Map<string, number>();
    for (const b of bottles) map.set(b.wineID, (map.get(b.wineID) ?? 0) + b.quantity);
    return map;
  };
  const newCounts = counts(next.bottles);
  const bottleCount = next.bottles.reduce((sum, b) => sum + b.quantity, 0);
  const base = { date: now.toISOString(), productCount: next.products.length, bottleCount };

  if (!previous) return { ...base, isInitial: true, added: [], increased: [], decreased: [], removed: [] };

  const oldCounts = counts(previous.bottles);
  const change = (p: MenuProduct, before: number, after: number): SyncChange => {
    const o = overrides[p.id] ?? {};
    const subtitle = o.subtitle !== undefined ? o.subtitle || undefined : p.subtitle;
    const result: SyncChange = {
      id: p.id,
      title: o.title || p.title,
      category: (o.category as SpiritCategory | undefined) ?? p.category,
      before,
      after,
    };
    if (subtitle !== undefined) result.subtitle = subtitle;
    return result;
  };

  const added: SyncChange[] = [];
  const increased: SyncChange[] = [];
  const decreased: SyncChange[] = [];
  for (const p of next.products) {
    const before = oldCounts.get(p.id) ?? 0;
    const after = newCounts.get(p.id) ?? 0;
    if (before === 0) added.push(change(p, 0, after));
    else if (after > before) increased.push(change(p, before, after));
    else if (after < before) decreased.push(change(p, before, after));
  }
  const nextIDs = new Set(next.products.map((p) => p.id));
  const removed = previous.products
    .filter((p) => !nextIDs.has(p.id) && (oldCounts.get(p.id) ?? 0) > 0)
    .map((p) => change(p, oldCounts.get(p.id) ?? 0, 0));

  const sorted = (list: SyncChange[]) =>
    list.sort((a, b) => a.title.localeCompare(b.title, "en", { numeric: true, sensitivity: "base" }));
  return {
    ...base,
    isInitial: false,
    added: sorted(added),
    increased: sorted(increased),
    decreased: sorted(decreased),
    removed: sorted(removed),
  };
}
