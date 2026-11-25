# David's Liquor Cabinet — Project Plan

A native iPad app that turns a CellarTracker spirits collection into a browsable
"digital menu" for guests, with an admin mode for the owner.

## Goals

- **Guests** browse what's available, by spirit type, region and style, and see
  what's open and ready to pour.
- **Owner** keeps CellarTracker as the source of truth. The app syncs from it
  and adds menu-only extras: descriptions, photos, featured picks, hidden items.
- Works offline once synced. No server to run.

## Data source

CellarTracker has no official API, but it has a self-serve export endpoint
(the same one [slavins-co/cellartracker-mcp](https://github.com/slavins-co/cellartracker-mcp) uses):

```
GET https://www.cellartracker.com/xlquery.asp
    ?User=<user>&Password=<pw>&Format=csv&Table=List&Location=1
```

- Credentials go in the query string, so they live in the iPad Keychain and are
  never logged.
- A bad login still returns **HTTP 200** with an HTML page containing
  "You are currently not logged into CellarTracker." A body starting with `<`
  means error, not CSV.
- **Encoding is windows-1252, not UTF-8**. This is confirmed: the sample export
  breaks a UTF-8 decoder on accented names such as "Cachaça".
- No published rate limit. Sync on launch if the data is more than 24h old, plus
  manual pull-to-refresh.

Other tables available later if useful: `Notes`, `Bottles`, `Purchase`,
`Consumed`, `Tag`, `Pending`.

### Findings from the sample export (Nov 2026)

1,648 bottle rows, **785 unique expressions** (`iWine`), one row per bottle (`iInventory`).

| Column | What it holds for spirits | Usable? |
|---|---|---|
| `Type` / `Color` / `Category` | Always `Spirits` / `Other` / `Distilled` | No, so the spirit type has to be derived |
| `Wine` | Full name incl. ABV, e.g. *"Aberfeldy 25 Year Old … Single Malt Scotch Whisky, 46%"* | Yes, the main display name |
| `Producer` | Distillery / brand | Yes |
| `Designation` | Expression name, e.g. *"25 Year Old 125th Anniversary Edition"* | Yes |
| `Vineyard` | Style + ABV (+ sometimes bottle count). Messy: 184 variants | Partial, parse it |
| `Varietal` | Malt / Grain / Rye / Agave / Molasses / Sugar Cane / … | Yes, for classification |
| `Country` / `Region` / `SubRegion` | e.g. UK / Scotland / Islay | Yes, for Scotch regions |
| `Vintage` | `1001` = no vintage (1,041 bottles); else distillation/release year | Yes, show when ≠ 1001 |
| `Size` | 750ml, 700ml, 1.0L, 50ml … | Yes |
| `Location` / `Bin` | Owl's Perch, Cellar, Estancia, Basement, "Open in Owl's perch", "194 Opened", "Estancia Open" | Yes: location + **opened** status |
| `Note` | Bottle notes, e.g. *"bottle 124 of 280"*, *"bottled in 2004"* | Yes, as detail text |
| `CScore` / `CNotes` / `LikePercent` | Community score / note count | Optional |
| `Value` / `Price` / `StoreName` / `PurchaseDate` | Financials | **Admin only, never shown to guests** |
| `PNotes` / `PScore` | Personal tasting notes | Empty, so no description text comes from CT |
| `BeginConsume` / `EndConsume` | Wine drinking windows | Ignore |

Derived fields:

- **Category**: keyword rules over `Wine`, `Varietal` and `Country` classify
  783 of 785 expressions:
  Scotch 315 · Bourbon 192 · Rum & Cane 56 · Rye 54 · Agave 49 · Irish 49 ·
  American/World Whiskey 42 · Japanese 15 · Brandy 11 · Other 2.
  The owner can override the category per expression.
- **Scotch sub-region** from `SubRegion`: Islay, Speyside, Highlands, Campbeltown, …
- **ABV**: a regex on `Wine`. 68 bottles have no ABV, so it is shown as optional.
- **Age statement**: a regex on `Designation` (`\d+ Year`). 941 bottles have one.
- **Opened**: `Location` contains "open". 89 bottles are open now: the
  "Now Pouring" shelf.
- **Bottle count**: rows grouped by `iWine`.

## Architecture

```
DavidsLiquorCabinet/            Xcode project (iPadOS 17+, SwiftUI)
├── App/                        App target: views, navigation, theming
└── Packages/CellarKit/         Local Swift package (unit-tested)
    ├── CellarTrackerClient     URLSession fetch, auth/HTML detection, retries
    ├── CSVParser               RFC-4180 parser, windows-1252 decoding
    ├── Models                  Bottle (row) → Expression (grouped by iWine)
    ├── Enrichment              Category / region / ABV / age / opened
    └── Store                   SwiftData persistence + sync merge
```

- **SwiftData** caches the synced collection plus a separate `Override` model
  keyed by `iWine`, holding description, photo, category, featured and hidden.
  Overrides survive resyncs. Bottles that disappear from CT drop off the menu,
  but their overrides are kept in case the bottles come back.
- **Keychain** holds the CT credentials and the admin PIN.
- **No backend.** The app talks to CellarTracker directly over HTTPS.
- A sanitized CSV fixture (prices and stores stripped) drives the parser and
  classifier tests.

## App structure

**Guest mode** (default):
- Home: a "Now Pouring" shelf (opened bottles), a featured shelf, and category tiles.
- Category → filterable list/grid: sub-region, age, ABV range, opened only,
  and sort by name, age or ABV.
- Expression detail: name, distillery, style, region, age, ABV, vintage, size,
  bottle notes, description and photo.
- Global search.
- No prices, stores, purchase dates or bin details.

**Admin mode** (PIN / Face ID):
- CellarTracker login, sync status, manual refresh.
- Per-expression overrides: description, photo (camera/library), category,
  featured, hidden.
- Settings: which locations count as "this house", and the theme.

Kiosk use: iPad **Guided Access** locks the iPad to the app for parties. No
extra code is needed.

## Phases

1. **Foundation**: Xcode project, CellarKit package, CSV parser +
   windows-1252 + enrichment, with tests against the sample fixture.
2. **Sync**: CellarTracker client, Keychain login, SwiftData store, refresh,
   error states (bad login, offline, CT down).
3. **Guest menu MVP**: home, categories, list, detail, search.
4. **Admin + overrides**: PIN gate, edit description/photo/category/featured/hidden.
5. **Polish**: visual design pass (typographic menu look, category colors),
   empty/loading states, iPad landscape + portrait, accessibility.
6. **Distribution**: TestFlight build on David's iPad via the Apple Developer account.

Optional later: "Surprise me" pick, flight builder (pick 3–4 to taste side by
side), AI-drafted tasting descriptions that David reviews and edits.

## Open questions

1. **Locations.** Are *Owl's Perch* and *Estancia* different houses? If so, the
   iPad should probably show only the bottles at the house it lives in.
   *Cellar*, *Basement* and *194* also need sorting out.
2. **Descriptions.** CellarTracker has no tasting-note text for these bottles.
   Options: David writes his own, AI drafts them for him to edit, or the menu
   goes without. 785 expressions is a lot to write by hand.
3. **Photos.** There are no images in the export. Should we use a typographic
   design by default and add optional photos for featured bottles?
4. **Guest-visible extras.** Should guests see community scores? Bottle counts?
   "Only one left"?
5. **Pending bottles** (9 in transit). Should they be hidden from guests?

## Notes

- Building requires the Mac + Xcode. The CellarKit logic can be developed and
  tested anywhere Swift runs.
- Never commit real exports. `*.csv` is git-ignored, and only sanitized fixtures
  go in the repo.
