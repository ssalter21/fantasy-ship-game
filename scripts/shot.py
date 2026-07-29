"""Zoom into a capture shot, diff two of them, and see which screens a change moved.

    python scripts/shot.py zoom 00-chart-table top-left --factor 3
    python scripts/shot.py diff 05-build 06-build-hover
    python scripts/shot.py diff prev:05-build 05-build
    python scripts/shot.py check
    python scripts/shot.py accept

A bare shot name is this branch's, because captures are scoped by branch and each shot's
previous version is kept beside it -- `prev:<name>` is the frame the last capture replaced,
and `<scope>:<name>` another branch's. Nothing needs copying out of the shots directory to
survive a capture run.

When to reach for which, and what the check does and does not cover, are in
`.claude/skills/run-game/SKILL.md` -- kept there rather than restated here, so the two
cannot drift apart.
"""

import argparse
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageChops

REPO = Path(__file__).resolve().parent.parent
SHOTS = REPO / "docs" / "ui" / "shots"
MANIFEST = REPO / "docs" / "ui" / "shot-manifest.txt"
GAME = REPO / ("game.exe" if os.name == "nt" else "game")

# Inside a scope: the version each shot had before the current run replaced it. The game
# writes it (presentation/capture_scope.odin); this is the name to look under.
PREV = "prev"

# Directories under SHOTS that hold derived output rather than a capture scope, so the
# search for a shot in another scope does not descend into them.
DERIVED = {"zoom", "diff"}

HEAD_REF_PREFIX = "ref: refs/heads/"
OBJECT_NAME_MIN = 40
OBJECT_NAME_SHORT = 7
SCOPE_UNSCOPED = "no-git"
SCOPE_KEEP = re.compile(r"[^A-Za-z0-9._-]")

# `capture: wrote docs/ui/shots/main/05-build.png` -- one line per shot capture landed, in
# every capture mode. The check reads the set it compares off these rather than off the
# directory, so a stale PNG left there by an older walk is not mistaken for this run's.
WROTE = re.compile(r"^capture: wrote (\S+\.png)$")

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


def git_head():
    """The text of this working tree's HEAD, or None when there is none to read.

    `.git` is a directory in an ordinary checkout and a file naming the real git
    directory in a linked worktree; both are followed, so a capture taken in a worktree
    scopes by that worktree's branch.
    """
    git_dir = REPO / ".git"
    if git_dir.is_file():
        pointer = git_dir.read_text().strip()
        if not pointer.startswith("gitdir: "):
            return None
        git_dir = Path(pointer[len("gitdir: "):].strip())
    head = git_dir / "HEAD"
    return head.read_text() if head.is_file() else None


def scope_from_head(head):
    """The directory name a HEAD scopes its captures under.

    The same rule as `capture_scope_from_head` in presentation/capture_scope.odin, over
    the same file: a symbolic ref scopes by its branch with every byte a path segment
    cannot carry replaced, a bare object name by its short form, and anything else is
    unreadable and scopes by SCOPE_UNSCOPED. The game writes where this says to look, so
    the two implementations agreeing is the whole contract.
    """
    if head is None:
        return SCOPE_UNSCOPED
    trimmed = head.strip()
    if trimmed.startswith(HEAD_REF_PREFIX):
        branch = trimmed[len(HEAD_REF_PREFIX):]
        if branch:
            return SCOPE_KEEP.sub("-", branch)
    if len(trimmed) >= OBJECT_NAME_MIN and all(c in "0123456789abcdef" for c in trimmed):
        return f"detached-{trimmed[:OBJECT_NAME_SHORT]}"
    return SCOPE_UNSCOPED


def scope_dir():
    """The directory the current branch's captures land in."""
    return SHOTS / scope_from_head(git_head())


def shot_candidates(name):
    """Where a bare or qualified shot name could be, in the order it is looked for.

    `<where>:<name>` asks for one place: `prev` is the version the last capture replaced,
    and anything else names another scope. A bare name is the current scope's, then that
    scope's `prev`, then the other scopes — so a name that exists in more than one place
    resolves to this branch's, and a name that exists in only one still resolves.
    """
    where, marked, rest = name.partition(":")
    if marked:
        root = scope_dir() / PREV if where == PREV else SHOTS / where
        return [root / f"{rest}.png", root / rest]

    current = scope_dir()
    roots = [current, current / PREV]
    roots += sorted(
        d for d in SHOTS.glob("*")
        if d.is_dir() and d.name not in DERIVED and d != current
    )
    return [root / part for root in roots for part in (f"{name}.png", name)]


def resolve_shot(name):
    """Accept a path, or a shot name resolved against the capture scopes.

    Naming a directory means you meant that file; naming neither directory nor
    extension means the shots directory, and *only* it. A capture killed mid-walk
    strands `NN-*.png` in the repo root (see the run-game skill), and a stray one
    there must not quietly shadow the real shot of the same name.
    """
    if "/" in name or "\\" in name:
        candidates = [Path(name)]
    else:
        candidates = shot_candidates(name)
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    sys.exit(f"no such shot: {name} (tried {', '.join(str(c) for c in candidates)})")


def shot_label(path):
    """A shot's name in derived output and in a report.

    Qualified by the directory it came from unless that is the current scope, so
    `prev:05-build` and `05-build` — the before and after of one capture run, and the
    comparison this tool is mostly reached for — do not both answer to `05-build`.
    """
    if path.parent == scope_dir():
        return path.stem
    return f"{path.parent.name}-{path.stem}"


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
        SHOTS / "zoom" / f"{shot_label(path)}-{region_slug}-{args.factor}x.png"
    )
    write(out, destination)
    print(
        f"{shot_label(path)} {box[0]},{box[1]} {crop.width}x{crop.height} "
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
    before_label, after_label = shot_label(before_path), shot_label(after_path)
    before, after = load(before_path), load(after_path)
    if before.size != after.size:
        sys.exit(
            f"cannot diff different sizes: {before_label} is "
            f"{before.width}x{before.height}, {after_label} is "
            f"{after.width}x{after.height}"
        )

    delta, changed = changed_mask(before, after)
    pixels = sum(delta.histogram()[1:])
    if pixels == 0:
        # ASCII only: this console is cp1252 and mangles anything else.
        print(f"{before_label} and {after_label} are identical - nothing written")
        return

    stem = f"{before_label}-vs-{after_label}"
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
    print(f"side by side ({before_label} left, {after_label} right): {side_path}")
    print(f"mask: {mask_path}")


MANIFEST_HEADER = """\
# What each named screen looks like, as a hash -- so a change to shared chrome names the
# screens it moved instead of moving them silently.
#
# `python scripts/shot.py check` re-renders the shots and reports which of these moved;
# `python scripts/shot.py accept` records the new ones, and is the deliberate step that
# says an intended change is intended.
#
# One line per entry of capture_shots in presentation/capture.odin, plus `hull-sheet` for the
# hull contact sheet, keyed by the screen's name and sorted by it: inserting a shot adds a line
# rather than renumbering the file, and the walk-order number a PNG carries appears nowhere
# here. The hash is SHA-256 over the shot's decoded RGB pixels, not over the PNG, so it moves
# when the screen does and not when the encoder, the file's timestamp or its place in the walk
# does.
#
# `hull-sheet` is the 3D ship screen from six eyes in three paints, in one PNG, so a change to
# the loft or to the hull painter names itself here rather than moving that screen silently. A
# hash says a hull moved, never whether it moved for the better -- look at the sheet before
# accepting it.
#
# These are the pixels one machine's GPU and driver produced. Regenerate on the machine
# that reads them; a mismatch across two machines is not a design change.

"""


def shot_name(path):
    """The screen behind a shot's filename: `05-build.png` -> `build`.

    The number is the shot's place in the walk, so it shifts when a shot is inserted
    ahead of it and says nothing about the screen. The manifest is keyed by the name
    alone, which is also the only half of it a report has any business saying.
    """
    return re.sub(r"^\d+-", "", Path(path).stem)


def pixel_hash(path):
    """SHA-256 over a shot's decoded RGB pixels."""
    return hashlib.sha256(load(path).tobytes()).hexdigest()


def run_capture_mode(mode):
    """Run one capture mode and return the shots it wrote. name -> path."""
    render = subprocess.run([str(GAME), mode], cwd=REPO, capture_output=True, text=True)
    written = {}
    for line in render.stdout.splitlines():
        match = WROTE.match(line.strip())
        if match:
            written[shot_name(match.group(1))] = REPO / match.group(1)
    # Non-zero means at least one shot did not land, and a shot missing from the
    # comparison would read as an unchanged screen. Fail rather than compare a subset.
    if render.returncode != 0 or not written:
        sys.exit(
            f"capture {mode} failed ({render.returncode}), "
            f"{len(written)} shot(s) written:\n{render.stderr}"
        )
    return written


def render_shots():
    """Rebuild the game, render every manifest entry, and hash them. name -> hash.

    Two capture modes, because the manifest is not the registry alone: `--shots` writes one
    PNG per standalone screen and `--hull-sheet` writes one for the whole contact sheet, which
    joins as a single entry named for its file. What that buys is in MANIFEST_HEADER, which is
    where a reader of the manifest finds it.

    Builds first so the shots are of the working tree rather than of whatever the last
    build left in `game.exe`. This opens a real window, so it wants a real desktop --
    the same limit every capture mode has.
    """
    build = subprocess.run(
        ["odin", "build", "cmd/game", f"-out:{GAME.name}"],
        cwd=REPO,
        capture_output=True,
        text=True,
    )
    if build.returncode != 0:
        sys.exit(f"odin build cmd/game failed:\n{build.stdout}{build.stderr}")

    written = {}
    for mode in ("--shots", "--hull-sheet"):
        for name, path in run_capture_mode(mode).items():
            # One name, one entry: two modes writing the same name would leave the manifest
            # hashing one of the two files and saying nothing about the other -- a subset
            # compared silently, which is what each mode's own check above refuses to do.
            if name in written:
                sys.exit(f"{mode} wrote {name}, which an earlier capture mode already wrote")
            written[name] = path
    return {name: pixel_hash(path) for name, path in written.items()}


def read_manifest():
    """The recorded hashes as name -> hash, or None when nothing is recorded yet."""
    if not MANIFEST.is_file():
        return None
    recorded = {}
    for line in MANIFEST.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            name, _, digest = line.partition(" ")
            recorded[name] = digest.strip()
    return recorded


def write_manifest(hashes):
    # Sorted by name and newline-terminated with explicit "\n": the file is committed, so
    # its byte order and line endings should depend on the shots and nothing else.
    body = "".join(f"{name}  {hashes[name]}\n" for name in sorted(hashes))
    MANIFEST.write_text(MANIFEST_HEADER + body, newline="\n")


def compare(recorded, current):
    """Which screens moved, which are unrecorded, and which the manifest still expects."""
    moved = sorted(n for n, h in current.items() if n in recorded and recorded[n] != h)
    added = sorted(n for n in current if n not in recorded)
    gone = sorted(n for n in recorded if n not in current)
    return moved, added, gone


def report(heading, names):
    if names:
        print(f"{heading}:")
        for name in names:
            print(f"  {name}")


def check(args):
    recorded = read_manifest()
    if recorded is None:
        sys.exit(f"no manifest at {MANIFEST} - record one with: python scripts/shot.py accept")

    current = render_shots()
    moved, added, gone = compare(recorded, current)
    if not (moved or added or gone):
        print(f"{len(current)} shots, none moved")
        return

    report(f"{len(moved)} of {len(current)} shots moved", moved)
    report("shot, but not in the manifest", added)
    report("in the manifest, but not shot", gone)
    print("\naccept with: python scripts/shot.py accept")
    sys.exit(1)


def accept(args):
    recorded = read_manifest() or {}
    current = render_shots()
    moved, added, gone = compare(recorded, current)
    write_manifest(current)

    if not (moved or added or gone):
        print(f"{MANIFEST.name} already matched all {len(current)} shots")
        return
    report("accepted as intended", moved)
    report("newly recorded", added)
    report("dropped from the manifest", gone)
    print(f"\n{len(current)} shots recorded in {MANIFEST}")


def main():
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"named regions: {', '.join(sorted(REGIONS))}",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    zoom_parser = sub.add_parser("zoom", help="crop a region and magnify it")
    zoom_parser.add_argument("shot", help="shot name (e.g. 00-chart-table, prev:00-chart-table) or path")
    zoom_parser.add_argument("region", help="a named region, or x,y,w,h in pixels")
    zoom_parser.add_argument("--factor", type=int, default=3, help="integer magnification (default 3)")
    zoom_parser.add_argument("--out", help="output path (default docs/ui/shots/zoom/)")
    zoom_parser.set_defaults(func=zoom)

    diff_parser = sub.add_parser("diff", help="side-by-side plus a mask of what changed")
    diff_parser.add_argument("before", help="shot name, prev:<name>, <scope>:<name>, or a path")
    diff_parser.add_argument("after", help="shot name, prev:<name>, <scope>:<name>, or a path")
    diff_parser.add_argument("--out-dir", help="output directory (default docs/ui/shots/diff/)")
    diff_parser.set_defaults(func=diff)

    check_parser = sub.add_parser(
        "check", help="re-render the named shots and report which moved (exit 1 if any did)"
    )
    check_parser.set_defaults(func=check)

    accept_parser = sub.add_parser(
        "accept", help="re-render the named shots and record them as the manifest"
    )
    accept_parser.set_defaults(func=accept)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
