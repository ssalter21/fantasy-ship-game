"""Zoom into a capture shot, and diff two of them.

    python scripts/shot.py zoom 00-chart-table top-left --factor 3
    python scripts/shot.py diff 04-build 05-build-hover

When to reach for which, and why this is an instrument for 2D chrome rather than for
the 3D ship screen, are in `.claude/skills/run-game/SKILL.md` -- kept there rather
than restated here, so the two cannot drift apart.
"""

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops

SHOTS = Path(__file__).resolve().parent.parent / "docs" / "ui" / "shots"

# Fractions of the shot, so a name means the same thing at any resolution.
REGIONS = {
    "full": (0.0, 0.0, 1.0, 1.0),
    "top": (0.0, 0.0, 1.0, 0.5),
    "bottom": (0.0, 0.5, 1.0, 0.5),
    "left": (0.0, 0.0, 0.5, 1.0),
    "right": (0.5, 0.0, 0.5, 1.0),
    "top-left": (0.0, 0.0, 0.5, 0.5),
    "top-right": (0.5, 0.0, 0.5, 0.5),
    "bottom-left": (0.0, 0.5, 0.5, 0.5),
    "bottom-right": (0.5, 0.5, 0.5, 0.5),
    "centre": (0.25, 0.25, 0.5, 0.5),
}
REGIONS["center"] = REGIONS["centre"]

CHANGED_COLOUR = (255, 0, 255)  # magenta: in no game palette, so it can only mean changed
UNCHANGED_DIM = 4  # divisor on the base image, so the highlight is the only bright thing
GUTTER_COLOUR = (128, 128, 128)  # the side-by-side divider, deliberately not CHANGED_COLOUR


def resolve_shot(name):
    """Accept a path, or a bare shot name resolved against docs/ui/shots.

    Naming a directory means you meant that file; naming neither directory nor
    extension means the shots directory, and *only* it. A capture killed mid-walk
    strands `NN-*.png` in the repo root (see the run-game skill), and a stray one
    there must not quietly shadow the real shot of the same name.
    """
    if "/" in name or "\\" in name:
        candidates = (Path(name),)
    else:
        candidates = (SHOTS / f"{name}.png", SHOTS / name)
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    sys.exit(f"no such shot: {name} (tried {', '.join(str(c) for c in candidates)})")


def load(path):
    return Image.open(path).convert("RGB")


def resolve_region(region, size):
    """A named region or an explicit `x,y,w,h`, as a PIL crop box."""
    width, height = size
    if region in REGIONS:
        fx, fy, fw, fh = REGIONS[region]
        # Round the edges, never the origin and the size separately: rounded apart, a
        # half-width can land past the far edge, and PIL pads a crop that overruns with
        # black instead of failing -- a fabricated column that reads as a finding. Off
        # the edges, `left` and `right` also tile exactly on an odd width.
        return (
            round(fx * width),
            round(fy * height),
            round((fx + fw) * width),
            round((fy + fh) * height),
        )
    else:
        try:
            x, y, w, h = (int(part) for part in region.split(","))
        except ValueError:
            sys.exit(
                f"unknown region: {region}\n"
                f"named regions: {', '.join(sorted(REGIONS))}\n"
                f"or explicit pixels: x,y,w,h"
            )
        if w <= 0 or h <= 0:
            sys.exit(f"region {region} has no area")
        if x < 0 or y < 0 or x + w > width or y + h > height:
            sys.exit(f"region {region} falls outside the {width}x{height} shot")
    return (x, y, x + w, y + h)


def write(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)
    return path


def zoom(args):
    if args.factor < 1:
        sys.exit(f"factor must be at least 1, got {args.factor}")

    path = resolve_shot(args.shot)
    source = load(path)
    box = resolve_region(args.region, source.size)
    crop = source.crop(box)
    # Nearest neighbour, so a magnified pixel stays a hard-edged square.
    out = crop.resize(
        (crop.width * args.factor, crop.height * args.factor),
        Image.Resampling.NEAREST,
    )

    region_slug = args.region.replace(",", "-")
    destination = Path(args.out) if args.out else (
        SHOTS / "zoom" / f"{path.stem}-{region_slug}-{args.factor}x.png"
    )
    write(out, destination)
    print(
        f"{path.name} {box[0]},{box[1]} {crop.width}x{crop.height} "
        f"at {args.factor}x -> {destination} ({out.width}x{out.height})"
    )


def changed_mask(before, after):
    """Per-pixel max absolute channel delta, and the pixels where it is non-zero.

    Not `convert("L")` — that is luminance-weighted, which would all but hide a
    change confined to the blue channel, and this palette is mostly blues.
    """
    delta_rgb = ImageChops.difference(before, after)
    red, green, blue = delta_rgb.split()
    delta = ImageChops.lighter(ImageChops.lighter(red, green), blue)
    return delta, delta.point(lambda v: 255 if v else 0, mode="1")


def diff(args):
    before_path, after_path = resolve_shot(args.before), resolve_shot(args.after)
    before, after = load(before_path), load(after_path)
    if before.size != after.size:
        sys.exit(
            f"cannot diff different sizes: {before_path.name} is "
            f"{before.width}x{before.height}, {after_path.name} is "
            f"{after.width}x{after.height}"
        )

    delta, changed = changed_mask(before, after)
    pixels = sum(delta.histogram()[1:])
    if pixels == 0:
        # ASCII only: this console is cp1252 and mangles anything else.
        print(f"{before_path.name} and {after_path.name} are identical - nothing written")
        return

    stem = f"{before_path.stem}-vs-{after_path.stem}"
    out_dir = Path(args.out_dir) if args.out_dir else SHOTS / "diff"

    gap = 8
    side_by_side = Image.new(
        "RGB", (before.width * 2 + gap, before.height), GUTTER_COLOUR
    )
    side_by_side.paste(before, (0, 0))
    side_by_side.paste(after, (before.width + gap, 0))
    side_path = write(side_by_side, out_dir / f"{stem}-side-by-side.png")

    base = after.convert("L").point(lambda v: v // UNCHANGED_DIM).convert("RGB")
    highlight = Image.new("RGB", after.size, CHANGED_COLOUR)
    mask_path = write(
        Image.composite(highlight, base, changed), out_dir / f"{stem}-mask.png"
    )

    total = before.width * before.height
    left, top, right, bottom = changed.getbbox()
    print(
        f"{pixels} of {total} pixels changed ({100 * pixels / total:.2f}%), "
        f"max channel delta {delta.getextrema()[1]}"
    )
    # Printed in the region grammar, so it pastes straight back into `zoom`.
    print(f"changed region: {left},{top},{right - left},{bottom - top}")
    print(f"side by side ({before_path.name} left, {after_path.name} right): {side_path}")
    print(f"mask: {mask_path}")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"named regions: {', '.join(sorted(REGIONS))}",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    zoom_parser = sub.add_parser("zoom", help="crop a region and magnify it")
    zoom_parser.add_argument("shot", help="shot name (e.g. 00-chart-table) or path")
    zoom_parser.add_argument("region", help="a named region, or x,y,w,h in pixels")
    zoom_parser.add_argument("--factor", type=int, default=3, help="integer magnification (default 3)")
    zoom_parser.add_argument("--out", help="output path (default docs/ui/shots/zoom/)")
    zoom_parser.set_defaults(func=zoom)

    diff_parser = sub.add_parser("diff", help="side-by-side plus a mask of what changed")
    diff_parser.add_argument("before", help="shot name or path")
    diff_parser.add_argument("after", help="shot name or path")
    diff_parser.add_argument("--out-dir", help="output directory (default docs/ui/shots/diff/)")
    diff_parser.set_defaults(func=diff)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
