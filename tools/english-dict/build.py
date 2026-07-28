#!/usr/bin/env python3
"""Build the on-device English suggestion table.

Sources (both MIT):
  - hermitdave/FrequencyWords en_50k.txt — conversational unigrams (OpenSubtitles)
  - wolfgarbe/SymSpell frequency_bigramdictionary — next-word bigrams (Google Books ∩ SCOWL)

Attribution is a license condition; the app open-source notices must credit both.

    ZEN1 header (40 bytes, little endian)
      0  magic b"ZEN1"
      4  version u32
      8  unigramCount u32
      12 bigramCount u32
      16 unigramOffset u32
      20 bigramOffset u32
      24 poolOffset u32
      28 reserved u32
      32 totalUnigramWeight u64
    unigram (12 bytes), sorted by word bytes
      0  wordOffset u32
      4  weight u32          # log2(count+1)*1e6, order-preserving
      8  wordLen u16
      10 reserved u16
    bigram (16 bytes), sorted by prev bytes then weight descending
      0  prevOffset u32
      4  nextOffset u32
      8  weight u32
      12 prevLen u8
      13 nextLen u8
      14 reserved u16
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

MAGIC = b"ZEN1"
VERSION = 1
HEADER = struct.Struct("<4sIIIIIIIQ")
UNIGRAM = struct.Struct("<IIHH")
BIGRAM = struct.Struct("<III BBH")

DEFAULT_CORPORA = Path(__file__).resolve().parent / "corpora"
DEFAULT_OUT = (
    Path(__file__).resolve().parents[2]
    / "apps/ios/ZhigengCore/Resources/english.zed"
)


def pack_weight(count: int) -> int:
    """Compress corpus counts into u32 while preserving rank order."""
    return min(0xFFFFFFFF, int(math.log2(count + 1) * 1_000_000))


def load_unigrams(path: Path) -> list[tuple[str, int]]:
    rows: list[tuple[str, int]] = []
    with path.open(encoding="utf-8-sig") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) != 2:
                continue
            word, count_s = parts
            word = word.lower()
            if not word.isalpha():
                continue
            rows.append((word, pack_weight(int(count_s))))
    rows.sort(key=lambda r: r[0].encode("utf-8"))
    return rows


def load_bigrams(path: Path, known: set[str]) -> list[tuple[str, str, int]]:
    """Keep only bigrams whose words appear in the unigram table.

    Cross-source mismatch is expected (subtitles vs books). Dropping unknowns
    keeps next-word suggestions inside the vocabulary the completion bar knows.
    """
    rows: list[tuple[str, str, int]] = []
    with path.open(encoding="utf-8-sig") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) != 3:
                continue
            prev, nxt, count_s = parts
            prev, nxt = prev.lower(), nxt.lower()
            if prev not in known or nxt not in known:
                continue
            rows.append((prev, nxt, pack_weight(int(count_s))))
    # prev ascending, then weight descending so a scan yields ranked next-words.
    rows.sort(key=lambda r: (r[0].encode("utf-8"), -r[2], r[1].encode("utf-8")))
    return rows


def build(unigrams: list[tuple[str, int]], bigrams: list[tuple[str, str, int]]) -> bytes:
    pool = bytearray()
    offsets: dict[str, tuple[int, int]] = {}

    def intern(word: str) -> tuple[int, int]:
        if word in offsets:
            return offsets[word]
        raw = word.encode("utf-8")
        if len(raw) > 255:
            raise SystemExit(f"word too long for u8 length: {word!r}")
        off = len(pool)
        pool.extend(raw)
        offsets[word] = (off, len(raw))
        return offsets[word]

    uni_blob = bytearray()
    total = 0
    for word, weight in unigrams:
        off, length = intern(word)
        uni_blob.extend(UNIGRAM.pack(off, weight, length, 0))
        total += weight

    bi_blob = bytearray()
    for prev, nxt, weight in bigrams:
        po, pl = intern(prev)
        no, nl = intern(nxt)
        bi_blob.extend(BIGRAM.pack(po, no, weight, pl, nl, 0))

    uni_off = HEADER.size
    bi_off = uni_off + len(uni_blob)
    pool_off = bi_off + len(bi_blob)
    header = HEADER.pack(
        MAGIC,
        VERSION,
        len(unigrams),
        len(bigrams),
        uni_off,
        bi_off,
        pool_off,
        0,
        total,
    )
    return header + uni_blob + bi_blob + pool


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpora", type=Path, default=DEFAULT_CORPORA)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()

    uni_path = args.corpora / "en_50k.txt"
    bi_path = args.corpora / "frequency_bigramdictionary_en_243_342.txt"
    if not uni_path.exists() or not bi_path.exists():
        raise SystemExit(
            f"missing corpora in {args.corpora}\n"
            "download:\n"
            "  en_50k.txt from hermitdave/FrequencyWords (MIT)\n"
            "  frequency_bigramdictionary_en_243_342.txt from wolfgarbe/SymSpell (MIT)"
        )

    unigrams = load_unigrams(uni_path)
    known = {w for w, _ in unigrams}
    bigrams = load_bigrams(bi_path, known)
    blob = build(unigrams, bigrams)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(blob)
    print(
        f"wrote {args.out} ({len(blob)/1e6:.1f}MB) "
        f"unigrams={len(unigrams)} bigrams={len(bigrams)}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
