---
name: direct-a-screen
description: Direct a screen — the human briefs N design directions, each spawns n parallel browser mockups, and they come back as a contact sheet to pick from. Every direction sets its own constraint level, from house style to no constraints at all. Use when designing or redesigning a game screen, exploring layouts or art directions, iterating on a picked direction, or when a screen "needs a look".
---

# Direct a screen

The **direction** is the unit of this skill, and it comes from the human. Not from a table, not
from this file, and not from you.

That sentence is the whole correction. Its predecessor, `design-a-screen`, chose the directions
itself off a fixed four-axis table and generated four options per screen. Against the Shop it
looked like it worked. Against a screen that is not a list it produced five options of which four
made the same move — delete the world, draw a table of text on parchment — and no pair got below
25% pixel-identical. **A table cannot know what you want the screen to be.** So the human briefs
the directions, and the machinery's job is to make briefing them cheap and running them fast.

## The shape of a run

```
round               one invocation of this skill
  direction         a name, your prompt or style, an optional reference, a constraint level
    example         one sub-agent, one HTML mockup, one structural commitment broken
```

Across directions you are choosing **what the screen is**. Inside a direction you are choosing
**which arrangement of that idea reads best**. Divergence is what the first level is for and
convergence is what the second is for, and briefing them the same way is how the last skill died.

## Prerequisites

- [`docs/ui/mock/README.md`](../../../docs/ui/mock/README.md) — the harness, the three levels, the
  note block's fields, and the porting table. Every mockup is written against `harness.css`.
- The screen as it ships: its capture in `docs/ui/shots/<branch>/` and its draw proc in
  `presentation/`.

## 1. Interview — and the level is never assumed

Ask, one thing at a time. Nothing spawns until this is answered and nothing here is defaulted
silently, because a run configured by guesswork produces nine pictures answering a question
nobody asked.

**a. The global reference.** Optional, and usually the screen's current shot. Every agent sees
it, at every level. Also accepts the winners of a previous round — that is what makes iteration
work (step 5).

**b. The directions.** For each one:

| | |
| --- | --- |
| **name** | a slug — it names the file and the row on the sheet |
| **brief** | the human's own words. A style, a mood, a rule, a single sentence. |
| **reference** | optional, this direction's alone. No other direction's agents see it. |
| **level** | `house`, `off-style`, or `free`. Asked every time. |

**The three levels, and what each is evidence of:**

| Level | Style roster & type scale | What raylib can draw | The picture is |
| --- | --- | --- | --- |
| `house` | binding | binding | a screen you could ship this week |
| `off-style` | thrown out — any palette, any type size, coral unreserved | binding | a different look this engine can still draw |
| `free` | thrown out | thrown out — blur, round a corner, rotate | concept art, priced in engine work |

`off-style` is the one to reach for when the ask is "show me something that doesn't look like
this game". It is nearly always what "no constraints" actually means, and unlike `free` it ports.

**c. N and n.** Default 3 × 3 — nine agents in parallel. Below three examples the structural
axes in step 2 run out; above three directions the sheet gets too wide to judge.

**d. The content list.** **You derive it, the human amends it.** Read the screen's draw proc and
its shot, write down every piece of content and every control it carries, and show that list. It
is fact-work, so do it rather than asking. For a screen that does not exist yet there is nothing
to read, so the human states it.

## 2. Draft the sub-briefs, and show them before spawning

Inside a direction, all n agents have the same brief — which is the 82%-identical failure waiting
to happen. So each example additionally breaks **one different structural commitment**:

| Axis | The question |
| --- | --- |
| **Ground** | What is the screen mostly made of? |
| **Containment** | What holds the content? |
| **Figure / ground** | Which is the subject — the world, or the content? |
| **Order** | How is the content ordered? |

This is the old skill's table, and it is a good list of *what structurally varies in a screen*
while being a bad way to choose what a screen should be. It is demoted accordingly: it never
picks a direction, it only spreads the examples inside one the human picked. Holding a direction
constant and varying one axis is the converging move, which is the right move at this level.

Write the n sub-briefs per direction, each one line, and **show all N×n to the human before a
single agent spawns.** They veto or overwrite any line. This gate costs one glance and no tokens,
and it is the last point at which a wrong direction is free.

## 3. Spawn them in parallel

One message, N×n `Agent` calls, `run_in_background: false`. No agent is told the others exist.

```
Design one mockup of the <screen> screen for this game.

Read first: docs/ui/mock/README.md — the harness, the three levels, and the note block you
must close with. Also docs/ui/mock/shop.html (a worked example) and, if your level is
`house`, docs/ui/style-guide.md.

<the global reference, if any: "This is the screen as it ships today: <path>.">
<at `free`, add: "Your direction is not required to relate to it.">

What the screen has to carry, which is fixed: <the content list from step 1d>
If you think an item does not belong on this screen, draw it anyway and argue in your note.
An option missing a control is not a design, it is a different question — and it wins the
comparison unfairly by being emptier.

YOUR DIRECTION — <name>: <the human's brief>
<the direction's reference image, if any>

YOUR CONSTRAINT LEVEL — <level>: <what that level allows, from README.md>

WITHIN THAT DIRECTION, YOUR EXAMPLE BREAKS: <the one structural axis, from step 2>

Write exactly one file: docs/ui/mock/<screen>/r<N>/<direction>--<example>.html, linking
../../harness.css. The stage is 1244x700 at every level — it is the window, not a style.
It must pass `python scripts/check-mock.py <that file>`.

Close it with the port-cost note block, as README.md specifies. Fill every field that has
something to say and leave out the ones that do not.

Do not edit any other file. Do not read or write any other mockup.
```

Two lines carry most of the weight. **The content list is fixed** — constraints govern form, and
an agent that quietly drops a control has answered a different question. **The note block is the
port cost** — it is how this skill feeds the widget layer, and the components worth building are
the ones several independent designs actually reached for.

## 4. Assemble the sheet

```bash
python scripts/check-mock.py docs/ui/mock/<screen>/r<N>/*.html
python scripts/mock-contact-sheet.py <screen>
```

The checker applies each mockup's declared level and prints what the others cost. The sheet
renders every option, groups the rows by direction, and repeats each option's port cost under its
frame. Open `docs/ui/mock/<screen>/r<N>/index.html`.

**A human picks.** Say so and stop. The useful answer is often "the ground from A with the order
in C", and that is not a pick you can make for them.

## 5. Record it, then round again or port

Write the round into `docs/ui/mock/<screen>/README.md`: the directions and their briefs, the
levels, what was picked, and why the others were not. **Rejected directions are kept, not
deleted** — the cost of keeping one forever is a file, and a direction nobody chose is still a
data point about what this game looks like.

Then one of two things happens:

- **Another round.** This skill again, with the winner (or two winners plus a sentence) as the
  global reference in step 1a. Round 2's directions can narrow to deltas or pivot wide — that is
  the human's call, and it needs no separate mode, because a round is just a run whose reference
  is a mockup instead of a shot.
- **`/port-a-mockup`**, which takes it into the presentation package.

**A `free` winner does not go to `/port-a-mockup`.** It goes through one more round at `house` or
`off-style` first. Its note block says what it broke; that round is where the look gets priced
against what raylib can actually draw, and skipping it produces a design nobody can build.

## What this skill does not do

- **It does not choose the directions.** That is the correction it exists to be. If nobody has
  briefed a direction, interview — do not fill the gap from the axis table.
- **It does not pick.** The output is options, their costs, and a sheet.
- **It does not implement.** Porting is `/port-a-mockup`, against the table in
  `docs/ui/mock/README.md`.
- **It does not tune.** Once a design is ported, refining its numbers is `--workbench <screen>`
  and a human eye — see the `run-game` skill.
