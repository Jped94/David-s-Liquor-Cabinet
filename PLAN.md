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
a local JSON file. Displaying the menu never calls the LLM, and re-syncing doesn't
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
    ├── Models                  BottleRecord (row) → MenuItem (grouped by iWine)
    ├── Enrichment              Rules (category/region/ABV/age/opened)
    │                           + ClaudeEnricher (Messages API, JSON schema)
    └── Sync                    CellarTracker client, JSON snapshot cache, sync policy
```

- **JSON files** in Application Support hold the cache. `collection.json` is
  the last good CellarTracker download, and the menu opens from it instantly
  and offline. Overrides (and later Claude enrichment) are stored separately,
  keyed by `iWine`, so they survive resyncs. Bottles that disappear from CT
  drop off the menu, but their overrides are kept in case the bottles come
  back. This replaced the original SwiftData plan: the data is about 1,600
  read-only rows, so a file is simpler and can be tested on Linux.
- **Keychain** holds the CT credentials and the admin PIN.
- **No backend (v1).** The app talks to CellarTracker directly over HTTPS.
  v2 adds a shared Cloudflare backend; see below.
- A sanitized CSV fixture (prices and stores stripped) drives the parser and
  classifier tests.

## Shared database & web (v2)

Several iPads (3–4) and a web page for David and family share one copy of
the collection, edits and photos. Syncing is manual.

### Stack: Cloudflare (free tier)

| Piece | Cloudflare product | Notes |
|---|---|---|
| API + web page | **Worker** (TypeScript) with static assets | No server to keep running |
| Data | **D1** (SQLite) | Under 5 MB of data; the free tier allows 500 MB |
| Photos | **R2** | About 200–400 KB per resized photo, so 1 GB at most; the free tier allows about 10 GB with no download fees |

Expected cost: $0 a month. The $5 Workers Paid plan is the fallback if
limits ever bite.

### Sync: pass-through credentials, never stored

1. An admin presses **Sync** on an iPad or the web page. The CellarTracker
   login comes from the iPad Keychain or the browser's password manager.
2. It is sent over HTTPS to `POST /api/sync`. The Worker downloads the export
   once, then drops the login. It is never written to D1, logs or error text.
3. The Worker decodes the windows-1252 export, parses it and derives each
   product's menu fields (category, region, Scotch style, ABV, age, title and
   subtitle), replaces the stored bottles, and returns the sync report.

A browser page can't call CellarTracker itself because CT doesn't allow
cross-site requests, so the Worker does the fetch.

**One copy of the rules.** The parsing and classification rules move from
CellarKit (Swift) to the Worker (TypeScript). To keep them identical:

- a Swift test writes a **golden file** with the derived fields for every
  product in the sanitized fixture;
- the TypeScript tests must reproduce it exactly.

Once the iPads read from the server, the Swift rules are only kept for the
golden file and offline sample data.

### Access: two shared passcodes

- **Guest passcode** reads the menu. Each iPad enters it once.
- **Admin passcode** additionally allows sync, edits and photos. It replaces
  the local admin toggle.
- `POST /api/session` exchanges a passcode for a signed token (HMAC; the
  secret is a Worker secret). The iPad keeps the token in the Keychain; the
  web page keeps it in an HttpOnly cookie. Failed attempts are rate-limited.
- Passcodes are Worker secrets. They are never put in the repo or in chat.

### Data model (D1)

| Table | Contents |
|---|---|
| `bottles` | One row per CT inventory row from the latest sync: iWine, location, bin, quantity, pending, note, size, community score. **No prices, stores or purchase data are stored.** |
| `products` | One row per iWine: CT name fields plus derived fields (category, region, style, ABV, age, title, subtitle). Rebuilt on each sync. |
| `overrides` | The owner's edits per iWine (same fields as `ItemOverride`), updated time and device. Kept even when a product leaves CT. |
| `photos` | iWine → R2 key, size and updated time. |
| `syncs` | Time, counts and the sync report JSON, for history. |
| `descriptions` | Later: Claude drafts per iWine, frozen once written. |

### API

| Endpoint | Who | Purpose |
|---|---|---|
| `POST /api/session` | anyone | Passcode → token |
| `GET /api/menu` | guest | Products, bottles, overrides and photo refs in one JSON, with an ETag so unchanged menus cost nothing |
| `POST /api/sync` | admin | Pass-through CT sync; returns the report |
| `PUT /api/items/:iWine/override` | admin | Save or clear an edit |
| `PUT /api/items/:iWine/photo` | admin | Upload a resized JPEG (the client resizes it to about 1200px) |
| `GET /api/photos/:key` | guest | Photo from R2, cacheable |
| `GET /api/syncs` | admin | Recent sync reports |

### Clients

- **iPad:** reads `/api/menu`, caches it as JSON for offline and instant
  launch, and refreshes on launch, foreground and pull-to-refresh. The house
  and hidden-location choices stay per iPad. Photos are cached on the device.
  A one-time admin action uploads the edits already saved on David's iPad.
- **Web:** a static page in the same paper-menu style. It has the menu, search
  and house filter, and admin sync plus the report. Editing on the web comes
  later.

### Build order

1. **Rules port:** the golden file from Swift, then the TypeScript
   parser and rules, which must reproduce it.
2. **Worker:** D1 schema and migrations, the passcode session, `/api/menu`
   and `/api/sync`, with tests run locally (Miniflare).
3. **Deploy** (needs the setup below): a GitHub Action deploys on push.
4. **iPad client:** reads from the server, plus passcode entry, edits
   through the API, and migrating existing edits.
5. **Web page.**
6. **Photos:** "Add photo" in admin, R2 upload, and on-device caching.
7. **Claude descriptions** (Anthropic key as a Worker secret).

### Setup the owner does (about 20 minutes, once)

1. Create a free Cloudflare account. Whoever owns it controls the data.
2. Create an API token from the "Edit Cloudflare Workers" template, with D1
   and R2 access added.
3. Add it to the GitHub repo secrets as `CLOUDFLARE_API_TOKEN`, along with
   `CLOUDFLARE_ACCOUNT_ID`.
4. Set the two passcodes and the token-signing secret with
   `wrangler secret put` (exact commands are in the README).
5. Later: an Anthropic API key for descriptions.

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

1. **Foundation** ✅: Xcode project, CellarKit package, CSV parser +
   windows-1252 + enrichment, with tests against the sample fixture.
2. **Sync** (in progress): CellarTracker client, Keychain login, JSON cache, refresh,
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
3. **Photos:** none in v1. In v2, David adds them from the iPad (stored in R2).
4. **Guest extras:** guests see community scores and sealed/open bottle
   counts. "On order" bottles are hidden. Still to confirm: what
   David uses Pending for.

## Notes

- Building requires the Mac + Xcode. The CellarKit logic can be developed and
  tested anywhere Swift runs.
- Never commit real exports. `*.csv` is git-ignored, and only sanitized fixtures
  go in the repo.

## Decisions (v2)

5. **Backend:** Cloudflare Worker + D1 + R2, on the free tier.
6. **Sync:** manual, from any iPad or the web page. CT credentials are passed
   through for each sync and never stored on the server.
7. **Access:** shared guest and admin passcodes. The web page is for David
   and family only.
