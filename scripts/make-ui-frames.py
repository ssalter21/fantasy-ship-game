"""Author the three chrome frames the UI blits, straight onto the style guide's roster.

    python scripts/make-ui-frames.py

Writes assets/art/ui-frame-{panel,card,button}.png. Deterministic — running it twice
writes the same bytes — so the frames are reviewable as source rather than as a binary
someone has to take on trust, and a change to a border weight is a diff here.

Every pixel is a named roster swatch. That is the one thing this buys over a generated
frame: the guide's conform step exists because generated art lands *near* the palette and
never *on* it, and art placed a pixel at a time lands on it by construction.

The three frames and what distinguishes them:

  panel   the heaviest chrome, for a surface that holds other things — a rock outline over
          a cliff-and-sand bevel, with a gilt tick at each corner.
  card    flatter, for a thing *in* a panel — a sea-deep border on parchment, the read the
          Offer/Shop stock already has.
  button  three states side by side in one strip, in the order Ui_Button_State names them:
          rest raised, hover with its outline lit, press pushed in with the bevel inverted.

Corner art stays inside each frame's slice inset, so 9-slicing stretches only the flat
runs and every corner blits at native size.
"""

from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parent.parent
ART = REPO / "assets" / "art"

# docs/ui/style-guide.md, "The roster". Named here rather than spelled inline so a frame
# reads as the swatches it is made of.
PARCHMENT = (235, 217, 166)
SAND = (210, 169, 104)
CLIFF = (185, 138, 80)
ROCK = (126, 92, 58)
SEA_DEEP = (23, 134, 188)

OPAQUE = 255


def frame(size, rings, corner=None, corner_reach=0):
    """A square frame: concentric `rings` inward from the edge over a parchment field.

    `rings` is one colour per ring, outermost first. `corner`, when given, marks each
    corner with an L reaching `corner_reach` pixels along both edges, inside the rings —
    the mark that makes this art rather than a stroked rectangle.
    """
    img = Image.new("RGBA", (size, size), PARCHMENT + (OPAQUE,))
    px = img.load()

    for depth, colour in enumerate(rings):
        for i in range(depth, size - depth):
            px[i, depth] = colour + (OPAQUE,)
            px[i, size - 1 - depth] = colour + (OPAQUE,)
            px[depth, i] = colour + (OPAQUE,)
            px[size - 1 - depth, i] = colour + (OPAQUE,)

    if corner is not None:
        edge = len(rings)
        for i in range(corner_reach):
            for x, y in ((edge + i, edge), (edge, edge + i)):
                for fx, fy in ((x, y), (size - 1 - x, y), (x, size - 1 - y), (size - 1 - x, size - 1 - y)):
                    px[fx, fy] = corner + (OPAQUE,)
    return img


def bevelled(size, outline, outline_w, top, bottom, field):
    """One button state: an outline `outline_w` thick, a lit row inside the top edge and a
    shadowed row inside the bottom one, over `field`.

    The three states differ by structure rather than by tint, which is what a pixel-art
    control does and what keeps every state on the roster: hover thickens the outline so
    the edge lights, and press swaps the bevel so the face reads pushed in.
    """
    img = Image.new("RGBA", (size, size), field + (OPAQUE,))
    px = img.load()

    for depth in range(outline_w):
        for i in range(depth, size - depth):
            px[i, depth] = outline + (OPAQUE,)
            px[i, size - 1 - depth] = outline + (OPAQUE,)
            px[depth, i] = outline + (OPAQUE,)
            px[size - 1 - depth, i] = outline + (OPAQUE,)

    bevel = outline_w
    for i in range(bevel, size - bevel):
        px[i, bevel] = top + (OPAQUE,)
        px[i, size - 1 - bevel] = bottom + (OPAQUE,)
        px[bevel, i] = top + (OPAQUE,)
        px[size - 1 - bevel, i] = bottom + (OPAQUE,)
    # The two bevel runs meet at the corners; the lit one wins on the top-left and the
    # shadowed one on the bottom-right, so the light has a single direction.
    px[bevel, size - 1 - bevel] = top + (OPAQUE,)
    px[size - 1 - bevel, bevel] = bottom + (OPAQUE,)
    return img


def strip(images):
    """States laid side by side in one texture, so a state is a source-x offset."""
    w, h = images[0].size
    out = Image.new("RGBA", (w * len(images), h), (0, 0, 0, 0))
    for i, image in enumerate(images):
        out.paste(image, (i * w, 0))
    return out


def main():
    ART.mkdir(parents=True, exist_ok=True)

    panel = frame(24, [ROCK, CLIFF, SAND], corner=SAND, corner_reach=4)
    card = frame(16, [SEA_DEEP, SEA_DEEP, SAND], corner=SEA_DEEP, corner_reach=2)
    button = strip(
        [
            bevelled(16, SEA_DEEP, 1, SAND, CLIFF, PARCHMENT),
            bevelled(16, SEA_DEEP, 2, SAND, CLIFF, PARCHMENT),
            bevelled(16, SEA_DEEP, 1, CLIFF, SAND, SAND),
        ]
    )

    for name, image in (("panel", panel), ("card", card), ("button", button)):
        path = ART / f"ui-frame-{name}.png"
        image.save(path)
        print(f"wrote {path.relative_to(REPO)} ({image.width}x{image.height})")


if __name__ == "__main__":
    main()
