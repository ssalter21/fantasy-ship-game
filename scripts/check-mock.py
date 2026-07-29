"""Check a browser mockup against the constraints CSS cannot enforce.

    python scripts/check-mock.py                      # every mockup under docs/ui/mock/
    python scripts/check-mock.py docs/ui/mock/shop.html

The harness (docs/ui/mock/harness.css) refuses everything it can with `!important`. What is
left over is this: rules about *values* rather than about properties, which no stylesheet can
express. A mockup that passes both is a mockup that ports.

What is checked, and why each one is a real trap:

  colours     Every colour is a roster swatch, or a uniform shade of one (which is what
              `colour_shade` does in Odin). A hand-typed hex is how a mockup drifts off the
              palette the game is locked to — and it drifts by an amount too small to see and
              large enough to read as a foreign object next to art that is exactly on it.
  gradients   One axis only, because DrawRectangleGradientV/H are the only gradient calls
              there are. A radial or an angled gradient has nothing behind it.
  size        The stage is exactly 1244x700. A layout measured at any other size is a layout
              the game will never show.
  fractions   Whole-pixel positions. A half-pixel edge is resampled by the browser and simply
              cannot be asked for in a draw call.

Exit 1 on any finding, so this is usable as a gate.
"""

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MOCK = REPO / "docs" / "ui" / "mock"
HARNESS = MOCK / "harness.css"

# A screen's options are assembled into an index page (scripts/mock-divergence.py), which is
# a contact sheet of iframes rather than a mockup and has no stage of its own.
NOT_A_MOCKUP = {"index.html"}

# docs/ui/style-guide.md, "The roster", plus the navy ramp the unre-coloured screens still
# draw from. Named so a finding can say which swatch a colour nearly was.
ROSTER = {
    "sea": (0x1F, 0xA9, 0xD0),
    "sea-bright": (0x2C, 0xC3, 0xDE),
    "sea-shallow": (0x63, 0xE2, 0xEC),
    "sea-deep": (0x17, 0x86, 0xBC),
    "foam": (0xF2, 0xFB, 0xFB),
    "sky-high": (0x3F, 0x79, 0xC0),
    "sky": (0x5A, 0x93, 0xD2),
    "haze": (0x8F, 0xBC, 0xE8),
    "cloud": (0xEE, 0xF1, 0xF8),
    "cloud-shadow": (0x92, 0xB7, 0xE0),
    "parchment": (0xEB, 0xD9, 0xA6),
    "sand": (0xD2, 0xA9, 0x68),
    "cliff": (0xB9, 0x8A, 0x50),
    "rock": (0x7E, 0x5C, 0x3A),
    "trunk": (0x87, 0x5F, 0x38),
    "green-highlight": (0x9B, 0xDE, 0x57),
    "green-light": (0x57, 0xC9, 0x4D),
    "green": (0x2F, 0xA2, 0x3E),
    "green-deep": (0x1B, 0x6A, 0x2B),
    "coral": (0xE1, 0x55, 0x2B),
    "ink": (0x12, 0x33, 0x3F),
    "ink-muted": (0x4C, 0x73, 0x85),
    "cream-bright": (0xF3, 0xE6, 0xC4),
    "deep": (0x08, 0x11, 0x27),
    "mid": (0x0A, 0x1C, 0x30),
    "shallow": (0x0E, 0x2E, 0x3F),
    "vignette": (0x05, 0x0B, 0x18),
    "steel": (0x8A, 0xA9, 0xD6),
    "cream": (0xE7, 0xD2, 0xA3),
    "cyan": (0x6F, 0xE0, 0xEC),
}

# The desk the stage sits on and the caption under it are outside the stage and never ship,
# so they are not roster-bound. Everything else is.
OUTSIDE_THE_STAGE = re.compile(r"^\s*(html|body|\.note\b)", re.MULTILINE)

HEX = re.compile(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\b")
GRADIENT = re.compile(r"(\w*-?gradient)\(([^;]*)")
ONE_AXIS = re.compile(r"^\s*to\s+(top|bottom|left|right)\b")
FRACTIONAL_PX = re.compile(r"\b\d+\.\d+px\b")
STAGE_SIZE = re.compile(r"\.stage\s*\{[^}]*?width:\s*(\d+)px[^}]*?height:\s*(\d+)px", re.S)

STAGE_W, STAGE_H = 1244, 700

# A shade is a uniform multiply, so a rounded channel can sit one off. Two would let a colour
# drift far enough to be a different swatch.
SHADE_TOLERANCE = 1


def parse_hex(text):
    if len(text) == 3:
        return tuple(int(c * 2, 16) for c in text)
    return tuple(int(text[i : i + 2], 16) for i in (0, 2, 4))


def resolve(colour):
    """The roster swatch and shade factor a colour is, or None if it is off the roster.

    A shade is `colour_shade(swatch, factor)` — every channel multiplied by one factor and
    clamped — which is how the game gets a lit face and a shadowed one out of a single
    swatch rather than out of two that have to be kept in step by hand.
    """
    for name, swatch in ROSTER.items():
        if swatch == colour:
            return name, 1.0
        # Take the factor off the largest channel: the smallest carries the most rounding
        # error, and a zero channel carries no information at all.
        base = max(range(3), key=lambda i: swatch[i])
        if swatch[base] == 0:
            continue
        factor = colour[base] / swatch[base]
        if not 0 < factor <= 2:
            continue
        if all(abs(round(swatch[i] * factor) - colour[i]) <= SHADE_TOLERANCE for i in range(3)):
            return name, factor
    return None


def stage_only(css):
    """The stylesheet minus the rules that style things outside the stage."""
    kept, skip = [], False
    for block in re.split(r"(?<=\})", css):
        if OUTSIDE_THE_STAGE.search(block):
            skip = True
        if not skip:
            kept.append(block)
        skip = False
    return "".join(kept)


def check(path):
    text = path.read_text(encoding="utf-8")
    findings = []

    for match in HEX.finditer(stage_only(text)):
        colour = parse_hex(match.group(1))
        resolved = resolve(colour)
        if resolved is None:
            findings.append(f"#{match.group(1)} is not a roster swatch or a shade of one")
        elif resolved[1] != 1.0:
            name, factor = resolved
            print(f"  note: #{match.group(1)} is {name} shaded {factor:.3f} — port as colour_shade")

    for match in GRADIENT.finditer(text):
        kind, args = match.group(1), match.group(2)
        if kind != "linear-gradient":
            findings.append(f"{kind}() has no draw call behind it; only one-axis linear-gradient ports")
        elif not ONE_AXIS.match(args):
            findings.append(
                f"linear-gradient({args.strip()[:40]}...) is not one axis; "
                f"DrawRectangleGradientV/H take `to top|bottom|left|right` only"
            )

    for match in FRACTIONAL_PX.finditer(text):
        findings.append(f"{match.group(0)} is not a whole pixel; a draw call cannot ask for one")

    if path.suffix == ".html":
        # One harness, wherever the mockup sits. A screen's options live in
        # docs/ui/mock/<screen>/ and link ../harness.css, so this cannot resolve relative to
        # the mockup — and a per-directory copy of the harness would be a second set of
        # constraints to drift.
        size = STAGE_SIZE.search(HARNESS.read_text(encoding="utf-8"))
        if not size:
            findings.append("harness.css does not fix the stage size")
        elif (int(size.group(1)), int(size.group(2))) != (STAGE_W, STAGE_H):
            findings.append(f"the stage is {size.group(1)}x{size.group(2)}, not {STAGE_W}x{STAGE_H}")
        if 'harness.css"' not in text:
            findings.append("the mockup does not link harness.css, so none of its constraints apply")
        if 'class="stage"' not in text:
            findings.append("the mockup has no .stage, so it is not drawn at the window's size")

    return findings


def label(path):
    """A mockup's name for a report: repo-relative where it can be, whole otherwise — a
    mockup written outside the repo is still worth checking before it is moved in."""
    try:
        return path.resolve().relative_to(REPO)
    except ValueError:
        return path


def main():
    # Recursive: a screen's options live one level down, and a sweep that only saw the top
    # level would pass while every option under it went unchecked.
    targets = [Path(a) for a in sys.argv[1:]] or sorted(
        p for p in MOCK.glob("**/*.html") if p.name not in NOT_A_MOCKUP
    )
    if not targets:
        sys.exit(f"no mockups under {MOCK}")

    failed = 0
    for path in targets:
        print(f"{label(path)}:")
        findings = check(path)
        for finding in findings:
            print(f"  {finding}")
        if findings:
            failed += 1
        else:
            print("  ok")
    if failed:
        sys.exit(f"\n{failed} mockup(s) would not port")


if __name__ == "__main__":
    main()
