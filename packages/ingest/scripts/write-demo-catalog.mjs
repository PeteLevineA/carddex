#!/usr/bin/env node
import { access, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../../..");
const catalogPath = path.join(repoRoot, "assets/cards/catalog.json");
const catalog = JSON.parse(await readFile(catalogPath, "utf8"));

for (const card of catalog) {
  // card.image is "/cards/<id>/card.png"; strip the leading "/cards" since
  // the shared store lives at <repoRoot>/assets/cards.
  const stripPrefix = (p) => p.replace(/^\/cards\//, "");
  await Promise.all([
    access(path.join(repoRoot, "assets/cards", stripPrefix(card.image))),
    access(path.join(repoRoot, "assets/cards", stripPrefix(card.depth))),
    access(path.join(repoRoot, "assets/cards", stripPrefix(card.expandedImage))),
    access(path.join(repoRoot, "assets/cards", stripPrefix(card.expandedDepth))),
  ]);
}

console.log(`Demo catalog is ready with ${catalog.length} cards.`);
