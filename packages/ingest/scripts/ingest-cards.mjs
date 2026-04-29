#!/usr/bin/env node
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createDepthMap, createFallbackExpandedArt, DEFAULT_ARTWORK_REGION, normalizeCardImage } from "./lib/depth-map.mjs";
import { detectCoverage, detectHoloPattern } from "./lib/holo-patterns.mjs";
import { generateExpandedArt, generateExpandedDepthMap } from "./lib/openai-expanded-art.mjs";

const cwd = process.cwd();
const args = parseArgs(process.argv.slice(2));
// Resolve defaults against the repo root so the script works regardless of
// whether it is invoked from the workspace or the package directory.
const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../../..");
const inputDir = path.resolve(cwd, args.input ?? path.join(repoRoot, "assets/cards/inbox"));
const publicCardsDir = path.resolve(cwd, args.output ?? path.join(repoRoot, "assets/cards"));
const catalogPath = path.resolve(cwd, args.catalog ?? path.join(repoRoot, "assets/cards/catalog.json"));
const shouldUseAiExpand = Boolean(args.expand);
const shouldUseAiDepth = Boolean(args["ai-depth"]);

const imageExtensions = new Set([".png", ".jpg", ".jpeg", ".webp"]);

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

async function main() {
  const files = (await walk(inputDir)).filter((file) => imageExtensions.has(path.extname(file).toLowerCase()));
  if (files.length === 0) {
    console.log(`No card images found in ${inputDir}`);
    return;
  }

  const existingCatalog = await readJson(catalogPath, []);
  const byId = new Map(existingCatalog.map((card) => [card.id, card]));

  for (const filePath of files) {
    const metadata = await readMetadata(filePath);
    const id = slug(metadata.id ?? path.basename(filePath, path.extname(filePath)));
    const outDir = path.join(publicCardsDir, id);
    await mkdir(outDir, { recursive: true });

    const artworkRegion = metadata.artworkRegion ?? DEFAULT_ARTWORK_REGION;
    const normalizedPath = path.join(outDir, "card.png");
    const depthPath = path.join(outDir, "depth.png");
    const expandedPath = path.join(outDir, "expanded.png");
    const expandedDepthPath = path.join(outDir, "expanded-depth.png");

    await normalizeCardImage(filePath, normalizedPath);
    await createDepthMap(normalizedPath, depthPath, { artworkRegion });

    if (shouldUseAiExpand) {
      try {
        await generateExpandedArt(normalizedPath, expandedPath, metadata.expandedPrompt ? { prompt: metadata.expandedPrompt } : {});
      } catch (error) {
        console.warn(`AI expanded art failed for ${id}; using artwork crop fallback. ${error.message}`);
        await createFallbackExpandedArt(normalizedPath, expandedPath, { artworkRegion });
      }
    } else {
      await createFallbackExpandedArt(normalizedPath, expandedPath, { artworkRegion });
    }

    if (shouldUseAiDepth) {
      try {
        await generateExpandedDepthMap(expandedPath, expandedDepthPath, metadata.depthPrompt ? { prompt: metadata.depthPrompt } : {});
      } catch (error) {
        console.warn(`AI expanded depth failed for ${id}; using heuristic depth fallback. ${error.message}`);
        await createDepthMap(expandedPath, expandedDepthPath, { artworkRegion: { x: 0, y: 0, w: 1, h: 1 } });
      }
    } else {
      await createDepthMap(expandedPath, expandedDepthPath, { artworkRegion: { x: 0, y: 0, w: 1, h: 1 } });
    }

    const pattern = detectHoloPattern({ filename: filePath, metadata });
    const record = {
      id,
      name: metadata.name ?? titleFromSlug(id),
      subtitle: metadata.subtitle ?? "Processed card scan",
      set: metadata.set ?? "Imported Cards",
      rarity: metadata.rarity ?? "Unknown",
      number: metadata.number ?? "000/000",
      image: `/cards/${id}/card.png`,
      depth: `/cards/${id}/depth.png`,
      expandedImage: `/cards/${id}/expanded.png`,
      expandedDepth: `/cards/${id}/expanded-depth.png`,
      holoPattern: pattern,
      holoCoverage: detectCoverage({ metadata, pattern }),
      artworkRegion,
      depthScale: metadata.depthScale ?? 0.12,
      foilStrength: metadata.foilStrength ?? 1,
      accent: metadata.accent ?? "#35f6dd",
      processedAt: new Date().toISOString(),
      sourceImage: path.relative(cwd, filePath),
    };

    byId.set(id, record);
    console.log(`Processed ${id}`);
  }

  const nextCatalog = [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
  await writeFile(catalogPath, `${JSON.stringify(nextCatalog, null, 2)}\n`);
  console.log(`Updated ${path.relative(cwd, catalogPath)} with ${nextCatalog.length} cards`);
}

async function readMetadata(filePath) {
  const metadataPath = filePath.replace(path.extname(filePath), ".json");
  return readJson(metadataPath, {});
}

async function readJson(filePath, fallback) {
  try {
    return JSON.parse(await readFile(filePath, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return fallback;
    throw error;
  }
}

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = await Promise.all(
    entries.map((entry) => {
      const fullPath = path.join(dir, entry.name);
      return entry.isDirectory() ? walk(fullPath) : fullPath;
    }),
  );
  return files.flat();
}

function parseArgs(argv) {
  const parsed = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--")) continue;
    const key = token.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) {
      parsed[key] = true;
    } else {
      parsed[key] = next;
      index += 1;
    }
  }
  return parsed;
}

function slug(value) {
  return String(value)
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function titleFromSlug(value) {
  return value
    .split("-")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(" ");
}

export const __filename = fileURLToPath(import.meta.url);
