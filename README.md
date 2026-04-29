# Carddex Monorepo

Carddex is a multi-app project for viewing, scanning, and managing Pokémon cards.

## Layout

```
.
├── apps/
│   ├── web/          # Vite + Three.js holofoil viewer (the original Pokemon Card Lightbox)
│   └── ios/          # Native iOS app (SwiftUI + Metal + Vision + SwiftData)
├── packages/
│   ├── catalog/      # Shared card catalog schema, JSON Schema, JS types
│   ├── ingest/       # Scripts to ingest scans + the Pokémon TCG API
│   └── shaders/      # Canonical GLSL holofoil shaders (ported to MSL on iOS)
├── assets/
│   ├── cards/        # Per-card assets (front, depth, foil mask, expanded art, meta)
│   └── catalog/      # Generated full Pokémon catalog (cards.json, sets.json, sqlite)
├── tools/            # Cross-cutting build/dev tooling
└── .github/workflows # CI: web build + iOS xcodebuild test
```

## Workspaces

This repo uses npm workspaces. From the root:

```bash
npm install
npm run dev          # runs the web app
npm run build        # builds the web app
npm run ingest       # ingest hand-processed scans (sharp + AI expand)
npm run ingest:catalog   # pull the full Pokémon TCG API into assets/catalog/
```

To target a specific workspace directly:

```bash
npm run <script> -w @carddex/web
npm run <script> -w @carddex/ingest
```

## Web app

See [`apps/web/README.md`](apps/web/README.md) for the holofoil viewer. The web app
serves `/cards/*` from the shared `assets/cards/` directory at dev time, and copies
that directory into `dist/cards` on build.

## iOS app

See [`apps/ios/README.md`](apps/ios/README.md). The iOS app:

1. Has the same 3D holofoil tab, ported from the GLSL in `packages/shaders/` to Metal.
2. Adds CollX-style **Scan** + **Collection** + **Browse** tabs.
3. Uses Vision + a bundled Core ML model for offline identification, with optional
   on-device LLM verification through Apple's Foundation Models framework when the
   device supports Apple Intelligence, and an opt-in cloud fallback to the Pokémon TCG API.
4. Persists scans, collection items, and cached catalog rows with SwiftData and
   syncs across devices via CloudKit.

## Catalog

The canonical Pokémon catalog is generated from <https://pokemontcg.io>. Re-run
`npm run ingest:catalog` to refresh `assets/catalog/cards.json`, the per-set
indices, and the SQLite snapshot consumed by the iOS app.

## CI

GitHub Actions runs two jobs on every PR:

* **web** — Node 20, `npm ci && npm run build -w @carddex/web`.
* **ios** — macOS runner, `xcodebuild test` against an iPhone 16 Pro simulator.

## License

See individual package licenses. Card images are © The Pokémon Company; the
catalog ingest pipeline only redistributes thumbnails fetched on demand.
