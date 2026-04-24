import fs from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import OpenAI, { toFile } from "openai";

const DEFAULT_MODEL = process.env.OPENAI_IMAGE_MODEL || "gpt-image-2";

export async function generateExpandedArt(inputPath, outputPath, options = {}) {
  assertOpenAIKey();
  const client = new OpenAI();
  const prompt =
    options.prompt ??
    [
      "Create an expanded full-art Pokemon trading card illustration from this card scan.",
      "Remove the trading card frame, type text, attack text, HP, rarity marks, and all surrounding UI.",
      "Preserve the subject, lighting direction, palette, and composition cues from the artwork window.",
      "Extend the illustration to a full vertical 5:7 card-art canvas with rich background detail.",
      "Do not include text, logos, borders, watermarks, or card interface elements.",
    ].join(" ");

  const response = await client.images.edit({
    model: options.model ?? DEFAULT_MODEL,
    image: await imageFile(inputPath),
    prompt,
    size: options.size ?? "1024x1536",
    quality: options.quality ?? "high",
  });

  await writeFile(outputPath, await extractImageBuffer(response));
}

export async function generateExpandedDepthMap(inputPath, outputPath, options = {}) {
  assertOpenAIKey();
  const client = new OpenAI();
  const prompt =
    options.prompt ??
    [
      "Create a grayscale depth map for this expanded card artwork.",
      "White is closest to the viewer, black is farthest away.",
      "Keep the composition exactly aligned with the source image.",
      "Use smooth matte grayscale shading only. No text, color, borders, UI, or decorative effects.",
    ].join(" ");

  const response = await client.images.edit({
    model: options.model ?? DEFAULT_MODEL,
    image: await imageFile(inputPath),
    prompt,
    size: options.size ?? "1024x1536",
    quality: options.quality ?? "high",
  });

  await writeFile(outputPath, await extractImageBuffer(response));
}

async function imageFile(filePath) {
  return toFile(fs.createReadStream(filePath), path.basename(filePath), {
    type: mimeType(filePath),
  });
}

async function extractImageBuffer(response) {
  const item = response?.data?.[0] ?? response?.output?.[0];
  const b64 = item?.b64_json ?? item?.image_base64 ?? item?.content?.[0]?.image_base64;
  if (b64) return Buffer.from(b64, "base64");

  const url = item?.url;
  if (url) {
    const fetched = await fetch(url);
    if (!fetched.ok) throw new Error(`Image URL fetch failed: ${fetched.status}`);
    return Buffer.from(await fetched.arrayBuffer());
  }

  throw new Error("OpenAI image response did not contain image data");
}

function assertOpenAIKey() {
  if (!process.env.OPENAI_API_KEY) {
    throw new Error("OPENAI_API_KEY is required for AI expanded art generation");
  }
}

function mimeType(filePath) {
  const extension = path.extname(filePath).toLowerCase();
  if (extension === ".jpg" || extension === ".jpeg") return "image/jpeg";
  if (extension === ".webp") return "image/webp";
  return "image/png";
}
