import sharp from "sharp";

export const CARD_SIZE = {
  width: 900,
  height: 1260,
};

export const DEFAULT_ARTWORK_REGION = {
  x: 0.093,
  y: 0.518,
  w: 0.814,
  h: 0.341,
};

export async function normalizeCardImage(inputPath, outputPath, size = CARD_SIZE) {
  await sharp(inputPath)
    .rotate()
    .resize(size.width, size.height, {
      fit: "contain",
      background: { r: 9, g: 10, b: 13, alpha: 1 },
    })
    .png()
    .toFile(outputPath);
}

export async function createDepthMap(inputPath, outputPath, options = {}) {
  const size = options.size ?? CARD_SIZE;
  const artworkRegion = options.artworkRegion ?? DEFAULT_ARTWORK_REGION;
  const { data } = await sharp(inputPath)
    .resize(size.width, size.height, { fit: "cover" })
    .greyscale()
    .normalise()
    .blur(0.4)
    .raw()
    .toBuffer({ resolveWithObject: true });

  const output = Buffer.alloc(size.width * size.height);
  for (let y = 0; y < size.height; y += 1) {
    for (let x = 0; x < size.width; x += 1) {
      const index = y * size.width + x;
      const u = x / (size.width - 1);
      const v = 1 - y / (size.height - 1);
      const luminance = data[index] / 255;
      const center = 1 - clamp(distance(u, v, 0.5, 0.52) / 0.72, 0, 1);
      const edge = 1 - Math.min(u, v, 1 - u, 1 - v) * 7.5;
      const art = rectSoftMask(u, v, artworkRegion);
      const relief = 0.17 + luminance * 0.5 + center * 0.18 + art * 0.13 - clamp(edge, 0, 1) * 0.16;
      output[index] = Math.round(clamp(relief, 0, 1) * 255);
    }
  }

  await sharp(output, {
    raw: {
      width: size.width,
      height: size.height,
      channels: 1,
    },
  })
    .png()
    .toFile(outputPath);
}

export async function createFallbackExpandedArt(inputPath, outputPath, options = {}) {
  const size = options.size ?? CARD_SIZE;
  const artworkRegion = options.artworkRegion ?? DEFAULT_ARTWORK_REGION;
  const crop = rectToPixels(artworkRegion, size);
  const cropped = sharp(inputPath).extract(crop);
  const background = await cropped
    .clone()
    .resize(size.width, size.height, { fit: "cover" })
    .blur(18)
    .modulate({ brightness: 0.72, saturation: 1.15 })
    .png()
    .toBuffer();
  const foreground = await cropped
    .resize(size.width, size.height, { fit: "cover" })
    .png()
    .toBuffer();

  await sharp(background)
    .composite([{ input: foreground, blend: "screen", opacity: 0.72 }])
    .png()
    .toFile(outputPath);
}

export function rectToPixels(rect, size = CARD_SIZE) {
  const left = Math.round(rect.x * size.width);
  const top = Math.round((1 - rect.y - rect.h) * size.height);
  const width = Math.round(rect.w * size.width);
  const height = Math.round(rect.h * size.height);
  return {
    left: clamp(left, 0, size.width - 1),
    top: clamp(top, 0, size.height - 1),
    width: clamp(width, 1, size.width - left),
    height: clamp(height, 1, size.height - top),
  };
}

function rectSoftMask(u, v, rect) {
  const left = smoothstep(rect.x, rect.x + 0.035, u);
  const right = 1 - smoothstep(rect.x + rect.w - 0.035, rect.x + rect.w, u);
  const bottom = smoothstep(rect.y, rect.y + 0.035, v);
  const top = 1 - smoothstep(rect.y + rect.h - 0.035, rect.y + rect.h, v);
  return clamp(left * right * bottom * top, 0, 1);
}

function smoothstep(edge0, edge1, x) {
  const t = clamp((x - edge0) / (edge1 - edge0), 0, 1);
  return t * t * (3 - 2 * t);
}

function distance(x1, y1, x2, y2) {
  return Math.hypot(x1 - x2, y1 - y2);
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}
