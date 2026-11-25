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

## Enrichment: rules + Claude, frozen per expression

New bottles arrive at runtime, so parsing can't rely on a one-off LLM pass. We
use three layers. The highest one that has a value wins:

1. **Owner override.** Anything David edits in admin mode.
2. **Claude enrichment.** It runs once per new `iWine`, the result is saved,
   and it is never re-run unless David taps "Regenerate".
3. **Deterministic rules.** These always run, instantly and offline. They are
   the fallback when there's no network, no API key, or the call failed.

This keeps runtime behaviour deterministic. Each expression is enriched exactly
once, the output is constrained to a JSON schema, and the result is stored in
SwiftData. Displaying the menu never calls the LLM, and re-syncing doesn't
re-enrich existing items. Only new `iWine`s found during a sync are queued.

**Claude call** (raw `URLSession` → `POST https://api.anthropic.com/v1/messages`;
there is no official Swift SDK):

- Model `claude-opus-5-5`, `output_config.effort: "low"`, and
  `output_config.format: {type: "json_schema", schema: …}` so the response is
  always schema-valid JSON.
- Input: one expression's raw CT fields (Wine, Producer, Designation, Vineyard,
  Varietal, Country/Region/SubRegion, Vintage, Size, Note).
- Output schema (draft): `category`, `subcategory` (e.g. "Islay", "Wheated
  Bourbon"), `style`, `abv`, `ageYears`, `caskFinish`, `caskStrength`,
  `limitedEdition`, `bottleNumber`, `description` (2–3 sentences),
  `flavorTags` (e.g. smoky, sherried, spicy), `confidence`.
- Always check `stop_reason` (e.g. `refusal`, `max_tokens`) before parsing.
  On failure, fall back to rules and retry on a later sync.
- **Initial run:** the first sync enriches all 785 expressions in the app,
  using the same code path as later additions. Estimated cost is about $5–10
  one-time, then pennies per new bottle.
- **API key:** an Anthropic API key (console.anthropic.com, billed separately
  from a Claude.ai subscription). David enters it in admin settings and it is
  stored in the Keychain, never compiled into the app. Set a monthly spend
  limit in the Console.

**Descriptions** are AI drafts, so they can be wrong for obscure single casks.
The prompt tells Claude to describe the style rather than invent specifics
when it isn't sure.

- Each description is marked as a draft until David edits or approves it.
- David can edit, regenerate, or hide the description for any single bottle.
- A global "Show descriptions" switch turns them off everywhere.
- Later option: give Claude the web search tool so it can ground descriptions
  for limited releases.

## Houses & locations

| House | CT `Location` values |
|---|---|
| **Estancia** | Estancia, Estancia Open |
| **Bedford** | Owl's Perch, Open in Owl's perch, Cellar, Basement, 194 Opened |

- Each iPad has a setting for which house it is at: Bedford, Estancia or All.
  The guest menu shows only the bottles at that house.
- The location → house mapping is editable in admin mode. A new CT location
  that isn't mapped yet gets flagged for David to assign.
- **On order:** CT `Pending = 1` means the purchase was logged but never marked
  as delivered. These 9 bottles have no location, and some date back to
  2018/2023, so they probably arrived but were never checked in. They are
  hidden from guests. Fixing them in CT means marking them delivered and giving
  them a location.

## Architecture

```
DavidsLiquorCabinet/            Xcode project (iPadOS 17+, SwiftUI)
├── App/                        App target: views, navigation, theming
└── Packages/CellarKit/         Local Swift package (unit-tested)
    ├── CellarTrackerClient     URLSession fetch, auth/HTML detection, retries
    ├── CSVParser               RFC-4180 parser, windows-1252 decoding
    ├── Models                  Bottle (row) → Expression (grouped by iWine)
    ├── Enrichment              Rules (category/region/ABV/age/opened)
    │                           + ClaudeEnricher (Messages API, JSON schema)
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
   error states (bad login, offline, CT down), house filtering.
2b. **Claude enrichment**: enrichment queue for new `iWine`s, schema-constrained
   calls, stored results, an admin "Regenerate" action, and description switches.
3. **Guest menu MVP**: home, categories, list, detail, search.
4. **Admin + overrides**: PIN gate, edit description/photo/category/featured/hidden.
5. **Polish**: visual design pass (typographic menu look, category colors),
   empty/loading states, iPad landscape + portrait, accessibility.
6. **Distribution**: TestFlight build on David's iPad via the Apple Developer account.

Optional later: "Surprise me" pick, flight builder (pick 3–4 to taste side by
side), AI-drafted tasting descriptions that David reviews and edits.

## Decisions

1. **Houses:** Estancia and Bedford. Each iPad filters to its own house (see above).
2. **Descriptions:** start with AI drafts. They can be edited or hidden per
   bottle, and switched off globally.
3. **Photos:** none in v1. The menu uses a typographic design; photos may come later.
4. **Guest extras:** guests see community scores, bottle counts and "last
   bottle" badges. "On order" bottles are hidden. Still to confirm: what
   David uses Pending for.

## Notes

- Building requires the Mac + Xcode. The CellarKit logic can be developed and
  tested anywhere Swift runs.
- Never commit real exports. `*.csv` is git-ignored, and only sanitized fixtures
  go in the repo.
