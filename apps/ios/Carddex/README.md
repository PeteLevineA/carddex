# Carddex iOS

Native iOS / visionOS app that ports the Carddex holofoil viewer to Metal and
adds CollX-style scanning, identification, and collection management.

## Layout

```
apps/ios/Carddex/
├── Package.swift                 # SwiftPM with library targets only
├── project.yml                   # XcodeGen spec for the app + extensions
├── App/                          # SwiftUI app target (CarddexApp.swift, Info.plist, entitlements)
├── Sources/
│   ├── CarddexCore/              # SwiftData models, persistence, shared types
│   ├── CarddexCatalog/           # Bundled holofoil catalog + Pokémon TCG client
│   ├── CarddexScanner/           # Vision pipeline + Foundation Models verifier
│   ├── CarddexHolofoil/          # Metal renderer, MSL holofoil port
│   └── CarddexUI/                # SwiftUI tabs (Scan, Collection, Browse, Holofoil, Settings)
├── Widgets/                      # WidgetKit "Card of the day"
├── LiveActivities/               # ActivityKit scanning session
├── AppClip/                      # Scan-only App Clip
├── Intents/                      # App Intents + Shortcuts
└── Tests/                        # XCTest suites for Core / Catalog / Scanner
```

## Build

The non-UI logic builds with plain SwiftPM:

```bash
cd apps/ios/Carddex
swift build               # builds all library targets (no app)
swift test                # runs the XCTest suites
```

The full app needs Xcode (SwiftUI app targets aren't yet supported by SwiftPM).
Generate `Carddex.xcodeproj` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd apps/ios/Carddex
xcodegen generate
open Carddex.xcodeproj
```

CI runs `xcodebuild test` against the generated project on macOS.

## Architecture summary

### Tabs

1. **Scan** — `DataScannerViewController` for capture, `VNDetectRectanglesRequest`
   for framing, `VNRecognizeTextRequest` for OCR, then `CardScanner` to identify.
2. **Collection** — SwiftData-backed list of `CollectionItem`s with CSV export
   via `ShareLink`.
3. **Browse** — full Pokémon catalog (sets → cards → detail) loaded from
   `CatalogStore`.
4. **Holofoil** — `MTKView` with `HolofoilRenderer`, hand-ported from the GLSL
   in `apps/web/src/render/shaders.js` (re-exported by `packages/shaders`).
5. **Settings** — toggle cloud lookups, refresh catalog, view Apple Intelligence
   capability state.

### Identification tiers

| Tier | Where it runs | When |
| --- | --- | --- |
| A | Vision + OCR + bundled Core ML embeddings | Always |
| B | Foundation Models (`SystemLanguageModel.default`) | When `availability == .available` and Tier A is uncertain |
| C | `PokemonTCGClient` | Only with explicit user opt-in in Settings |

### Persistence

- `SwiftData` stores `CollectionItem`, `Scan`, and references between them.
- A CloudKit-backed configuration is used by default; a local-only fallback is
  used when the entitlement isn't configured (e.g. in CI / unit tests).
- Scan crops are written as HEIC into `Application Support/scans/<uuid>.heic`.

### Modern iOS feature surface

- App Intents + Shortcuts (`ScanCardIntent`, `ShowCollectionValueIntent`)
- WidgetKit "Card of the day"
- ActivityKit Live Activity for scanning sessions
- App Clip target for the scan flow
- `ShareLink` + Transferable CSV export
- Visual Intelligence / Camera Control button binding (planned)

## Tests

```bash
swift test --parallel
```

Covers OCR parsing, persistence round-trips, and catalog resolution. UI / shader
parity tests live in the Xcode-only target alongside golden-image fixtures.
