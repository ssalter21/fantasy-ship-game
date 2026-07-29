"""Render a round's mockups and assemble them side by side for a human to pick from.

    python scripts/mock-contact-sheet.py shop            # the latest round
    python scripts/mock-contact-sheet.py shop r1         # a named one

Renders every mockup in `docs/ui/mock/<screen>/r<N>/` headlessly at 1244x700 and writes that
round's `index.html`, holding them at full resolution, **grouped by direction**, with each
option's port-cost fields under its frame.

The grouping is the point. `direct-a-screen` runs a tree — N directions you briefed, n
examples inside each — and those two levels are judged differently. Across directions you are
choosing what the screen *is*; inside one you are choosing which arrangement of that idea
reads best. A flat row of nine cannot be read either way, so the sheet keeps the tree.

Under each frame sit the fields the mockup declared: what level it played by, what its brief
forced, what `ui.odin` lacks, what it invented, what it broke. That is the option's **port
cost**, and it is half the decision — the prettiest of nine is not the pick if it is the one
that costs a month of engine work.

Rendering needs a Chromium — Edge or Chrome, whichever is installed. Without one the page is
still assembled, because the page is the thing a human judges by; only the PNGs are skipped.
"""

import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MOCK = REPO / "docs" / "ui" / "mock"

STAGE_W, STAGE_H = 1244, 700

CHROMIUM = (
    Path(r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"),
    Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
    Path("/usr/bin/chromium"),
    Path("/usr/bin/google-chrome"),
)

# A direction and its example are one filename, and this is the seam. Two hyphens rather than
# one because both halves are themselves hyphenated names — `torn-chart--ship-behind` splits,
# `torn-chart-ship-behind` is a guess.
SEAM = "--"

ROUND = re.compile(r"^r(\d+)$")

# The note block's contract — which fields exist, and how they are written — belongs to the
# checker, which is what makes it binding. Loading it rather than restating it here keeps one
# source: a field added there shows up on this page without a second edit.
_spec = importlib.util.spec_from_file_location("check_mock", Path(__file__).parent / "check-mock.py")
check_mock = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(check_mock)


def browser():
    for candidate in CHROMIUM:
        if candidate.is_file():
            return candidate
    return None


def render(exe, page, out):
    """One mockup's stage as a PNG. The window is the stage plus the margin harness.css
    leaves, so the shot contains the whole 1244x700 and nothing of the caption."""
    import subprocess

    subprocess.run(
        [
            str(exe),
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            f"--window-size={STAGE_W + 6},{STAGE_H + 48}",
            f"--screenshot={out}",
            page.resolve().as_uri(),
        ],
        capture_output=True,
        check=False,
    )
    return out.is_file()


def split(stem):
    """A filename's direction and example. A mockup with no seam is its own direction —
    which is what the pre-`direct-a-screen` sets are, one option per brief."""
    if SEAM in stem:
        direction, _, example = stem.partition(SEAM)
        return direction, example
    return stem, ""


def group(pages):
    """The round's options, as directions in file order, each holding its examples."""
    directions = {}
    for page in pages:
        direction, example = split(page.stem)
        directions.setdefault(direction, []).append((example, page))
    return directions


INDEX = """\
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>%(screen)s %(round)s — %(count)d options</title>
    <style>
      body {
        margin: 0;
        padding: 24px;
        background: #181818;
        color: #c8c8c8;
        font: 14px/1.5 system-ui, sans-serif;
      }
      h1 { color: #fff; font-size: 20px; margin: 0 0 4px; }
      h2 { color: #fff; font-size: 17px; margin: 32px 0 2px; }
      p.lede { margin: 0 0 24px; max-width: 900px; }
      p.brief { margin: 0 0 12px; max-width: 900px; color: #9a9a9a; }
      .row { display: flex; gap: 24px; overflow-x: auto; padding-bottom: 8px; }
      .option { flex: 0 0 auto; width: %(w)dpx; }
      .option h3 { color: #fff; font-size: 15px; margin: 0 0 8px; font-weight: 600; }
      .option iframe { width: %(w)dpx; height: %(h)dpx; border: 1px solid #333; display: block; }
      code { color: #ffd479; }
      .cost {
        display: grid;
        grid-template-columns: max-content 1fr;
        gap: 2px 16px;
        margin: 8px 0 0;
        padding: 12px 16px;
        background: #111;
        border-left: 3px solid #444;
      }
      .cost dt {
        color: #8c8c8c;
        text-transform: uppercase;
        letter-spacing: 0.06em;
        font-size: 12px;
        padding-top: 2px;
      }
      .cost dd { margin: 0; color: #e0e0e0; }
      .cost dd.level { color: #fff; font-weight: 600; }
      .cost dd.level-off-style { color: #ffd479; }
      .cost dd.level-free { color: #ff8f6b; }
    </style>
  </head>
  <body>
    <h1>%(screen)s %(round)s — %(count)d options in %(directions)d direction(s)</h1>
    <p class="lede">
      Generated by the <code>direct-a-screen</code> skill: one sub-agent per option, in
      parallel, none of them able to see another's brief or output. Scroll each row sideways.
      <strong>Across</strong> the rows you are choosing what the screen is; <strong>inside</strong>
      a row you are choosing which arrangement of that idea reads best.
    </p>
    <p class="lede">
      Under each frame is that option's <strong>port cost</strong>, as it declared it. A
      <code>free</code> option does not port as drawn — it goes back through a round at
      <code>house</code> or <code>off-style</code> first, which is where its look gets priced.
    </p>
    <p class="lede">
      <strong>Rejected directions are kept, not deleted.</strong> The cost of keeping one forever
      is a file, and a direction that was not chosen is still a data point about what this game
      looks like. Record the pick and the reasons in the screen's <code>README.md</code> rather
      than removing anything.
    </p>
    <p class="lede"><strong>Chosen:</strong> <em>not yet decided</em></p>
%(directions_html)s
  </body>
</html>
"""

DIRECTION = """\
    <h2>%(direction)s</h2>
    <div class="row">
%(options)s
    </div>
"""

OPTION = """\
      <div class="option">
        <h3>%(title)s</h3>
        <iframe src="%(file)s" title="%(title)s"></iframe>
%(cost)s
      </div>
"""


def cost_html(fields):
    """The mockup's own port-cost fields, repeated on the sheet so nine options can be read
    without opening nine files. Empty fields are absent rather than blank."""
    if not fields:
        return '        <dl class="cost"><dt>cost</dt><dd>no port-cost block</dd></dl>'
    rows = []
    for name in check_mock.KNOWN_FIELDS:
        value = fields.get(name)
        if not value:
            continue
        cls = f' class="level level-{value}"' if name == "level" else ""
        rows.append(f"          <dt>{name}</dt><dd{cls}>{value}</dd>")
    return '        <dl class="cost">\n' + "\n".join(rows) + "\n        </dl>"


def rounds(folder):
    """The round folders under a screen, newest last. A screen with none is a pre-round set
    — the shop and home options predate the tree — and the screen folder is its own round."""
    found = sorted(
        (int(ROUND.match(p.name).group(1)), p)
        for p in folder.iterdir()
        if p.is_dir() and ROUND.match(p.name)
    )
    return [p for _, p in found]


def main():
    if not 2 <= len(sys.argv) <= 3:
        sys.exit("usage: python scripts/mock-contact-sheet.py <screen> [round]")
    screen = sys.argv[1]
    folder = MOCK / screen
    if not folder.is_dir():
        sys.exit(f"no mockups at {folder}")

    available = rounds(folder)
    if len(sys.argv) == 3:
        wanted = folder / sys.argv[2]
        if wanted not in available:
            sys.exit(f"no round at {wanted}")
        round_dir = wanted
    else:
        round_dir = available[-1] if available else folder

    pages = sorted(p for p in round_dir.glob("*.html") if p.name != "index.html")
    if not pages:
        sys.exit(f"no mockups in {round_dir}")

    shoot(round_dir, pages)
    directions = group(pages)

    directions_html = "".join(
        DIRECTION
        % {
            "direction": direction.replace("-", " "),
            "options": "".join(
                OPTION
                % {
                    "title": (example or direction).replace("-", " "),
                    "file": page.name,
                    "cost": cost_html(check_mock.read_note(page.read_text(encoding="utf-8"))[0]),
                }
                for example, page in examples
            ),
        }
        for direction, examples in directions.items()
    )

    index = round_dir / "index.html"
    index.write_text(
        INDEX
        % {
            "screen": screen,
            "round": round_dir.name if round_dir != folder else "",
            "count": len(pages),
            "directions": len(directions),
            "w": STAGE_W,
            "h": STAGE_H,
            "directions_html": directions_html,
        },
        newline="\n",
    )
    print(f"wrote {index.relative_to(REPO)} — {len(pages)} options in {len(directions)} direction(s)")


def shoot(round_dir, pages):
    """A PNG per option, beside the round. Not a measurement of anything — the sheet is what
    a human judges by, and these are for the record and for anything that wants a still."""
    exe = browser()
    if exe is None:
        print("no Chromium found; skipping the renders")
        return

    out_dir = round_dir / "render"
    out_dir.mkdir(exist_ok=True)
    for page in pages:
        if not render(exe, page, out_dir / f"{page.stem}.png"):
            print(f"  could not render {page.name}")


if __name__ == "__main__":
    main()
