"""
Rough prototype for wayfinder ticket #338 (Zero-crossing layout).

Replicates the voyage graph generation at the level of detail that matters for
crossings (layers of variable width 4-6; adjacent-layer forward edges; same-layer
laterals), then MEASURES crossings under two wiring strategies:

  RANDOM     - forward targets by uniform-random lane (mirrors generation.odin today)
  CONSTRAINED- forward targets assigned monotonically (StS-style planar invariant),
               laterals restricted to adjacent lanes

Crossing model matches how view.odin draws: straight lines between node centres,
x = layer, y = lane. So:
  * two forward edges (a->c),(b->d) between the same layer pair CROSS iff their
    lane order inverts: lane(a) < lane(b) but lane(c) > lane(d).
  * a same-layer lateral between lanes i,j passes THROUGH every node whose lane is
    strictly between i and j (|i-j|-1 nodes) - a straight vertical segment in one column.
"""

import random

LAYER_WIDTH_MIN, LAYER_WIDTH_MAX = 4, 6
ZONE_BUDGETS = (17, 17, 16)          # Coastal / Open_Sea / Deep, per generation.odin:17
OUT_DEGREE_MAX = 4                   # per generation.odin
LATERAL_EDGE_CHANCE = 0.15           # representative; exact value doesn't change the shape of the result


def partition_layers(budget, rng):
    layers = []
    remaining = budget
    while remaining > 0:
        w = min(remaining, rng.randint(LAYER_WIDTH_MIN, LAYER_WIDTH_MAX))
        if remaining - w in range(1, LAYER_WIDTH_MIN):   # avoid a stranded < MIN layer
            w = remaining
        layers.append(w)
        remaining -= w
    return layers


def build_layers(rng):
    widths = [1]  # Start
    for b in ZONE_BUDGETS:
        widths += partition_layers(b, rng)
    widths.append(1)  # Haven
    return widths


# ---- forward wiring strategies -----------------------------------------------

def wire_random(widths, rng):
    """Mirror generation.odin: out-guarantee + in-guarantee + capped extra branching,
    every target chosen by uniform-random lane."""
    fwd = []  # (layer, parent_lane, child_lane)
    for l in range(len(widths) - 1):
        wl, wl1 = widths[l], widths[l + 1]
        outdeg = [0] * wl
        indeg = [0] * wl1
        # out-guarantee
        for p in range(wl):
            c = rng.randrange(wl1)
            fwd.append((l, p, c)); outdeg[p] += 1; indeg[c] += 1
        # in-guarantee
        for c in range(wl1):
            if indeg[c] == 0:
                p = rng.randrange(wl)
                fwd.append((l, p, c)); outdeg[p] += 1; indeg[c] += 1
        # extra branching
        for p in range(wl):
            while outdeg[p] < OUT_DEGREE_MAX and rng.random() < 0.35:
                c = rng.randrange(wl1)
                fwd.append((l, p, c)); outdeg[p] += 1
    return fwd


def wire_constrained(widths, rng):
    """Planar-by-construction (monotone-tiling / caterpillar-forest condition).

    Tile the child lane axis into wl contiguous blocks, one per parent, adjacent
    blocks sharing exactly their boundary child. Parent p connects to block
    [start[p] .. start[p+1]] inclusive. Because the blocks are monotone and overlap
    only at a single shared boundary child, for any p1<p2 every child of p1 has lane
    <= every child of p2 -> no lane inversion -> provably ZERO forward crossings.
    This still gives branching (block width) and full coverage (blocks tile the axis)."""
    fwd = []
    for l in range(len(widths) - 1):
        wl, wl1 = widths[l], widths[l + 1]
        # monotone start points: start[0]=0 .. start[wl]=wl1-1, non-decreasing
        cuts = sorted(rng.randrange(wl1) for _ in range(wl - 1))
        start = [0] + cuts + [wl1 - 1]
        covered = set()
        for p in range(wl):
            s, e = start[p], max(start[p + 1], start[p])
            deg = 0
            for c in range(s, e + 1):          # inclusive -> shares boundary child with next parent
                if deg >= OUT_DEGREE_MAX:
                    break
                fwd.append((l, p, c)); covered.add(c); deg += 1
        # in-guarantee, monotone-safe: any child skipped by the degree cap attaches to its
        # own block's parent (c within [start[p], start[p+1]]) -> still no inversion.
        for c in range(wl1):
            if c not in covered:
                p = max(p for p in range(wl) if start[p] <= c)
                fwd.append((l, p, c)); covered.add(c)
    return fwd


def coverage_ok(widths, fwd):
    """Every non-Start node has >=1 incoming edge; every non-Haven node has >=1 outgoing."""
    outs = {l: set() for l in range(len(widths))}
    ins = {l: set() for l in range(len(widths))}
    for (l, p, c) in fwd:
        outs[l].add(p); ins[l + 1].add(c)
    for l in range(len(widths)):
        w = widths[l]
        if l > 0 and any(c not in ins[l] for c in range(w)):
            return False
        if l < len(widths) - 1 and any(p not in outs[l] for p in range(w)):
            return False
    return True


# ---- crossing measurement ----------------------------------------------------

def forward_crossings(fwd):
    by_layer = {}
    for (l, p, c) in fwd:
        by_layer.setdefault(l, []).append((p, c))
    total = 0
    for edges in by_layer.values():
        for i in range(len(edges)):
            for j in range(i + 1, len(edges)):
                (p1, c1), (p2, c2) = edges[i], edges[j]
                if p1 == p2 or c1 == c2:
                    continue
                if (p1 < p2) != (c1 < c2):
                    total += 1
    return total


def lateral_through_nodes(widths, rng, adjacent_only):
    through = 0
    for w in widths:
        for i in range(w):
            for j in range(i + 1, w):
                if rng.random() < LATERAL_EDGE_CHANCE:
                    if adjacent_only and j - i != 1:
                        continue
                    through += (j - i - 1)
    return through


def run(seeds=200):
    rand_fx = rand_lat = con_fx = con_lat = 0
    rand_fx_max = con_fx_max = 0
    total_nodes = 0
    con_all_connected = True
    for s in range(seeds):
        rng = random.Random(s)
        widths = build_layers(rng)
        total_nodes += sum(widths)
        rf = forward_crossings(wire_random(widths, random.Random(1000 + s)))
        con_fwd = wire_constrained(widths, random.Random(1000 + s))
        cf = forward_crossings(con_fwd)
        con_all_connected &= coverage_ok(widths, con_fwd)
        rl = lateral_through_nodes(widths, random.Random(2000 + s), adjacent_only=False)
        cl = lateral_through_nodes(widths, random.Random(2000 + s), adjacent_only=True)
        rand_fx += rf; con_fx += cf; rand_lat += rl; con_lat += cl
        rand_fx_max = max(rand_fx_max, rf); con_fx_max = max(con_fx_max, cf)
    print(f"seeds={seeds}  avg nodes/map={total_nodes/seeds:.1f}")
    print(f"{'':22}{'avg fwd crossings':>18}{'max fwd':>10}{'avg lateral thru-nodes':>24}")
    print(f"{'RANDOM (today)':22}{rand_fx/seeds:>18.2f}{rand_fx_max:>10}{rand_lat/seeds:>24.2f}")
    print(f"{'CONSTRAINED (planar)':22}{con_fx/seeds:>18.2f}{con_fx_max:>10}{con_lat/seeds:>24.2f}")
    print(f"constrained: every map fully connected (in/out guarantees held) = {con_all_connected}")


if __name__ == "__main__":
    run()
