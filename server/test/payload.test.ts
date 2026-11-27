import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { buildSyncPayload } from "../src/rules/payload.js";

const fixture = fileURLToPath(
  new URL("../../Packages/CellarKit/Tests/CellarKitTests/Fixtures/sample_export.csv", import.meta.url),
);
const bytes = new Uint8Array(readFileSync(fixture));

describe("sync payload", () => {
  const first = buildSyncPayload(bytes, "text/csv; charset=windows-1252", undefined);

  it("leaves out pending bottles", () => {
    expect(first.products).toHaveLength(784);
    expect(first.bottles.reduce((n, b) => n + b.quantity, 0)).toBe(1639);
    expect(first.report).toMatchObject({ isInitial: true, productCount: 784, bottleCount: 1639 });
  });

  it("keeps guests' view free of prices and stores", () => {
    const text = JSON.stringify(first);
    for (const key of ["price", "Price", "value", "storeName", "purchaseDate"]) expect(text).not.toContain(`"${key}"`);
  });

  it("reports what changed since the previous menu", () => {
    const lagavulinID = first.products.find((p) => p.name.startsWith("Lagavulin"))!.id;
    const previous = {
      // One product didn't exist, one had an extra bottle, one is gone now.
      products: [
        ...first.products.filter((p) => p.id !== first.products[0].id),
        { ...first.products[1], id: "999999", title: "Long Gone 12 Year Old" },
      ],
      bottles: [
        ...first.bottles.filter((b) => b.wineID !== first.products[0].id),
        { inventoryID: "x1", wineID: lagavulinID, quantity: 5 },
        { inventoryID: "x2", wineID: "999999", quantity: 2 },
      ],
    };
    const { report } = buildSyncPayload(bytes, null, previous, { [lagavulinID]: { title: "Lagavulin (edited)" } });
    expect(report.isInitial).toBe(false);
    expect(report.added.map((c) => c.id)).toEqual([first.products[0].id]);
    expect(report.decreased).toHaveLength(1);
    expect(report.decreased[0]).toMatchObject({ id: lagavulinID, title: "Lagavulin (edited)" });
    expect(report.removed).toEqual([
      expect.objectContaining({ id: "999999", title: "Long Gone 12 Year Old", before: 2, after: 0 }),
    ]);
    expect(report.increased).toEqual([]);
  });

  it("is cheap for the server to check", () => {
    // The commit endpoint parses and re-serializes the upload; keep an eye on
    // its size and cost against the free plan's CPU allowance.
    const text = JSON.stringify(first);
    const start = performance.now();
    for (let i = 0; i < 10; i++) {
      const parsed = JSON.parse(text);
      JSON.stringify(parsed.products);
      JSON.stringify(parsed.bottles);
    }
    const perRun = (performance.now() - start) / 10;
    console.log(`upload ${(text.length / 1024).toFixed(0)} KB, parse+stringify ${perRun.toFixed(1)} ms`);
    expect(text.length).toBeLessThan(1_500_000);
  });
});
