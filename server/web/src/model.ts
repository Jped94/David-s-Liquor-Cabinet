import type { MenuBottle, MenuProduct } from "../../src/rules/payload.js";
import type { ScotchRegion, ScotchStyle, SpiritCategory } from "../../src/rules/enrich.js";

// The menu as the web page sees it, and the same "effective value" rules as
// the iPad (owner edits first, then CellarTracker-derived values).

export interface Override {
  title?: string;
  subtitle?: string;
  category?: SpiritCategory;
  scotchRegion?: ScotchRegion;
  scotchStyle?: ScotchStyle;
  abv?: number;
  ageYears?: number;
  style?: string;
  description?: string;
  isHidden: boolean;
}

export interface Menu {
  version: string;
  syncedAt: string | null;
  products: MenuProduct[];
  bottles: MenuBottle[];
  overrides: Record<string, Override>;
}

export const CATEGORY_NAMES: Record<SpiritCategory, string> = {
  scotch: "Scotch",
  bourbon: "Bourbon",
  rye: "Rye",
  americanWhiskey: "American Whiskey",
  irish: "Irish Whiskey",
  japanese: "Japanese Whisky",
  worldWhisky: "World Whisky",
  rum: "Rum & Cane",
  agave: "Tequila & Mezcal",
  brandy: "Brandy & Cognac",
  gin: "Gin",
  vodka: "Vodka",
  liqueur: "Liqueurs",
  other: "Other",
};

export const REGION_NAMES: Record<ScotchRegion, string> = {
  islay: "Islay",
  speyside: "Speyside",
  highlands: "Highlands",
  lowlands: "Lowlands",
  campbeltown: "Campbeltown",
  islands: "Islands",
};

export const STYLE_NAMES: Record<ScotchStyle, string> = {
  singleMalt: "Single Malt",
  blendedMalt: "Blended Malt",
  blended: "Blended",
  singleGrain: "Single Grain",
};

/** Cover entries: bourbon and rye are part of American Whiskey. */
export function menuCategory(category: SpiritCategory): SpiritCategory {
  return category === "bourbon" || category === "rye" ? "americanWhiskey" : category;
}

// Same as CellarKit's HouseMapping.default.
const HOUSES: Record<string, string> = {
  estancia: "Estancia",
  "estancia open": "Estancia",
  "owl's perch": "Bedford",
  "open in owl's perch": "Bedford",
  cellar: "Bedford",
  basement: "Bedford",
  "194 opened": "Bedford",
};

export function houseFor(location: string | undefined): string | undefined {
  return location ? HOUSES[location.trim().toLowerCase()] : undefined;
}

export const isOpenLocation = (location: string | undefined) => (location ?? "").toLowerCase().includes("open");

/** One product with its bottles and edit applied. */
export interface Item {
  product: MenuProduct;
  bottles: MenuBottle[];
  override?: Override;
  title: string;
  subtitle?: string;
  category: SpiritCategory;
  scotchRegion?: ScotchRegion;
  scotchStyle?: ScotchStyle;
  abv?: number;
  ageYears?: number;
  style?: string;
  description?: string;
  isHidden: boolean;
  bottleCount: number;
  openCount: number;
  houses: string[];
}

export function buildItems(menu: Menu): Item[] {
  const byProduct = new Map<string, MenuBottle[]>();
  for (const b of menu.bottles) {
    const list = byProduct.get(b.wineID);
    if (list) list.push(b);
    else byProduct.set(b.wineID, [b]);
  }
  return menu.products
    .map((product) => item(product, byProduct.get(product.id) ?? [], menu.overrides[product.id]))
    .sort((a, b) => a.title.localeCompare(b.title, "en", { numeric: true, sensitivity: "base" }));
}

export function item(product: MenuProduct, bottles: MenuBottle[], override?: Override): Item {
  const o = override;
  const category = o?.category ?? product.category;
  const textOr = (edit: string | undefined, base: string | undefined) => (edit !== undefined ? edit || undefined : base);
  return {
    product,
    bottles,
    override,
    title: o?.title?.trim() || product.title,
    subtitle: textOr(o?.subtitle, product.subtitle),
    category,
    scotchRegion: category === "scotch" ? (o?.scotchRegion ?? product.scotchRegion) : undefined,
    scotchStyle: category === "scotch" ? (o?.scotchStyle ?? product.scotchStyle ?? "singleMalt") : undefined,
    abv: o?.abv ?? product.abv,
    ageYears: o?.ageYears ?? product.ageYears,
    style: textOr(o?.style, product.style),
    description: o?.description?.trim() || undefined,
    isHidden: o?.isHidden ?? false,
    bottleCount: bottles.reduce((n, b) => n + b.quantity, 0),
    openCount: bottles.filter((b) => isOpenLocation(b.location)).reduce((n, b) => n + b.quantity, 0),
    houses: [...new Set(bottles.map((b) => houseFor(b.location) ?? "Unassigned"))].sort(),
  };
}

/** "Bedford · Owl's Perch · Cabinet 1", without repeating the house name. */
export function placement(location: string | undefined, bin: string | undefined): string {
  const house = houseFor(location);
  let place = location?.trim();
  if (house && place) {
    const lower = place.toLowerCase();
    const name = house.toLowerCase();
    if (lower === name) place = undefined;
    else if (lower.startsWith(name + " ")) {
      const rest = place.slice(name.length).trim();
      place = rest.charAt(0).toUpperCase() + rest.slice(1);
    }
  }
  return [house, place, bin].filter(Boolean).join(" · ") || "No location set";
}

export function matches(item: Item, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return [item.product.name, item.title, item.subtitle, item.product.producer, item.product.region, item.style]
    .some((s) => s?.toLowerCase().includes(q));
}

export const formatNumber = (n: number) => (Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/0+$/, "").replace(/\.$/, ""));
