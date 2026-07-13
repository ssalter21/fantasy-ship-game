# Issue tracker: GitHub Issues

Issues and PRDs for this repo live as GitHub Issues in `ssalter21/fantasy-ship-game`, managed via the `gh` CLI.

## Conventions

- One label per feature/effort: `effort:<slug>` (e.g. `effort:vertical-slice`), applied to every issue belonging to that feature.
- The PRD/tracking issue for an effort carries the `map` label in addition to its `effort:<slug>` label.
- Ticket type is recorded as a `type:<kind>` label (`type:grilling` / `type:research` / `type:prototype` / `type:task`).
- Triage state uses the label vocabulary in `triage-labels.md` (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`).
- Native issue state is the source of truth for open/closed — there is no separate `Status:` line. "Resolved" means the issue is closed with an `## Answer` comment; "claimed" means it's open and assigned.
- Comments and conversation history are ordinary GitHub issue comments.

## When a skill says "publish to the issue tracker"

Create a new issue: `gh issue create --title "<title>" --label "effort:<slug>,type:<kind>,needs-triage" --body "<body>"`. To attach it to a tracking/map issue, wire it as a **native sub-issue** — pass `--parent <map-number>` at creation (or `gh issue edit <map-number> --add-sub-issue <n>` after) rather than only mentioning the parent in the body. See "Wayfinding operations" for the full child-ticket recipe.

## When a skill says "fetch the relevant ticket"

`gh issue view <number>`. The user will normally pass the issue number or URL directly.

## Session-start overview

Use `scripts/issue-status.sh` instead of ad hoc `gh issue view --json ...comments...` calls for a session-start check — pulling comments and re-serializing with `ConvertTo-Json -Depth N` burns a lot of tokens for a status glance.

- `scripts/issue-status.sh` — compact one-line-per-open-issue overview (number, state, labels, title only)
- `scripts/issue-status.sh list --unassigned --label effort:<slug>` — frontier candidates for one effort
- `scripts/issue-status.sh map` — open `map`-labeled issue(s): title, url, body (no comments)
- `scripts/issue-status.sh view <number>` — full detail for one issue, body included but comments excluded by default; add `--comments` only when the conversation history is actually needed

## Wayfinding operations

Used by `/wayfinder`. The **map** is a tracking issue, and each ticket is a **native GitHub sub-issue** of it. (Labels stay repo-local: `map` / `effort:<slug>` / `type:<kind>`, not the skill's `wayfinder:*` vocabulary.)

- **Map**: a GitHub issue labeled `map` + `effort:<slug>`, body holding the Destination / Notes / Decisions-so-far / Not-yet-specified / Out-of-scope sections (see the map body template below). The map is an **index** — resolved decisions are appended as one-line gists to the body's `## Decisions so far` section, each linking its child ticket where the detail lives. Do **not** log decisions as comments; the body is the canonical decision index.
- **Child ticket**: a GitHub issue labeled `type:<kind>` (`research`/`prototype`/`grilling`/`task`) + `effort:<slug>`, wired to the map as a **native sub-issue** so the tracker UI renders the hierarchy and progress rollup. Create it already parented: `gh issue create --parent <map-number> --label "effort:<slug>,type:<kind>,ready-for-agent" --title "..." --body "..."`. Retro-wire an existing child with `gh issue edit <map-number> --add-sub-issue <child-number>`. A human-readable `Part of the <effort> effort: #<map-number>` line in the body is optional prose, not the link — the sub-issue relationship is.
- **Blocking**: prefer GitHub's **native issue dependencies** (the canonical, UI-visible representation). Add an edge with `gh api --method POST repos/ssalter21/fantasy-ship-game/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/ssalter21/fantasy-ship-game/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports open blockers in `issue_dependencies_summary.blocked_by`. Where dependencies aren't available, fall back to a `Blocked by: #N, #N` line near the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier**: the map's open sub-issues with no assignee and no open blocker; first by number wins. `gh issue list --label effort:<slug> --state open` lists candidates — drop any with an assignee or an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line).
- **Claim**: `gh issue edit <number> --add-assignee @me` before starting work — the session's first write.
- **Resolve**: `gh issue comment <number> --body "## Answer\n\n..."`, then `gh issue close <number> --reason completed`, then **append a one-line gist + link to the map body's `## Decisions so far` section** (edit the body, not a comment).

### Map body template

```markdown
## Destination

<what reaching the end of this map looks like — the spec, decision, or change this effort is finding its way to. One or two lines.>

## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the index — one line per closed ticket, linking the child where the detail lives -->

- [<closed ticket title>](link) — <one-line gist of the answer>

## Not yet specified

<!-- in-scope fog you can't ticket yet; graduates as the frontier advances -->

## Out of scope

<!-- work ruled beyond the destination; closed, never graduates -->
```

Open tickets are **not** listed in the body — they are the map's open sub-issues, found by query. The tracker UI renders the sub-issue hierarchy, so no manual `## Children` list is needed.
