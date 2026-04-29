# @carddex/ingest

Ingestion pipelines for the Carddex monorepo.

## Scripts

| Script | Description |
| --- | --- |
| `npm run ingest` | Process scans in `assets/cards/inbox/` into the holofoil viewer's per-card asset folders + update `assets/cards/catalog.json`. |
| `npm run ingest:static` | Pure-Python fallback when `sharp` is unavailable. |
| `npm run ingest:catalog` | Pull the full Pokémon TCG API into `assets/catalog/` (sets, cards, per-set buckets, optional thumbnails). |
| `npm run catalog:demo` | Verify the demo catalog references resolve on disk. |

## Pokémon TCG API

`ingest:catalog` paginates `https://api.pokemontcg.io/v2`. Set
`POKEMONTCG_API_KEY` for higher rate limits. Pass `--with-images` to also
download the `images.small` thumbnail for every card into
`assets/catalog/images/<setId>/<number>.png`.

The output of `ingest:catalog` is the canonical input for `tools/build-embeddings.py`,
which produces the `carddex.sqlite` + `embeddings.bin` artifacts that ship
inside the iOS app bundle.

## OpenAI (optional)

`npm run ingest -- --expand --ai-depth` calls the OpenAI Images API to
generate full-art expansions and AI depth maps. `OPENAI_API_KEY` is required;
`OPENAI_IMAGE_MODEL` defaults to `gpt-image-2`.
