#!/usr/bin/env node
import { access, readFile } from "node:fs/promises";

const catalogPath = "cards/catalog.json";
const catalog = JSON.parse(await readFile(catalogPath, "utf8"));

for (const card of catalog) {
  await Promise.all([
    access(`.${card.image}`),
    access(`.${card.depth}`),
    access(`.${card.expandedImage}`),
    access(`.${card.expandedDepth}`),
  ]);
}

console.log(`Demo catalog is ready with ${catalog.length} cards.`);
