import type { Bottle } from "./export.js";

// Port of CellarKit's RuleEnricher, MenuWording and agave grouping. The
// golden-file test keeps it identical to the Swift version.

export type SpiritCategory =
  | "scotch"
  | "bourbon"
  | "rye"
  | "americanWhiskey"
  | "irish"
  | "japanese"
  | "worldWhisky"
  | "rum"
  | "agave"
  | "brandy"
  | "gin"
  | "vodka"
  | "liqueur"
  | "other";

export type ScotchRegion = "islay" | "speyside" | "highlands" | "lowlands" | "campbeltown" | "islands";
export type ScotchStyle = "singleMalt" | "blendedMalt" | "blended" | "singleGrain";
export type AgaveKind = "Tequila" | "Mezcal" | "Other Agave";

/** Everything derived from a product's CellarTracker data. */
export interface ProductBasics {
  category: SpiritCategory;
  scotchRegion?: ScotchRegion;
  scotchStyle?: ScotchStyle;
  agaveKind?: AgaveKind;
  abv?: number;
  ageYears?: number;
  style?: string;
  isCaskStrength: boolean;
  isSingleCask: boolean;
  title: string;
  subtitle?: string;
}

export function deriveBasics(bottle: Bottle): ProductBasics {
  const category = categoryFor(bottle);
  const haystack = [bottle.name, bottle.designation, bottle.vineyard]
    .filter((s): s is string => s !== undefined)
    .join(" ")
    .toLowerCase();
  const wording = menuWording(bottle);
  const basics: ProductBasics = {
    category,
    scotchRegion: category === "scotch" ? scotchRegionFor(bottle) : undefined,
    scotchStyle: category === "scotch" ? scotchStyleFor(bottle) : undefined,
    agaveKind: category === "agave" ? agaveKindFor(bottle) : undefined,
    abv: abvFor(bottle),
    ageYears: ageYearsFor(bottle),
    style: styleFromVineyard(bottle.vineyard),
    isCaskStrength: ["cask strength", "barrel proof", "barrel strength", "cask straight", "full proof"].some((k) =>
      haystack.includes(k),
    ),
    isSingleCask: ["single cask", "single barrel"].some((k) => haystack.includes(k)),
    title: wording.title,
    subtitle: wording.subtitle,
  };
  for (const key of Object.keys(basics) as (keyof ProductBasics)[]) {
    if (basics[key] === undefined) delete basics[key];
  }
  return basics;
}

/** Words of a lowercased name, split on anything that isn't a letter. */
function wordsOf(text: string): Set<string> {
  return new Set(text.split(/[^\p{L}]+/u).filter(Boolean));
}

const lower = (s: string | undefined) => s?.toLowerCase() ?? "";

// MARK: Category

const WHISKY_GRAINS = new Set(["malt", "grain", "rye", "wheat", "corn"]);
const BRANDY_VARIETALS = new Set([
  "ugni blanc",
  "trebbiano",
  "apple",
  "pear",
  "grape blend",
  "pinot noir",
  "folle blanche",
  "colombard",
]);

export function categoryFor(bottle: Bottle): SpiritCategory {
  const name = bottle.name.toLowerCase();
  const words = wordsOf(name);
  const varietal = lower(bottle.varietal);
  const master = lower(bottle.masterVarietal);
  const country = lower(bottle.country);
  const region = lower(bottle.region);

  const whiskyCategory = (): SpiritCategory => {
    if (name.includes("scotch") || (country === "united kingdom" && region === "scotland")) return "scotch";
    if (name.includes("bourbon")) return "bourbon";
    if (words.has("rye") || varietal === "rye") return "rye";
    if (country === "ireland") return "irish";
    if (country === "japan") return "japanese";
    if (country === "usa") return "americanWhiskey";
    return "worldWhisky";
  };
  const nameHas = (keywords: string[]) => keywords.some((k) => words.has(k));

  // 1. The name says whisky.
  if (name.includes("whisk") || name.includes("bourbon") || name.includes("scotch")) return whiskyCategory();

  // 2. The name names another spirit; this wins over the varietal.
  if (nameHas(["tequila", "mezcal", "raicilla", "sotol", "bacanora"])) return "agave";
  if (nameHas(["rum", "rhum", "ron", "cachaça", "cachaca", "agricole", "clairin"])) return "rum";
  if (nameHas(["cognac", "armagnac", "brandy", "calvados", "marc", "grappa", "pisco"])) return "brandy";
  if (nameHas(["gin", "genever"])) return "gin";
  if (nameHas(["vodka"])) return "vodka";
  if (nameHas(["liqueur", "amaro", "vermouth", "aperitivo", "bitters", "cordial"])) return "liqueur";

  // 3. Fall back to the base ingredient.
  if (varietal === "agave") return "agave";
  if (varietal === "molasses" || varietal === "sugar cane") return "rum";
  if (BRANDY_VARIETALS.has(varietal) || BRANDY_VARIETALS.has(master)) return "brandy";
  if (WHISKY_GRAINS.has(varietal)) return whiskyCategory();
  return "other";
}

// MARK: Scotch

const REGION_KEYWORDS: [ScotchRegion, string[]][] = [
  ["islay", ["islay"]],
  ["campbeltown", ["campbeltown"]],
  ["lowlands", ["lowland"]],
  ["islands", ["orkney", "skye", "mull", "jura", "arran", "lewis", "islands"]],
  ["speyside", ["speyside", "craigellachie", "dufftown", "easter elchies", "rothes", "elgin", "keith", "aberlour"]],
  ["highlands", ["highland"]],
];

/** SubRegion, then Appellation, then the name. */
export function scotchRegionFor(bottle: Bottle): ScotchRegion | undefined {
  for (const field of [bottle.subRegion, bottle.appellation, bottle.name]) {
    if (field === undefined) continue;
    const text = field.toLowerCase();
    for (const [region, keywords] of REGION_KEYWORDS) {
      if (keywords.some((k) => text.includes(k))) return region;
    }
  }
  return undefined;
}

const BLENDED_BRANDS = [
  "johnnie walker",
  "chivas regal",
  "dewar's",
  "famous grouse",
  "ballantine's",
  "cutty sark",
  "j&b",
  "teacher's",
  "grant's",
  "whyte & mackay",
  "royal salute",
  "buchanan's",
  "haig",
];
const BLENDED_MALT_BRANDS = ["monkey shoulder", "big peat", "scallywag", "timorous beastie", "rock oyster", "sheep dip"];

/** Anything that doesn't say otherwise is taken to be a single malt. */
export function scotchStyleFor(bottle: Bottle): ScotchStyle {
  const text = [bottle.name, bottle.producer, bottle.vineyard]
    .filter((s): s is string => s !== undefined)
    .join(" ")
    .toLowerCase();
  if (text.includes("single grain")) return "singleGrain";
  if (
    ["blended malt", "vatted malt", "pure malt"].some((k) => text.includes(k)) ||
    BLENDED_MALT_BRANDS.some((k) => text.includes(k))
  ) {
    return "blendedMalt";
  }
  if (text.includes("single malt")) return "singleMalt";
  if (text.includes("blend") || BLENDED_BRANDS.some((k) => text.includes(k))) return "blended";
  return "singleMalt";
}

// MARK: Agave

export function agaveKindFor(bottle: Bottle): AgaveKind {
  const name = bottle.name.toLowerCase();
  const words = wordsOf(name);
  const region = lower(bottle.region);
  const subRegion = lower(bottle.subRegion);
  if (name.includes("mezcal") || region === "oaxaca") return "Mezcal";
  if (
    name.includes("tequila") ||
    region === "jalisco" ||
    subRegion === "tequila" ||
    ["blanco", "reposado", "añejo", "anejo", "joven", "plata"].some((w) => words.has(w))
  ) {
    return "Tequila";
  }
  return "Other Agave";
}

// MARK: ABV and age

// Patterns start with `(?:^|[^\d.])` so they can't begin matching in the
// middle of a longer number (e.g. "13" inside "2013").

export function abvFor(bottle: Bottle): number | undefined {
  const fields = [bottle.name, bottle.vineyard].filter((s): s is string => s !== undefined);
  for (const text of fields) {
    const value = lastPercentage(text);
    if (value !== undefined) return value;
  }
  for (const text of fields) {
    const proof = lastProof(text);
    if (proof !== undefined) return proof / 2;
  }
  return undefined;
}

function lastInRange(text: string, pattern: RegExp, min: number, max: number): number | undefined {
  const values = [...text.matchAll(pattern)].map((m) => Number(m[1]));
  return values.filter((v) => v >= min && v <= max).at(-1);
}

const lastPercentage = (text: string) => lastInRange(text, /(?:^|[^\d.])(\d{1,2}(?:\.\d{1,2})?)\s?%/g, 15, 80);
const lastProof = (text: string) => lastInRange(text, /(?:^|[^\d.])(\d{2,3}(?:\.\d{1,2})?)\s?proof/gi, 30, 160);

export function ageYearsFor(bottle: Bottle): number | undefined {
  const pattern = /(?:^|[^\d.])(\d{1,2}(?:\.\d{1,2})?)[\s-]*(?:years?|yrs?|yo)\b/i;
  for (const text of [bottle.designation, bottle.name]) {
    if (text === undefined) continue;
    const match = pattern.exec(text);
    if (!match) continue;
    const years = Number(match[1]);
    if (years >= 1 && years <= 80) return years;
  }
  return undefined;
}

// MARK: Style

const ABV_TEXT = /,?\s*\d{1,2}(?:\.\d{1,2})?\s?%/;

/** "Single Malt Scotch Whisky, 59.7%, 585 bottles" → "Single Malt Scotch Whisky". */
export function styleFromVineyard(vineyard: string | undefined): string | undefined {
  if (vineyard === undefined) return undefined;
  let text = vineyard;
  const percent = ABV_TEXT.exec(text);
  if (percent) text = text.slice(0, percent.index);
  text = trimChars(text, " \t,");
  return /\p{L}/u.test(text) ? text : undefined;
}

// MARK: Opened

/** "Open in Owl's perch", "194 Opened", "Estancia Open". */
export function isOpened(bottle: Bottle): boolean {
  return lower(bottle.location).includes("open");
}

// MARK: Menu wording

/** Expression names up to this length are folded into the title. */
const SHORT_REST_LIMIT = 28;

/**
 * The menu's two lines: producer plus age statement or a short expression
 * name ("Ardbeg 22 Year Old"), then the rest of the name and the vintage.
 */
export function menuWording(bottle: Bottle): { title: string; subtitle?: string } {
  const vintageText = bottle.vintage !== undefined ? `Vintage ${bottle.vintage}` : undefined;
  const producer = bottle.producer;
  if (producer === undefined) return { title: bottle.name, subtitle: vintageText };

  let rest = bottle.designation ?? "";
  let ageText: string | undefined;
  const age = ageStatement(rest);
  if (age) {
    ageText = age.text;
    rest = rest.slice(0, age.start) + rest.slice(age.end);
  }
  rest = tidy(rest);

  let title = producer;
  if (ageText !== undefined) {
    title += " " + ageText;
  } else if (rest !== "" && graphemeCount(rest) <= SHORT_REST_LIMIT) {
    title += " " + rest;
    rest = "";
  }

  // Don't repeat a year the expression name already mentions.
  const vintage = bottle.vintage !== undefined && rest.includes(String(bottle.vintage)) ? undefined : vintageText;
  const parts = [rest === "" ? undefined : rest, vintage].filter((s): s is string => s !== undefined);
  return { title, subtitle: parts.length > 0 ? parts.join(" · ") : undefined };
}

/** "22 Year Old", "18yrs", "10 YO" → "N Year Old", with its position. */
function ageStatement(text: string): { text: string; start: number; end: number } | undefined {
  const pattern = /(?:^|[^\d.])((\d{1,2}(?:\.\d)?)[\s-]*(?:years?[\s-]+old|years?|yrs?|yo)\b)/di;
  const match = pattern.exec(text);
  const span = match?.indices?.[1];
  if (!match || !span) return undefined;
  return { text: `${match[2]} Year Old`, start: span[0], end: span[1] };
}

/** Collapses spaces and trims separators left after removing the age. */
function tidy(input: string): string {
  let text = input;
  const abv = ABV_TEXT.exec(text);
  if (abv) text = text.slice(0, abv.index) + text.slice(abv.index + abv[0].length);
  const collapsed = text.split(/\s+/u).filter(Boolean).join(" ");
  return trimChars(collapsed, " ,-–—·:");
}

function trimChars(text: string, chars: string): string {
  let start = 0;
  let end = text.length;
  while (start < end && chars.includes(text[start])) start++;
  while (end > start && chars.includes(text[end - 1])) end--;
  return text.slice(start, end);
}

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
function graphemeCount(text: string): number {
  return [...segmenter.segment(text)].length;
}
