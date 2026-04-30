#!/usr/bin/env python3
"""Build embedding + SQLite artifacts consumed by the iOS app at launch.

Reads `assets/catalog/cards.json` (produced by `npm run ingest:catalog`) and
emits:

  * assets/catalog/embeddings.bin   — packed float32 image embeddings
  * assets/catalog/carddex.sqlite   — sets and cards tables (with embedding offsets)

This script is a placeholder skeleton: real production use should plug in the
same Core ML model that ships in the iOS app so the embedding space is shared
between scan-time inference and the precomputed catalog index. We use a
deterministic SHA-256-derived embedding of the card id here so the artifact is
reproducible without any ML dependencies — note this is *not* a perceptual hash
and the output does not correlate with image similarity. The iOS scanner can
swap in a real model later.

Usage:
    python3 tools/build-embeddings.py [--limit N]
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import struct
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG_DIR = REPO_ROOT / "assets" / "catalog"
EMBEDDING_DIM = 64


def stable_embedding(card_id: str) -> list[float]:
    """Stable, deterministic 64-dim embedding from the card id."""
    digest = hashlib.sha256(card_id.encode("utf-8")).digest()
    # Repeat hash to fill EMBEDDING_DIM floats in [-1, 1].
    out: list[float] = []
    seed = digest
    while len(out) < EMBEDDING_DIM:
        seed = hashlib.sha256(seed).digest()
        for byte in seed:
            out.append((byte / 255.0) * 2.0 - 1.0)
            if len(out) == EMBEDDING_DIM:
                break
    return out


_REQUIRED_CARD_FIELDS = ("id", "setId", "number", "name")


def _has_required_fields(card: dict) -> bool:
    """True if the card row has every NOT NULL column filled in."""
    missing = [k for k in _REQUIRED_CARD_FIELDS if not card.get(k)]
    if missing:
        print(
            f"  skipping card {card.get('id') or '<no-id>'}: missing {missing}"
        )
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0,
                        help="Stop after N cards (0 = all).")
    args = parser.parse_args()

    cards_path = CATALOG_DIR / "cards.json"
    if not cards_path.exists():
        print(f"Run `npm run ingest:catalog` first; missing {cards_path}")
        return 1

    cards = json.loads(cards_path.read_text())
    if args.limit:
        cards = cards[: args.limit]

    embeddings_path = CATALOG_DIR / "embeddings.bin"
    sqlite_path = CATALOG_DIR / "carddex.sqlite"

    print(f"Writing {len(cards)} embeddings to {embeddings_path}")
    with open(embeddings_path, "wb") as f:
        for card in cards:
            for value in stable_embedding(card["id"]):
                f.write(struct.pack("<f", value))

    print(f"Writing SQLite to {sqlite_path}")
    if sqlite_path.exists():
        os.unlink(sqlite_path)
    conn = sqlite3.connect(sqlite_path)
    cur = conn.cursor()
    cur.executescript(
        """
        CREATE TABLE sets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            series TEXT,
            release_date TEXT,
            ptcgo_code TEXT
        );
        CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            set_id TEXT NOT NULL,
            number TEXT NOT NULL,
            name TEXT NOT NULL,
            rarity TEXT,
            small_image TEXT,
            embedding_offset INTEGER NOT NULL
        );
        CREATE INDEX cards_set_number ON cards(set_id, number);
        CREATE INDEX cards_name ON cards(name);
        """
    )

    sets_path = CATALOG_DIR / "sets.json"
    if sets_path.exists():
        sets = json.loads(sets_path.read_text())
        cur.executemany(
            "INSERT INTO sets VALUES (?,?,?,?,?)",
            [(s.get("id"), s.get("name"), s.get("series"), s.get("releaseDate"), s.get("ptcgoCode")) for s in sets],
        )

    cur.executemany(
        "INSERT INTO cards VALUES (?,?,?,?,?,?,?)",
        [
            (
                c["id"],
                c["setId"],
                c["number"],
                c["name"],
                c.get("rarity"),
                (c.get("images") or {}).get("small"),
                idx * EMBEDDING_DIM * 4,
            )
            for idx, c in enumerate(cards)
            if _has_required_fields(c)
        ],
    )
    conn.commit()
    conn.close()
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
