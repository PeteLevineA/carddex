#!/usr/bin/env python3
import argparse
import json
import math
import os
import shutil
import struct
import zlib
from pathlib import Path

CARD_WIDTH = 900
CARD_HEIGHT = 1260
DEFAULT_ARTWORK_REGION = {"x": 0.093, "y": 0.518, "w": 0.814, "h": 0.341}

HOLO_ALIASES = {
    "star": "starlight",
    "stars": "starlight",
    "starlight": "starlight",
    "galaxy": "cosmos",
    "cosmos": "cosmos",
    "dot": "cosmos",
    "dots": "cosmos",
    "tinsel": "tinsel",
    "stripe": "tinsel",
    "stripes": "tinsel",
    "sheen": "sheen",
    "mirror": "sheen",
    "cracked": "cracked-ice",
    "ice": "cracked-ice",
    "crosshatch": "crosshatch",
    "waterweb": "water-web",
    "water-web": "water-web",
    "web": "water-web",
    "sequin": "sequin",
    "sequins": "sequin",
    "firework": "fireworks",
    "fireworks": "fireworks",
    "plain": "plain",
}


def main():
    parser = argparse.ArgumentParser(description="Dependency-free card ingestion fallback.")
    parser.add_argument("image", help="Path to a PNG card image")
    parser.add_argument("--id", help="Card id slug")
    parser.add_argument("--name", help="Card display name")
    parser.add_argument("--subtitle", default="Processed physical card scan")
    parser.add_argument("--set", dest="set_name", default="Imported Cards")
    parser.add_argument("--rarity", default="Imported")
    parser.add_argument("--number", default="000/000")
    parser.add_argument("--holo-pattern", default="starlight")
    parser.add_argument("--holo-coverage", default="artwork", choices=["artwork", "full", "reverse"])
    parser.add_argument("--catalog", default="cards/catalog.json")
    parser.add_argument("--output", default="cards")
    args = parser.parse_args()

    image_path = Path(args.image)
    card_id = slug(args.id or image_path.stem)
    card_name = args.name or title_from_slug(card_id)
    out_dir = Path(args.output) / card_id
    out_dir.mkdir(parents=True, exist_ok=True)

    card_path = out_dir / "card.png"
    expanded_path = out_dir / "expanded.svg"
    depth_path = out_dir / "depth.svg"
    expanded_depth_path = out_dir / "expanded-depth.svg"

    shutil.copyfile(image_path, card_path)
    write_depth_svg(depth_path, DEFAULT_ARTWORK_REGION)
    write_expanded_svg(expanded_path, f"/cards/{card_id}/card.png", card_name)
    write_expanded_depth_svg(expanded_depth_path)

    catalog_path = Path(args.catalog)
    catalog = read_json(catalog_path, [])
    record = {
        "id": card_id,
        "name": card_name,
        "subtitle": args.subtitle,
        "set": args.set_name,
        "rarity": args.rarity,
        "number": args.number,
        "image": f"/cards/{card_id}/card.png",
        "depth": f"/cards/{card_id}/depth.svg",
        "expandedImage": f"/cards/{card_id}/expanded.svg",
        "expandedDepth": f"/cards/{card_id}/expanded-depth.svg",
        "holoPattern": normalize_pattern(args.holo_pattern),
        "holoCoverage": args.holo_coverage,
        "artworkRegion": DEFAULT_ARTWORK_REGION,
        "depthScale": 0.13,
        "foilStrength": 1.18,
        "accent": "#f36b31",
        "processedAt": "2026-04-24T00:00:00.000Z",
        "sourceImage": os.path.relpath(image_path, Path.cwd()),
    }
    next_catalog = [card for card in catalog if card.get("id") != card_id]
    next_catalog.append(record)
    next_catalog.sort(key=lambda card: card.get("name", ""))
    catalog_path.write_text(json.dumps(next_catalog, indent=2) + "\n", encoding="utf-8")
    print(f"Processed {card_id}")


def write_depth_svg(path, rect):
    art_x = rect["x"] * CARD_WIDTH
    art_y = (1 - rect["y"] - rect["h"]) * CARD_HEIGHT
    art_w = rect["w"] * CARD_WIDTH
    art_h = rect["h"] * CARD_HEIGHT
    path.write_text(
        f"""<svg xmlns="http://www.w3.org/2000/svg" width="{CARD_WIDTH}" height="{CARD_HEIGHT}" viewBox="0 0 {CARD_WIDTH} {CARD_HEIGHT}">
  <defs>
    <radialGradient id="card" cx=".5" cy=".48" r=".72">
      <stop offset="0" stop-color="#8e8e8e"/>
      <stop offset=".66" stop-color="#3c3c3c"/>
      <stop offset="1" stop-color="#151515"/>
    </radialGradient>
    <radialGradient id="art" cx=".5" cy=".46" r=".58">
      <stop offset="0" stop-color="#f0f0f0"/>
      <stop offset=".48" stop-color="#a6a6a6"/>
      <stop offset="1" stop-color="#333"/>
    </radialGradient>
  </defs>
  <rect width="{CARD_WIDTH}" height="{CARD_HEIGHT}" rx="44" fill="#151515"/>
  <rect x="42" y="42" width="816" height="1176" rx="32" fill="url(#card)"/>
  <rect x="{art_x:.1f}" y="{art_y:.1f}" width="{art_w:.1f}" height="{art_h:.1f}" rx="24" fill="url(#art)"/>
  <ellipse cx="442" cy="480" rx="148" ry="210" fill="#ececec"/>
  <path d="M319 636 C404 576 508 578 596 642 C530 686 386 684 319 636 Z" fill="#bdbdbd"/>
  <path d="M254 502 C309 388 385 309 492 263 C460 390 413 502 338 620 Z" fill="#d9d9d9"/>
  <path d="M557 302 C642 392 675 506 638 648 C596 536 550 442 486 360 Z" fill="#a5a5a5"/>
</svg>
""",
        encoding="utf-8",
    )


def write_expanded_svg(path, card_image, card_name):
    safe_name = escape_xml(card_name)
    path.write_text(
        f"""<svg xmlns="http://www.w3.org/2000/svg" width="{CARD_WIDTH}" height="{CARD_HEIGHT}" viewBox="0 0 {CARD_WIDTH} {CARD_HEIGHT}">
  <defs>
    <radialGradient id="sky" cx=".5" cy=".36" r=".82">
      <stop offset="0" stop-color="#fff7af"/>
      <stop offset=".35" stop-color="#ff9a45"/>
      <stop offset=".68" stop-color="#4bb86a"/>
      <stop offset="1" stop-color="#18395d"/>
    </radialGradient>
    <filter id="blur"><feGaussianBlur stdDeviation="22"/></filter>
    <clipPath id="round"><rect x="110" y="118" width="680" height="952" rx="34"/></clipPath>
  </defs>
  <rect width="{CARD_WIDTH}" height="{CARD_HEIGHT}" fill="url(#sky)"/>
  <g filter="url(#blur)" opacity=".52">
    <circle cx="213" cy="301" r="180" fill="#fff6a8"/>
    <circle cx="720" cy="454" r="230" fill="#3ed07e"/>
    <circle cx="404" cy="1050" r="260" fill="#ff713b"/>
  </g>
  <path d="M0 1010 C158 888 284 862 438 944 C587 1024 710 1017 900 896 L900 1260 L0 1260 Z" fill="#203b25" opacity=".78"/>
  <path d="M54 836 C194 737 333 719 462 780 C602 847 725 832 870 720 L900 1260 L0 1260 Z" fill="#f5c85a" opacity=".48"/>
  <g clip-path="url(#round)">
    <image href="{card_image}" x="110" y="118" width="680" height="952" preserveAspectRatio="xMidYMid slice" opacity=".76"/>
  </g>
  <rect x="110" y="118" width="680" height="952" rx="34" fill="none" stroke="#fff4aa" stroke-width="6" opacity=".34"/>
  <text x="450" y="1136" text-anchor="middle" fill="#fff7df" font-family="Verdana, Arial, sans-serif" font-size="34" font-weight="700" opacity=".92">{safe_name}</text>
</svg>
""",
        encoding="utf-8",
    )


def write_expanded_depth_svg(path):
    path.write_text(
        f"""<svg xmlns="http://www.w3.org/2000/svg" width="{CARD_WIDTH}" height="{CARD_HEIGHT}" viewBox="0 0 {CARD_WIDTH} {CARD_HEIGHT}">
  <defs>
    <radialGradient id="d" cx=".5" cy=".46" r=".78">
      <stop offset="0" stop-color="#cfcfcf"/>
      <stop offset=".62" stop-color="#555"/>
      <stop offset="1" stop-color="#111"/>
    </radialGradient>
  </defs>
  <rect width="{CARD_WIDTH}" height="{CARD_HEIGHT}" fill="url(#d)"/>
  <ellipse cx="450" cy="510" rx="190" ry="286" fill="#efefef"/>
  <path d="M235 874 C360 760 526 767 669 900 C551 970 350 964 235 874 Z" fill="#777"/>
  <path d="M168 740 C312 628 451 590 596 651 C520 778 401 856 259 914 Z" fill="#adadad"/>
</svg>
""",
        encoding="utf-8",
    )


def read_json(path, fallback):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return fallback


def normalize_pattern(value):
    key = "".join(ch for ch in value.lower() if ch.isalnum() or ch == "-")
    return HOLO_ALIASES.get(key, key if key in set(HOLO_ALIASES.values()) else "plain")


def slug(value):
    out = []
    previous_dash = False
    for ch in value.lower().strip():
        if ch.isalnum():
            out.append(ch)
            previous_dash = False
        elif not previous_dash:
            out.append("-")
            previous_dash = True
    return "".join(out).strip("-")


def title_from_slug(value):
    return " ".join(part.capitalize() for part in value.split("-") if part)


def escape_xml(value):
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("'", "&apos;")
    )


if __name__ == "__main__":
    main()
