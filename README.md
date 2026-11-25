# David's Liquor Cabinet

An iPad "digital menu" for a spirits collection tracked in CellarTracker.
See [PLAN.md](PLAN.md) for the full plan and the analysis of the export data.

## Layout

```
App/                      SwiftUI iPad app
Packages/CellarKit/       Core logic as a Swift package (unit-tested)
  Sources/CellarKit/
    CSV/                  RFC 4180 CSV parser
    Export/               CellarTracker export decoding (windows-1252, error pages)
    Models/               BottleRecord (one bottle), MenuItem (one product), categories
    Enrichment/           Rule-based parsing, house mapping, menu building
  Tests/CellarKitTests/   Tests, including a sanitized copy of the real export
scripts/                  Helper scripts
project.yml               XcodeGen project spec
```

## Getting started (Mac)

Requirements: Xcode 16 or newer, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
xcodegen generate              # creates DavidsLiquorCabinet.xcodeproj
open DavidsLiquorCabinet.xcodeproj
```

In Xcode, set your team under **Signing & Capabilities** (or set
`DEVELOPMENT_TEAM` in `project.yml`). Then run on an iPad simulator or on a
connected iPad. Re-run `xcodegen generate` after adding or removing files.

For now the app shows a bundled, sanitized sample of the collection.
The live CellarTracker sync is phase 2.

### Running the tests

```sh
cd Packages/CellarKit
swift test
```

CI runs the same tests and an unsigned simulator build on every push
(`.github/workflows/ci.yml`).

## Updating the test fixture

Real exports contain prices, stores and purchase dates, so they are
git-ignored. To refresh the fixture from a new export:

```sh
python3 scripts/sanitize_export.py ~/Downloads/export.csv \
  Packages/CellarKit/Tests/CellarKitTests/Fixtures/sample_export.csv
```

The expected counts in `FixtureTests.swift` will then need updating.
