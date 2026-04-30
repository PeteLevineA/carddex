#!/usr/bin/env node
// Copies the shared card assets into the Vite dist output so Netlify serves
// them at /cards/*. The source lives at <repo>/assets/cards.
import { cp, mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const sharedCards = path.resolve(here, "../../../assets/cards");
const outCards = path.resolve(here, "../dist/cards");

await mkdir(path.dirname(outCards), { recursive: true });
await rm(outCards, { recursive: true, force: true });
await cp(sharedCards, outCards, {
  recursive: true,
  filter: (source) => !source.includes(`${path.sep}inbox`) && !source.endsWith("inbox"),
});
console.log(`Copied processed cards from ${sharedCards} into ${outCards}`);
