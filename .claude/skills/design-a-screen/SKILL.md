---
name: design-a-screen
description: Generate N screen designs that genuinely disagree with each other — parallel sub-agents, one browser mockup each on the shared harness, divergently briefed and assembled side by side for a human to pick. Use when designing or redesigning any game screen, exploring layout options, or when a screen "needs a look".
---

# Design a screen

The visual sibling of `design-an-interface`, which has only ever been pointed at module APIs.
Same thesis — your first idea is unlikely to be the best, so generate several and compare — and
the same machinery, parallel sub-agents. What is different is what has to be *briefed*, and it is
the whole of the skill.

## The failure this exists to fix, measured

A four-way design exploration on this repo produced variants that were **82% pixel-identical**.
The brief that produced them was "four framings of that screen", and that brief *guarantees* that
result: holding everything constant but one variable is the right method for **converging** on a
design and the wrong method for **finding** one.

Two things follow, and skipping either gives you the 82% back:

- **Parallel, not sequential.** Sub-agents that cannot see each other cannot anchor on each
  other. Nothing is generated in sequence.
- **Divergently briefed, not differently parameterised.** Each agent gets a different *governing
  constraint*, not a different camera. Divergence has to be briefed for, or you get variance in
  whatever parameter the brief happened to leave loose.

## Prerequisites

- `docs/ui/mock/README.md` — the harness, its rules, and the porting table. Every mockup is
  written against `harness.css`, which is what keeps an option honest enough to ship.
- The screen as it is today: its capture (`docs/ui/shots/<branch>/`, see the `run-game` skill) and
  its draw proc in `presentation/`.

## 1. Name what the screen currently takes for granted

Before choosing constraints, write down the screen's **structural commitments** — the things it
assumes without ever having decided them. Four axes cover nearly every screen this game has:

| Axis | The question | The Shop's current answer |
| --- | --- | --- |
| **Ground** | What is the screen mostly made of? | Sea. The world fills it. |
| **Containment** | What holds the content? | Unbacked parchment cards, no panel. |
| **Figure / ground** | Which is the subject — the world, or the content? | The world is the subject; content sits beside it. |
| **Axis** | How is the content ordered? | A single column down the right edge. |

This table is the input to everything below. If you cannot fill it in, you do not yet know the
screen well enough to brief anyone about it.

## 2. Choose the constraints — one axis each, away from the current answer

**This is the step the invoker does not get to skip and does not get to improvise.** The rule:

> Give each agent a constraint that fixes **one different axis** to a **different value** than the
> screen ships with. Never two agents on the same axis.

Four axes, four agents, no overlap — that is the default N and why. Worked for the Shop:

- **Ground** → "This screen is mostly *parchment*. The world is a margin, not the field."
- **Containment** → "There is **no panel and no card**. Content sits directly on the world."
- **Figure / ground** → "The **ship is the background** and the content is the foreground, over her."
- **Axis** → "The stock does **not** run down a column. Order it some other way entirely."

**The check before you spawn:** for each pair of briefs, ask *would these produce the same
silhouette?* If yes, one of them is not a constraint — it is a parameter. Rewrite it.

**What a constraint is not.** "Try a wider column", "use bigger type", "four framings of that
screen", "make it feel more nautical" — these all leave the structure alone and vary a number or a
mood. You will get the 82% back.

If a screen genuinely has a fifth commitment worth breaking (a modal that assumes it interrupts, a
list that assumes it scrolls), add a fifth agent for it. Do not add agents that share an axis.

## 3. Spawn them in parallel

One message, N `Agent` calls, `run_in_background: false` so you have all N before assembling.
Every agent gets the *same* brief except its constraint line, and none is told the others exist.

```
Design one mockup of the <screen> screen for this game.

Read first: docs/ui/mock/README.md (the harness and its rules), docs/ui/mock/shop.html (a
worked example), docs/ui/style-guide.md (the palette roster and type scale). Look at the
screen as it ships: docs/ui/shots/<branch>/<NN>-<screen>.png.

What the screen has to carry: <the content and controls, listed — this is fixed>

YOUR GOVERNING CONSTRAINT, which is not negotiable and is the point of the exercise:
<one constraint from step 2>

Write exactly one file: docs/ui/mock/<screen>/<slug>.html, linking ../harness.css.
It must pass `python scripts/check-mock.py docs/ui/mock/<screen>/<slug>.html`.

Close it with a .note explaining what your constraint forced you to do differently, and what
you would need from ui.odin that does not exist yet.

Do not edit any other file. Do not read or write any other mockup.
```

Two lines of that brief carry most of the weight:

- **"What the screen has to carry" is fixed.** Constraints govern *form*. An agent that drops a
  control to make its layout work has answered a different question.
- **"what you would need from `ui.odin` that does not exist yet"** is how this skill feeds the
  widget layer. The components worth building are the ones the mockups actually needed — building
  them ahead of the mockups risks building the wrong ones.

## 4. Assemble, check, and measure the divergence

```bash
python scripts/check-mock.py docs/ui/mock/<screen>/*.html   # every option ports
python scripts/mock-divergence.py <screen>                  # writes index.html, reports overlap
```

`mock-divergence.py` renders each option headlessly at 1244×700, writes the side-by-side
`index.html`, and prints the **pairwise identical-pixel percentage**. That number is the skill's
own test: the 82% figure is what failure looked like, so a run whose pairs sit anywhere near it
has not diverged and the briefs are what to fix — not the agents.

Open `docs/ui/mock/<screen>/index.html`. A human picks.

## 5. Keep every rejection

**Rejected directions are kept, not deleted.** In HTML the cost of keeping all N forever is one
file, and a rejected direction is still a data point about what this game looks like — the reason
a thing was not chosen is worth more later than the absence of it. `index.html` records which was
chosen and why the others were not.

## What this skill does not do

- **It does not implement.** The output is mockups and a decision. Porting is a separate act
  against the table in `docs/ui/mock/README.md`.
- **It does not converge.** Once a direction is picked, refining it is the *right* time to hold
  everything constant and vary one thing — and that is `--workbench <screen>`, not this.
