#!/usr/bin/env python3
"""Tune the composer's relaxed matching without waiting on Swift.

Reads the shipped `pinyin.zpd` (ZPD1, see build.py), mirrors what PinyinSpelling and
PinyinComposer do, and scores top-1/top-5 on perturbation sets generated from the table
itself: full pinyin, half-typed, mixed, fuzzy, initials-only, one-key typo.

Changing a cost constant and re-running takes five seconds, which is why the constants
live here first and get copied into Swift once they settle. The gate is the `full` row:
relaxation must not cost the people who spell correctly anything.

    python3 tools/pinyin-dict/probe.py
"""

import math
import random
import re
import struct
import time
from bisect import bisect_left
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ZPD = ROOT / "apps/ios/ZhigengCore/Resources/pinyin.zpd"
SEGMENTER = ROOT / "apps/ios/ZhigengCore/PinyinSegmenter.swift"

HEADER = struct.Struct("<4sIIQIII")
RECORD = struct.Struct("<IIIBBH")


# ---------------------------------------------------------------- dictionary

def load_zpd(path):
    raw = path.read_bytes()
    magic, version, count, total, rec_off, key_off, word_off = HEADER.unpack_from(raw, 0)
    assert magic == b"ZPD1" and version == 1, (magic, version)
    keys, words, weights = [], [], []
    unpack = RECORD.unpack_from
    for i in range(count):
        ko, wo, weight, klen, wlen, _ = unpack(raw, rec_off + i * 16)
        keys.append(raw[key_off + ko: key_off + ko + klen].decode())
        words.append(raw[word_off + wo: word_off + wo + wlen].decode())
        weights.append(weight)
    return keys, words, weights, total


class Table:
    def __init__(self, keys, words, weights, total):
        self.keys, self.words, self.weights = keys, words, weights
        self.total = total
        self.log_z = math.log(max(total, 2))

    def has_prefix(self, p):
        i = bisect_left(self.keys, p)
        return i < len(self.keys) and self.keys[i].startswith(p)

    def entries(self, key):
        i = bisect_left(self.keys, key)
        out = []
        while i < len(self.keys) and self.keys[i] == key:
            out.append((self.words[i], self.weights[i]))
            i += 1
        return out


# ---------------------------------------------------------------- syllables

def load_syllables():
    src = SEGMENTER.read_text()
    body = src.split("public static let standard: [String] = [", 1)[1].split("\n\t]", 1)[0]
    syls = re.findall(r'"([a-zü]+)"', body)
    return sorted({s.replace("ü", "v") for s in syls})


SYLLABLES = load_syllables()
SYL_SET = set(SYLLABLES)
# prefix -> syllables starting with it
BY_PREFIX = {}
for s in SYLLABLES:
    for n in range(1, len(s) + 1):
        BY_PREFIX.setdefault(s[:n], []).append(s)

FUZZY_PAIRS = [("z", "zh"), ("c", "ch"), ("s", "sh"), ("n", "l"), ("f", "h")]
FUZZY_FINALS = [("an", "ang"), ("en", "eng"), ("in", "ing")]


def fuzzy_variants(syl):
    out = set()
    for a, b in FUZZY_PAIRS:
        if syl.startswith(a) and not syl.startswith(b):
            v = b + syl[len(a):]
            if v in SYL_SET:
                out.add(v)
        if syl.startswith(b):
            v = a + syl[len(b):]
            if v in SYL_SET:
                out.add(v)
    for a, b in FUZZY_FINALS:
        if syl.endswith(a) and not syl.endswith(b):
            v = syl[: -len(a)] + b
            if v in SYL_SET:
                out.add(v)
        if syl.endswith(b):
            v = syl[: -len(b)] + a
            if v in SYL_SET:
                out.add(v)
    out.discard(syl)
    return out


NEIGHBORS = {}
for row in ("qwertyuiop", "asdfghjkl", "zxcvbnm"):
    for i, ch in enumerate(row):
        NEIGHBORS.setdefault(ch, set())
        if i:
            NEIGHBORS[ch].add(row[i - 1])
        if i + 1 < len(row):
            NEIGHBORS[ch].add(row[i + 1])


def edit1(seg):
    """Syllables one adjacent-key substitution / transposition / insertion away."""
    out = set()
    for i, ch in enumerate(seg):
        for n in NEIGHBORS.get(ch, ()):
            v = seg[:i] + n + seg[i + 1:]
            if v in SYL_SET:
                out.add(v)
    for i in range(len(seg) - 1):
        v = seg[:i] + seg[i + 1] + seg[i] + seg[i + 2:]
        if v in SYL_SET:
            out.add(v)
    for i in range(len(seg)):  # user typed one letter too many
        v = seg[:i] + seg[i + 1:]
        if v in SYL_SET:
            out.add(v)
    out.discard(seg)
    return out


# ---------------------------------------------------------------- relaxation

COST_EXACT = 0.0
COST_PREFIX = {1: -3.0, 2: -1.5}   # by letters consumed; >=3 uses -1.0
COST_PREFIX_LONG = -1.0
COST_FUZZY = -2.0
COST_TYPO = -6.0
BEAM = 64
MAX_SYL = 6


EXACT_ONLY = False


def options(typed, pos, allow_typo):
    """(consumed, [syllable], cost) for the slot starting at pos."""
    out = []
    for n in range(1, min(MAX_SYL, len(typed) - pos) + 1):
        seg = typed[pos: pos + n]
        if seg in SYL_SET:
            out.append((n, [seg], COST_EXACT))
            for v in fuzzy_variants(seg):
                out.append((n, [v], COST_FUZZY))
        if EXACT_ONLY:
            continue
        expand = BY_PREFIX.get(seg)
        if expand:
            cost = COST_PREFIX.get(n, COST_PREFIX_LONG)
            longer = [s for s in expand if s != seg]
            if longer:
                out.append((n, longer, cost, True))
        if allow_typo and len(seg) >= 2:
            for v in edit1(seg):
                out.append((n, [v], COST_TYPO))
    return [o if len(o) == 4 else (*o, False) for o in out]


def search(table, typed, allow_typo=False):
    """Keys reachable from `typed`, each with its relaxation cost."""
    n = len(typed)
    layers = [dict() for _ in range(n + 1)]  # pos -> {key: (best cost, invented letters?)}
    layers[0][""] = (0.0, False)
    done = {}
    probes = 0
    for pos in range(n):
        layer = layers[pos]
        if not layer:
            continue
        if len(layer) > BEAM:
            layer = dict(sorted(layer.items(), key=lambda kv: -kv[1][0])[:BEAM])
        for key, (cost, invented) in layer.items():
            for consumed, syls, c, inv in options(typed, pos, allow_typo):
                nxt = pos + consumed
                for s in syls:
                    nk = key + s
                    probes += 1
                    if not table.has_prefix(nk):
                        continue
                    state = (cost + c, invented or inv)
                    if nxt == n and done.get(nk, (-1e9,))[0] < state[0]:
                        done[nk] = state
                    if layers[nxt].get(nk, (-1e9,))[0] < state[0]:
                        layers[nxt][nk] = state
    return done, probes


DEMOTE_WHEN_EXACT = -2.0


def candidates(table, typed, allow_typo=False, limit=9):
    keys, probes = search(table, typed, allow_typo)
    # If the user typed something that parses exactly, their spelling wins the top of
    # the bar; relaxed readings stay available but drop below it.
    has_exact = any(cost == 0.0 for cost, _ in keys.values())
    scored = {}
    for key, (cost, invented) in keys.items():
        for word, weight in table.entries(key):
            s = math.log(max(weight, 1)) + cost
            if has_exact and invented:
                s += DEMOTE_WHEN_EXACT
            if scored.get(word, -1e9) < s:
                scored[word] = s
    ranked = sorted(scored.items(), key=lambda kv: -kv[1])
    return [w for w, _ in ranked[:limit]], probes


# ---------------------------------------------------------------- eval sets

def split_key(key, count):
    """Split a key into exactly `count` syllables. None if impossible."""
    memo = {}

    def go(i, left):
        if i == len(key):
            return [] if left == 0 else None
        if left == 0:
            return None
        if (i, left) in memo:
            return memo[(i, left)]
        for n in range(min(MAX_SYL, len(key) - i), 0, -1):
            seg = key[i: i + n]
            if seg in SYL_SET:
                rest = go(i + n, left - 1)
                if rest is not None:
                    memo[(i, left)] = [seg] + rest
                    return memo[(i, left)]
        memo[(i, left)] = None
        return None

    return go(0, count)


def build_cases(table, sample=600, seed=7):
    rng = random.Random(seed)
    rows = sorted(
        (
            (w, table.words[i], table.keys[i])
            for i, w in enumerate(table.weights)
            if 2 <= len(table.words[i]) <= 4
        ),
        key=lambda r: -r[0],
    )[: sample * 3]
    cases = []
    for _, word, key in rows:
        syls = split_key(key, len(word))
        if not syls or "".join(syls) != key:
            continue
        cases.append((word, key, syls))
        if len(cases) >= sample:
            break
    out = {"full": [], "abbrev": [], "mixed": [], "half": [], "fuzzy": [], "typo": []}
    for word, key, syls in cases:
        out["full"].append((word, key))
        out["abbrev"].append((word, "".join(s[0] for s in syls)))
        out["mixed"].append((word, syls[0] + "".join(s[0] for s in syls[1:])))
        out["half"].append((word, "".join(syls[:-1]) + syls[-1][: max(1, len(syls[-1]) // 2)]))
        i = rng.randrange(len(syls))
        v = sorted(fuzzy_variants(syls[i]))
        if v:
            out["fuzzy"].append((word, "".join(syls[:i]) + rng.choice(v) + "".join(syls[i + 1:])))
        j = rng.randrange(len(key))
        nb = sorted(NEIGHBORS.get(key[j], ()))
        if nb:
            out["typo"].append((word, key[:j] + rng.choice(nb) + key[j + 1:]))
    return out


def run(table, cases, allow_typo, label):
    hit1 = hit5 = 0
    probes_total = 0
    t0 = time.perf_counter()
    for word, typed in cases:
        cands, probes = candidates(table, typed, allow_typo)
        probes_total += probes
        if cands[:1] == [word]:
            hit1 += 1
        if word in cands[:5]:
            hit5 += 1
    dt = (time.perf_counter() - t0) / max(len(cases), 1)
    print(
        f"  {label:8s} n={len(cases):4d}  top1={hit1 / len(cases):5.1%}  "
        f"top5={hit5 / len(cases):5.1%}  {dt * 1000:6.1f}ms  probes={probes_total // len(cases)}"
    )


def main():
    print("loading table ...", flush=True)
    t0 = time.perf_counter()
    table = Table(*load_zpd(ZPD))
    print(f"  {len(table.keys)} records in {time.perf_counter() - t0:.1f}s")

    print("\nsanity:")
    for typed in ("shashihou", "shashih", "ssh", "shsh", "shashihih", "jinqiu", "zaiganma"):
        cands, probes = candidates(table, typed, allow_typo=False)
        print(f"  {typed:12s} -> {' '.join(cands[:6])}   ({probes} probes)")
    for typed in ("shashihpu", "sahshihou", "shashihih"):
        cands, probes = candidates(table, typed, allow_typo=True)
        print(f"  {typed:12s} +typo -> {' '.join(cands[:6])}   ({probes} probes)")

    print("\nbuilding cases ...", flush=True)
    cases = build_cases(table)

    global EXACT_ONLY
    EXACT_ONLY = True
    print("\nbaseline (今天线上的精确匹配):")
    for label in ("full", "half", "mixed", "abbrev", "typo"):
        run(table, cases[label], False, label)

    EXACT_ONLY = False
    print("\nrelaxed:")
    for label in ("full", "half", "mixed", "fuzzy", "abbrev"):
        run(table, cases[label], False, label)
    run(table, cases["typo"], True, "typo")


if __name__ == "__main__":
    main()
