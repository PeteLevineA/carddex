// Shared catalog helpers. The web app and any Node-side tooling import these
// to ensure they are working with the same shape as the iOS Codable types.
import schema from "./schema.json" with { type: "json" };

export const HoloPatterns = Object.freeze([
  "starlight", "cosmos", "tinsel", "sheen", "cracked-ice",
  "crosshatch", "water-web", "sequin", "fireworks", "plain", "none",
]);

export const HoloCoverages = Object.freeze([
  "artwork", "full", "reverse",
]);

/**
 * Lightweight runtime validator. We keep this dependency-free; switch to ajv
 * if/when we need full JSON Schema validation.
 * @returns {{ ok: true } | { ok: false, errors: string[] }}
 */
export function validateCatalog(value) {
  const errors = [];
  if (!Array.isArray(value)) {
    return { ok: false, errors: ["catalog must be an array"] };
  }
  value.forEach((card, i) => {
    if (!card || typeof card !== "object") {
      errors.push(`#${i}: not an object`);
      return;
    }
    for (const key of ["id", "name", "image", "depth"]) {
      if (typeof card[key] !== "string" || card[key].length === 0) {
        errors.push(`#${i}: missing required string ${key}`);
      }
    }
    if (card.holoPattern && !HoloPatterns.includes(card.holoPattern)) {
      errors.push(`#${i}: unknown holoPattern ${card.holoPattern}`);
    }
    if (card.holoCoverage && !HoloCoverages.includes(card.holoCoverage)) {
      errors.push(`#${i}: unknown holoCoverage ${card.holoCoverage}`);
    }
  });
  return errors.length === 0 ? { ok: true } : { ok: false, errors };
}

export { schema };
