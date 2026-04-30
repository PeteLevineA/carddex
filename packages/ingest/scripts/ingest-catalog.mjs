#!/usr/bin/env node
// Pulls the full Pokémon TCG catalog from https://pokemontcg.io/v2 into
// <repo>/assets/catalog/.
//
// Outputs:
//   assets/catalog/sets.json              one entry per set
//   assets/catalog/cards.json             one entry per card (normalized)
//   assets/catalog/by-set/<setId>.json    per-set indices for fast load on iOS
//   assets/catalog/images/<setId>/<num>.png   small thumbnails (--with-images)
//
// Usage:
//   node scripts/ingest-catalog.mjs              # catalog metadata only
//   node scripts/ingest-catalog.mjs --with-images
//   POKEMONTCG_API_KEY=... node scripts/ingest-catalog.mjs   # higher rate limit
//
// The companion `tools/build-embeddings.py` script consumes cards.json and
// produces embeddings.bin + carddex.sqlite for the iOS app to mmap at launch.

import { mkdir, writeFile } from "node:fs/promises";
import { createWriteStream } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { pipeline } from "node:stream/promises";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../../..");
const outDir = path.join(repoRoot, "assets/catalog");

const API_BASE = "https://api.pokemontcg.io/v2";
const PAGE_SIZE = 250;

const args = parseArgs(process.argv.slice(2));
const withImages = Boolean(args["with-images"]);
const apiKey = process.env.POKEMONTCG_API_KEY ?? "";
const headers = apiKey ? { "X-Api-Key": apiKey } : {};

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

async function main() {
  await mkdir(outDir, { recursive: true });
  await mkdir(path.join(outDir, "by-set"), { recursive: true });

  console.log("Fetching sets...");
  const sets = await fetchAllPages(`${API_BASE}/sets`);
  const normalizedSets = sets.map(normalizeSet);
  await writeJson(path.join(outDir, "sets.json"), normalizedSets);
  console.log(`  wrote ${normalizedSets.length} sets`);

  console.log("Fetching cards (paginated)...");
  const allCards = [];
  let page = 1;
  // Pull all cards page-by-page so we can also bucket per set as we go.
  // The /cards endpoint supports `page` and `pageSize` query parameters.
  // We sort by set + number to keep diffs minimal between runs.
  while (true) {
    const url = `${API_BASE}/cards?page=${page}&pageSize=${PAGE_SIZE}&orderBy=set.releaseDate,number`;
    const res = await fetchJson(url);
    if (!res.data || res.data.length === 0) break;
    for (const raw of res.data) {
      allCards.push(normalizeCard(raw));
    }
    console.log(`  page ${page}: cumulative ${allCards.length} cards`);
    if (res.data.length < PAGE_SIZE) break;
    page += 1;
  }

  await writeJson(path.join(outDir, "cards.json"), allCards);

  // Per-set bucket files for the iOS app to lazy-load.
  const bySet = new Map();
  for (const card of allCards) {
    const list = bySet.get(card.setId) ?? [];
    list.push(card);
    bySet.set(card.setId, list);
  }
  for (const [setId, cards] of bySet) {
    await writeJson(path.join(outDir, "by-set", `${setId}.json`), cards);
  }
  console.log(`Wrote ${allCards.length} cards across ${bySet.size} sets.`);

  if (withImages) {
    console.log("Downloading small thumbnails...");
    await downloadThumbnails(allCards);
  } else {
    console.log("Skipping thumbnails (pass --with-images to fetch).");
  }
}

function normalizeSet(set) {
  return {
    id: set.id,
    name: set.name,
    series: set.series,
    printedTotal: set.printedTotal,
    total: set.total,
    releaseDate: set.releaseDate,
    ptcgoCode: set.ptcgoCode ?? null,
    symbol: set.images?.symbol ?? null,
    logo: set.images?.logo ?? null,
  };
}

function normalizeCard(card) {
  return {
    id: card.id,
    name: card.name,
    setId: card.set?.id,
    setName: card.set?.name,
    series: card.set?.series,
    number: card.number,
    printedTotal: card.set?.printedTotal,
    rarity: card.rarity ?? null,
    supertype: card.supertype ?? null,
    subtypes: card.subtypes ?? [],
    types: card.types ?? [],
    hp: card.hp ?? null,
    nationalPokedexNumbers: card.nationalPokedexNumbers ?? [],
    artist: card.artist ?? null,
    flavorText: card.flavorText ?? null,
    images: {
      small: card.images?.small ?? null,
      large: card.images?.large ?? null,
    },
    prices: {
      tcgplayer: card.tcgplayer?.prices ?? null,
      cardmarket: card.cardmarket?.prices ?? null,
      updatedAt: card.tcgplayer?.updatedAt ?? card.cardmarket?.updatedAt ?? null,
    },
  };
}

async function fetchAllPages(baseUrl) {
  const out = [];
  let page = 1;
  while (true) {
    const res = await fetchJson(`${baseUrl}?page=${page}&pageSize=${PAGE_SIZE}`);
    if (!res.data || res.data.length === 0) break;
    out.push(...res.data);
    if (res.data.length < PAGE_SIZE) break;
    page += 1;
  }
  return out;
}

async function fetchJson(url) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    const res = await fetch(url, { headers });
    if (res.ok) return res.json();
    if (res.status === 429 || res.status >= 500) {
      const wait = 2 ** attempt * 500;
      console.warn(`  ${res.status} from ${url}; retrying in ${wait}ms`);
      await sleep(wait);
      continue;
    }
    throw new Error(`HTTP ${res.status} fetching ${url}`);
  }
  throw new Error(`Exceeded retries for ${url}`);
}

async function downloadThumbnails(cards) {
  const root = path.join(outDir, "images");
  await mkdir(root, { recursive: true });
  let downloaded = 0;
  for (const card of cards) {
    const url = card.images?.small;
    if (!url) continue;
    const setDir = path.join(root, card.setId);
    await mkdir(setDir, { recursive: true });
    const safeNum = card.number.replace(/[^A-Za-z0-9_-]/g, "_");
    const outPath = path.join(setDir, `${safeNum}.png`);
    try {
      const res = await fetch(url);
      if (!res.ok || !res.body) {
        console.warn(`  skipped ${card.id}: HTTP ${res.status}`);
        continue;
      }
      await pipeline(res.body, createWriteStream(outPath));
      downloaded += 1;
      if (downloaded % 100 === 0) console.log(`  downloaded ${downloaded} thumbnails`);
    } catch (error) {
      console.warn(`  failed ${card.id}: ${error.message}`);
    }
  }
  console.log(`Downloaded ${downloaded} thumbnails.`);
}

async function writeJson(filePath, data) {
  await writeFile(filePath, `${JSON.stringify(data, null, 2)}\n`);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith("--")) {
      out[key] = next;
      i += 1;
    } else {
      out[key] = true;
    }
  }
  return out;
}
