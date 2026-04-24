# Pokemon Card Lightbox

A local 3D card viewer for processed Pokemon cards. It uses a Three.js shader to combine a front-card texture, a grayscale depth map, angle-sensitive holofoil patterns, and an expanded full-art view.

## Run It

This project can run without a build step:

```bash
python3 -m http.server 4173
```

Open `http://127.0.0.1:4173`.

If Node is installed, Vite also works:

```bash
npm install
npm run dev
```

The demo catalog includes three vector cards so the renderer works immediately. The static path uses CDN-hosted Three.js and Lucide; the Vite path uses the package dependencies.

## Add Cards

Put high-resolution scans in `cards/inbox`. You can add a matching JSON sidecar to set the card name, holo pattern, artwork bounds, depth strength, and foil coverage. Processed web assets live alongside the catalog in `cards`.

```bash
npm run ingest
```

The ingest script writes normalized assets into `cards/<card-id>` and updates `cards/catalog.json`.

When Node or Sharp are unavailable, use the static fallback:

```bash
python3 scripts/ingest-static.py /path/to/card.png --id my-card --name "My Card"
```

## AI Expanded Art

The ingestion pipeline can call the OpenAI Images API for full-art expansion and optional AI depth maps:

```bash
OPENAI_API_KEY=... npm run ingest -- --expand --ai-depth
```

`OPENAI_IMAGE_MODEL` defaults to `gpt-image-2` and can be changed without editing code.

## Holofoil Renderer

The shader currently includes these families: starlight, cosmos, tinsel, sheen, cracked ice, crosshatch, water web, sequin, fireworks, and plain foil. Each pattern is rendered procedurally and gated by view angle, light direction, depth, and coverage mode.

## Depth Maps

Depth maps are grayscale images where white comes forward and black recedes. The included heuristic is intentionally conservative: it uses luminance, center falloff, edge falloff, and the artwork region to create a Facebook-style relief effect. Replace generated maps with higher-quality depth maps whenever you have them.
