import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { decodeBottles } from "../src/rules/export.js";
import { deriveBasics } from "../src/rules/enrich.js";

// The Swift package writes the golden file from the same sanitized export
// (see Packages/CellarKit/Tests/CellarKitTests/GoldenTests.swift). The
// TypeScript rules must reproduce it exactly.
const fixtures = fileURLToPath(new URL("../../Packages/CellarKit/Tests/CellarKitTests/Fixtures/", import.meta.url));
const csv = readFileSync(fixtures + "sample_export.csv");
const golden = JSON.parse(readFileSync(fixtures + "golden.json", "utf8")) as {
  bottles: Record<string, unknown>[];
  products: ({ id: string; name: string } & Record<string, unknown>)[];
};

describe("golden file parity with CellarKit", () => {
  const bottles = decodeBottles(new Uint8Array(csv));

  it("parses every bottle the same way", () => {
    expect(bottles).toHaveLength(golden.bottles.length);
    const keys = ["inventoryID", "wineID", "name", "location", "bin", "quantity", "isPending", "vintage", "size", "note", "communityScore"] as const;
    const picked = bottles.map((b) => {
      const out: Record<string, unknown> = {};
      for (const key of keys) if (b[key] !== undefined) out[key] = b[key];
      return out;
    });
    expect(picked).toEqual(golden.bottles);
  });

  it("derives the same fields for every product", () => {
    const firstByWine = new Map<string, (typeof bottles)[number]>();
    for (const bottle of bottles) if (!firstByWine.has(bottle.wineID)) firstByWine.set(bottle.wineID, bottle);
    expect(firstByWine.size).toBe(golden.products.length);

    const mismatches: string[] = [];
    for (const expected of golden.products) {
      const bottle = firstByWine.get(expected.id)!;
      const actual = { id: bottle.wineID, name: bottle.name, ...deriveBasics(bottle) };
      if (JSON.stringify(sortKeys(actual)) !== JSON.stringify(sortKeys(expected))) {
        mismatches.push(`${expected.name}\n  swift: ${JSON.stringify(sortKeys(expected))}\n  ts:    ${JSON.stringify(sortKeys(actual))}`);
      }
    }
    expect(mismatches.slice(0, 10).join("\n"), `${mismatches.length} products differ`).toBe("");
  });
});

function sortKeys(value: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)));
}
