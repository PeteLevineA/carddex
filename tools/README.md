# tools/

Cross-cutting build/dev tooling for the Carddex monorepo.

| Script | Purpose |
| --- | --- |
| `build-embeddings.py` | Reads `assets/catalog/cards.json` (produced by `npm run ingest:catalog`) and writes `embeddings.bin` + `carddex.sqlite` for the iOS app. The current implementation uses a deterministic perceptual hash placeholder so the output is reproducible; swap in the production Core ML model once it exists. |
