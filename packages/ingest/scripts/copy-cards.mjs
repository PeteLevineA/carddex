#!/usr/bin/env node
import { cp, mkdir, rm } from "node:fs/promises";

await mkdir("dist", { recursive: true });
await rm("dist/cards", { recursive: true, force: true });
await cp("cards", "dist/cards", {
  recursive: true,
  filter: (source) => !source.includes("/inbox") && !source.endsWith("/inbox"),
});
console.log("Copied processed cards into dist/cards");
