export const HOLO_PATTERNS = [
  "starlight",
  "cosmos",
  "tinsel",
  "sheen",
  "cracked-ice",
  "crosshatch",
  "water-web",
  "sequin",
  "fireworks",
  "plain",
];

const aliases = new Map([
  ["star", "starlight"],
  ["stars", "starlight"],
  ["starlight", "starlight"],
  ["galaxy", "cosmos"],
  ["cosmos", "cosmos"],
  ["cosmo", "cosmos"],
  ["dot", "cosmos"],
  ["dots", "cosmos"],
  ["tinsel", "tinsel"],
  ["stripe", "tinsel"],
  ["stripes", "tinsel"],
  ["sheen", "sheen"],
  ["mirror", "sheen"],
  ["cracked", "cracked-ice"],
  ["crackedice", "cracked-ice"],
  ["ice", "cracked-ice"],
  ["crosshatch", "crosshatch"],
  ["cross", "crosshatch"],
  ["waterweb", "water-web"],
  ["water-web", "water-web"],
  ["web", "water-web"],
  ["sequin", "sequin"],
  ["sequins", "sequin"],
  ["firework", "fireworks"],
  ["fireworks", "fireworks"],
  ["plain", "plain"],
  ["foil", "plain"],
]);

export function normalizePattern(value) {
  if (!value) return undefined;
  const clean = String(value).toLowerCase().replace(/[^a-z0-9-]/g, "");
  if (HOLO_PATTERNS.includes(clean)) return clean;
  return aliases.get(clean);
}

export function detectHoloPattern({ filename, metadata = {} }) {
  const explicit = normalizePattern(metadata.holoPattern ?? metadata.holo ?? metadata.foil);
  if (explicit) return explicit;

  const name = filename.toLowerCase();
  for (const [alias, pattern] of aliases.entries()) {
    if (name.includes(alias)) return pattern;
  }

  return "plain";
}

export function detectCoverage({ metadata = {}, pattern }) {
  const coverage = String(metadata.holoCoverage ?? metadata.coverage ?? "").toLowerCase();
  if (["artwork", "full", "reverse"].includes(coverage)) return coverage;
  if (pattern === "cracked-ice" || pattern === "sheen") return "full";
  if (pattern === "cosmos") return "reverse";
  return "artwork";
}
