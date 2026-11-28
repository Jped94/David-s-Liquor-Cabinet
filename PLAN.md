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
App/                        iPad app (SwiftUI, iPadOS 17+)
Packages/CellarKit/         Shared Swift logic (unit-tested on Linux and macOS)
  CSV/, Export/             CSV parser, windows-1252 export decoding
  Models/, Enrichment/      Bottles → menu items, rules, house mapping, wording
  Server/                   Cabinet server client, menu format, sync upload, report
server/                     Cloudflare Worker (TypeScript)
  src/                      API: sessions, menu, edits, sync download/commit
  src/rules/                TypeScript port of the rules (used by the web page)
  web/                      Admin web page (Preact), served by the Worker
  migrations/               D1 (SQLite) schema
```

**One copy of the truth.** CellarTracker is the source of the collection.
The cabinet server holds the latest synced copy plus the owner's edits, and
every iPad and the web page read it from there.

**The same rules in two languages.** The menu rules are Swift (CellarKit,
used by the iPad) and TypeScript (`server/src/rules`, used by the web page).
`Fixtures/golden.json` is written by the Swift tests and must be reproduced
exactly by the TypeScript tests, so the two can't drift apart.

## Shared server (v2) ✅

Several iPads (3–4) and an admin web page share one collection, set of edits
and (later) photos. Syncing is manual.

### Stack: Cloudflare, free tier

| Piece | Cloudflare product | Notes |
|---|---|---|
| API + admin web page | **Worker** (TypeScript) + static assets | `owls-perch-lc.josh-090.workers.dev` |
| Data | **D1** (SQLite) | Under 5 MB; the free tier allows 500 MB |
| Photos (planned) | **R2** | About 200–400 KB per resized photo; free tier about 10 GB |

The free plan allows about 10 ms of CPU per request, so the server never
parses the CellarTracker export itself (that takes about 50 ms). See Sync.

### Sync: credentials passed through, parsing on the device

1. An admin presses **Sync** on an iPad or the web page. The CellarTracker
   login comes from that iPad's Keychain or the browser's password manager.
2. `POST /api/sync/download`: the Worker fetches the export with that login
   (browsers can't call CellarTracker directly), then drops the login. It's
   never stored, logged or included in errors.
3. The device parses the export and builds the menu and the sync report
   (CellarKit on the iPad, `server/src/rules` on the web page).
4. `POST /api/sync/commit`: the Worker checks the upload (about 3 ms) and
   stores it pre-serialized, in chunks, so serving it costs almost nothing.

Pending ("on order") bottles, prices, stores and purchase details are never
uploaded.

### Access

- **The iPad app has a built-in read key** (the `GUEST_PASSCODE` secret, put
  in the git-ignored `Config/Secrets.xcconfig`), so guests are never asked
  for a passcode.
- **The admin passcode** unlocks admin mode on an iPad (until the app closes)
  and is the only way into the web page.
- `POST /api/session` turns a passcode into a signed token (HMAC, one year):
  a Bearer token on iPads and an HttpOnly cookie on the web. Wrong passcodes
  are rate-limited.

### Data model (D1)

| Table | Contents |
|---|---|
| `menu_parts` | The latest sync: products and bottles as JSON, in chunks |
| `overrides` | The owner's edits per iWine. Kept even when a product leaves CT. |
| `syncs` | Time, counts and the report of each sync |
| `meta` | The menu version (its ETag) |
| `login_attempts` | Failed passcodes per address, for rate limiting |

### API

| Endpoint | Who | Purpose |
|---|---|---|
| `POST/GET/DELETE /api/session` | anyone | Sign in, check the role, sign out |
| `GET /api/menu` | guest | Products, bottles and edits, with an ETag |
| `POST /api/sync/download` | admin | Pass-through CellarTracker export |
| `POST /api/sync/commit` | admin | Store a synced menu and its report |
| `PUT/DELETE /api/items/:iWine/override` | admin | Save or clear an edit |
| `GET /api/syncs` | admin | The last 20 sync reports |

### Conflicts

- **Two syncs at once:** both upload the same CellarTracker data; the last
  one wins and nothing is lost.
- **A sync and an edit:** they're stored separately and never collide.
- **Two edits to the same bottle at once:** the last save wins (rare with one
  or two admins; an "edited elsewhere, reload" check could be added).
- **Offline:** reading uses the cached menu; saving needs a connection.

## App structure

**Guest view** (default):
- Cover: masthead, Tonight's Pours (open bottles), the list of spirits.
- Category pages with sections (Scotch by region, American Whiskey by style,
  agave by spirit, rum by country) or A–Z, a Scotch style filter, "open
  bottles only", and an inline search.
- House selector, search and settings on every page.
- Tasting card: age, strength, sealed/open counts, description, style,
  origin, bottle size, community score, where the bottles are, and a link to
  the product's CellarTracker page.

**Admin mode** (admin passcode):
- Sync from CellarTracker, sync report.
- Edit any bottle: title, second line, category, Scotch region and style,
  ABV, age, style, description, hide.
- One-time upload of edits saved on an iPad before the shared server.

**Admin web page:** sign in, sync and sync history, browse and filter the
whole collection, edit any bottle.

Kiosk use: iPad **Guided Access** locks the iPad to the app for parties.

## Status

Done:
- Foundation: CellarKit, parser, rules and tests against the real export.
- Printed-menu design, category pages, tasting card, search, houses and
  locations, sync report.
- Shared Cloudflare server, iPad client, admin web page.

Next:
1. **Distribution:** the $99 Apple Developer account, then installs from
   Xcode last a year (registered iPads).
2. **Open vs. sealed:** separate from location (see Decisions).
3. **Photos:** "Add photo" in admin, stored in R2, cached on each iPad.
4. **Tasting notes:** Claude-written notes from its own knowledge (needs an
   Anthropic API key). Community notes only with CellarTracker's written
   permission (their terms, sections 3 and 9).
5. Optional: "edited elsewhere" check for edits; assigning locations to
   houses from Settings.

## Decisions

1. **Houses:** Estancia = Estancia, Estancia Open. Bedford = Owl's Perch,
   Open in Owl's perch, Cellar, Basement, 194 Opened.
2. **Descriptions:** start with AI drafts, editable and removable per bottle.
3. **Photos:** David adds them from the iPad, stored in R2.
4. **Guests see** community scores and sealed/open counts. Pending bottles
   are hidden.
5. **Backend:** Cloudflare Worker + D1 (+ R2 later), on the free tier.
6. **Sync:** manual, from any iPad or the web page. The CT login is passed
   through for each sync and never stored on the server.
7. **Access:** built-in read key for the iPad app; the admin passcode for
   admin mode and the web page.
8. **"View on CellarTracker":** shown to everyone.
9. **Open vs. sealed:** currently read from the location name ("Open in
   Owl's perch"), because CellarTracker has no open/sealed field. To be
   separated from location (pending the owner's choice of approach).

## Notes

- Building the app requires the Mac + Xcode. CellarKit and the server can be
  developed and tested anywhere.
- Never commit real exports. `*.csv` is git-ignored, and only sanitized
  fixtures go in the repo.
