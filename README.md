# David's Liquor Cabinet

An iPad "digital menu" for a spirits collection tracked in CellarTracker,
with a shared Cloudflare server so several iPads and an admin web page see
the same collection and edits. See [PLAN.md](PLAN.md) for the design.

## Layout

```
App/                      SwiftUI iPad app
Config/                   Build settings (server host; git-ignored read key)
Packages/CellarKit/       Shared Swift logic (unit-tested)
  Sources/CellarKit/
    CSV/, Export/         CellarTracker export parsing (windows-1252, error pages)
    Models/, Enrichment/  Bottles → menu items, rules, houses, wording
    Server/               Cabinet server client, menu format, sync upload
  Tests/CellarKitTests/   Tests, a sanitized copy of the real export, golden.json
server/                   Cloudflare Worker (API + admin web page)
  src/                    API; src/rules is the TypeScript port of the rules
  web/                    Admin web page (Preact)
  migrations/             D1 schema
scripts/                  Helper scripts
project.yml               XcodeGen project spec
```

## iPad app (Mac)

Requirements: Xcode 16 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # then paste the read key
xcodegen generate              # creates DavidsLiquorCabinet.xcodeproj
open DavidsLiquorCabinet.xcodeproj
```

The read key is the server's `GUEST_PASSCODE` secret. It lets the app show
the menu without asking guests for a passcode, and it's never committed.

In Xcode, set your team under **Signing & Capabilities** (or set
`DEVELOPMENT_TEAM` in `project.yml`), then run on an iPad or simulator.
Re-run `xcodegen generate` after pulling changes that add or remove files.
With a paid Apple Developer account an install lasts a year; with a free
Personal Team, 7 days.

**Admin mode:** Settings → Admin → enter the admin passcode. It allows sync,
edits and hidden bottles, and locks again when the app closes.

## Server and admin web page

The Worker lives at `https://owls-perch-lc.josh-090.workers.dev`. The web
page there is admin-only (admin passcode). The **Deploy server** workflow
publishes it whenever `server/` changes; it needs these repository secrets:

| Secret | What |
|---|---|
| `CLOUDFLARE_API_TOKEN` | "Edit Cloudflare Workers" token plus D1 Edit |
| `ADMIN_PASSCODE` | Admin passcode (iPad admin mode and the web page) |
| `GUEST_PASSCODE` | The iPad app's read key (`openssl rand -hex 32`) |
| `SESSION_SECRET` | Signs sessions (`openssl rand -base64 48`); changing it signs everyone out |

Local development:

```sh
cd server
npx -y npm@11 ci               # npm 10 can't resolve vitest 4's peers
npm test                       # builds the web page, runs rules + API tests
printf 'ADMIN_PASSCODE=a\nGUEST_PASSCODE=g\nSESSION_SECRET=%s\n' "$(openssl rand -hex 24)" > .dev.vars
npx wrangler d1 migrations apply liquor-cabinet --local
npx wrangler dev               # http://localhost:8787
```

## Tests

```sh
cd Packages/CellarKit && swift test
cd server && npm run typecheck && npm test
```

CI runs both, plus an unsigned simulator build of the app, on every push.

`Packages/CellarKit/Tests/CellarKitTests/Fixtures/golden.json` holds the
derived fields for every product in the sample export. The Swift tests check
it and the TypeScript tests must reproduce it. After an intended rule change:

```sh
cd Packages/CellarKit && WRITE_GOLDEN=1 swift test --filter GoldenTests
```

## Updating the test fixture

Real exports contain prices, stores and purchase dates, so they're
git-ignored. To refresh the fixture from a new export:

```sh
python3 scripts/sanitize_export.py ~/Downloads/export.csv \
  Packages/CellarKit/Tests/CellarKitTests/Fixtures/sample_export.csv
```

Then update the expected counts in the tests and regenerate `golden.json`.
