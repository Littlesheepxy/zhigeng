#!/usr/bin/env python3
"""Build the on-device pinyin dictionary from permissively licensed sources.

Source: the Wanxiang (万象) RIME dictionaries, CC-BY 4.0.
    https://github.com/amzxyz/RIME-LMDG
Attribution is a license condition -- the app's open source notices must credit it.

Wanxiang ships `word \t toned pinyin \t weight` rows built from a 32GB corpus, which
gets us three things jieba+pypinyin could not: readings annotated per word (so
polyphones are already resolved in context), weights that are real corpus counts
rather than segmentation priors, and one source instead of two.

Weights are used as linear frequencies. Their README calls them "对数归一化" but
measured against an independent frequency list the log of these weights is what
correlates (r=0.56 vs 0.21), so the composer's log() is the right transform.

Output is a single sorted record table plus two string pools, laid out so the Swift
side can mmap it and answer both "is this a key prefix" and "what words have this key"
with one binary search. See ZhigengCore/PinyinFileDictionary.swift for the reader.

    ZPD1 header (32 bytes, little endian)
      0  magic b"ZPD1"
      4  version u32
      8  recordCount u32
      12 totalWeight u64
      20 recordsOffset u32
      24 keyPoolOffset u32
      28 wordPoolOffset u32
    record (16 bytes), sorted by key bytes then weight descending
      0  keyOffset u32
      4  wordOffset u32
      8  weight u32
      12 keyLen u8
      13 wordLen u8
      14 reserved u16
"""

import argparse
import struct
import sys
import unicodedata
from pathlib import Path

MAGIC = b"ZPD1"
VERSION = 1
HEADER = struct.Struct("<4sIIQIII")
RECORD = struct.Struct("<IIIBBH")

# Longer phrases are almost never typed in full and cost a lot of table.
MAX_WORD_CHARS = 8
# Measured on the sentence probe: accuracy is flat from here up to no pruning at all
# (the rare tail mostly adds noise), and falls off below -- at 500 the table has already
# lost 卡号 and 银杏树. 300 keeps 761k rows, 25MB mmapped, 10MB compressed.
DEFAULT_MIN_WEIGHT = 300
# Tone diacritics. The diaeresis of ü is deliberately not here: it distinguishes
# lü from lu, and has to survive long enough to become the letter v.
TONE_MARKS = {"\u0304", "\u0301", "\u030c", "\u0300"}
# Single characters, then 2-4 character words. The 5+ character list (lianxiang) is
# left out: the Viterbi composes those from shorter words at a fraction of the size.
SOURCES = ("zi.dict.yaml", "jichu.dict.yaml")


def to_keys(toned: str) -> str:
    """`nǚ ér` -> `nver`. Keys are letters as typed, with ü written v."""
    stripped = "".join(
        ch for ch in unicodedata.normalize("NFD", toned) if ch not in TONE_MARKS
    )
    return unicodedata.normalize("NFC", stripped).replace("ü", "v").replace(" ", "")


def key_variants(toned: str) -> list[str]:
    """Canonical key plus how people type nasal interjections.

    Wanxiang annotates 嗯 as n/ng (the phonetic reality). Phone users type en.
    Without the alias, en/enen/enne land on 恩/恩恩/恩呢.
    """
    syllables = [to_keys(part) for part in toned.split()]
    if not syllables:
        return []
    variants: list[list[str]] = [[]]
    for syllable in syllables:
        options = [syllable]
        if syllable in ("n", "ng"):
            options.append("en")
        variants = [head + [option] for head in variants for option in options]
    # Preserve order, drop duplicates (n-only words still emit a single en).
    seen: set[str] = set()
    keys: list[str] = []
    for parts in variants:
        key = "".join(parts)
        if key and key not in seen:
            seen.add(key)
            keys.append(key)
    return keys


def is_han(text: str) -> bool:
    return all("\u4e00" <= ch <= "\u9fff" for ch in text)


def wanxiang_rows(dicts_dir: Path):
    """Yield (word, toned pinyin, weight) from the Wanxiang dictionary files."""
    for name in SOURCES:
        path = dicts_dir / name
        if not path.exists():
            raise SystemExit(f"missing {path}\nsee {__doc__.splitlines()[3].strip()}")
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 3 or not parts[2].isdigit():
                    continue
                yield parts[0], parts[1], int(parts[2])


def build_rows(dicts_dir: Path, min_weight: int):
    """Collapse to (key, word, weight). Tone variants of one reading are one key."""
    rows = {}
    for word, toned, weight in wanxiang_rows(dicts_dir):
        if not is_han(word) or len(word) > MAX_WORD_CHARS:
            continue
        for key in key_variants(toned):
            if not key.isascii() or not key.isalpha():
                continue
            # 啊 is listed once per tone; together they are how often it is read "a".
            rows[(key, word)] = rows.get((key, word), 0) + weight
    return [
        (key, word, weight)
        for (key, word), weight in rows.items()
        if weight >= min_weight
    ]


def write_dictionary(rows, out_path: Path):
    rows.sort(key=lambda row: (row[0].encode("ascii"), -row[2]))

    key_pool = bytearray()
    word_pool = bytearray()
    word_offsets = {}
    records = bytearray()
    previous_key = None
    key_offset = 0
    total_weight = 0

    for key, word, weight in rows:
        key_bytes = key.encode("ascii")
        if key != previous_key:
            key_offset = len(key_pool)
            key_pool += key_bytes
            previous_key = key

        word_bytes = word.encode("utf-8")
        if word not in word_offsets:
            word_offsets[word] = len(word_pool)
            word_pool += word_bytes

        records += RECORD.pack(
            key_offset, word_offsets[word], weight, len(key_bytes), len(word_bytes), 0
        )
        total_weight += weight

    records_offset = HEADER.size
    key_pool_offset = records_offset + len(records)
    word_pool_offset = key_pool_offset + len(key_pool)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("wb") as handle:
        handle.write(
            HEADER.pack(
                MAGIC,
                VERSION,
                len(rows),
                total_weight,
                records_offset,
                key_pool_offset,
                word_pool_offset,
            )
        )
        handle.write(records)
        handle.write(key_pool)
        handle.write(word_pool)

    return {
        "records": len(rows),
        "words": len(word_offsets),
        "total_weight": total_weight,
        "bytes": out_path.stat().st_size,
        "key_pool": len(key_pool),
        "word_pool": len(word_pool),
    }


def main() -> int:
    here = Path(__file__).resolve()
    default_out = here.parents[2] / "apps/ios/ZhigengCore/Resources/pinyin.zpd"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=default_out)
    parser.add_argument(
        "--dicts",
        type=Path,
        default=here.parent / "corpora/wanxiang/dicts",
        help="unpacked dicts.zip from the Wanxiang releases",
    )
    parser.add_argument(
        "--min-weight",
        type=int,
        default=DEFAULT_MIN_WEIGHT,
        help="drop corpus entries rarer than this (raises quality, shrinks the table)",
    )
    args = parser.parse_args()

    rows = build_rows(args.dicts, args.min_weight)
    if not rows:
        print("no rows built", file=sys.stderr)
        return 1
    stats = write_dictionary(rows, args.out)
    print(f"wrote {args.out}")
    for name, value in stats.items():
        print(f"  {name}: {value:,}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
