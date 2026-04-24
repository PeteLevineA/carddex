# Card Inbox

Drop high-resolution card scans here, then run:

```bash
npm run ingest
```

Optional sidecar metadata uses the same basename as the image:

```json
{
  "name": "Example Charizard",
  "subtitle": "Fire type / personal scan",
  "set": "Base Set",
  "rarity": "Rare Holo",
  "number": "004/102",
  "holoPattern": "starlight",
  "holoCoverage": "artwork",
  "artworkRegion": { "x": 0.093, "y": 0.518, "w": 0.814, "h": 0.341 },
  "depthScale": 0.13,
  "foilStrength": 1.15,
  "expandedPrompt": "Create a full-bleed expanded illustration from the card art."
}
```

`artworkRegion` is in renderer UV space: `x` and `y` start at the bottom-left.
