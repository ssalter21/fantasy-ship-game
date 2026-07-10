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

Create a new issue: `gh issue create --title "<title>" --label "effort:<slug>,type:<kind>,needs-triage" --body "<body>"`. Reference the parent/tracking issue in the body (e.g. `Part of the vertical slice PRD: #2`).

## When a skill says "fetch the relevant ticket"

`gh issue view <number>`. The user will normally pass the issue number or URL directly.

## Session-start overview

Use `scripts/issue-status.sh` instead of ad hoc `gh issue view --json ...comments...` calls for a session-start check — pulling comments and re-serializing with `ConvertTo-Json -Depth N` burns a lot of tokens for a status glance.

- `scripts/issue-status.sh` — compact one-line-per-open-issue overview (number, state, labels, title only)
- `scripts/issue-status.sh list --unassigned --label effort:<slug>` — frontier candidates for one effort
- `scripts/issue-status.sh map` — open `map`-labeled issue(s): title, url, body (no comments)
- `scripts/issue-status.sh view <number>` — full detail for one issue, body included but comments excluded by default; add `--comments` only when the conversation history is actually needed

## Wayfinding operations

Used by `/wayfinder`. The **map** is a tracking issue with one **child** issue per ticket.

- **Map**: a GitHub issue labeled `map` + `effort:<slug>`, body holding the Destination / Notes / Decisions-so-far / Not-yet-specified / Out-of-scope sections. New decisions are appended as comments on this issue rather than edited into the body.
- **Child ticket**: a GitHub issue labeled `type:<kind>` (`research`/`prototype`/`grilling`/`task`) + `effort:<slug>`, with the question in the body and `Part of the vertical slice PRD: #<map-issue>` linking back to the map.
- **Blocking**: a `Blocked by: #N, #N` line near the top of the body. A ticket is unblocked when every issue it lists is closed.
- **Frontier**: `gh issue list --label effort:<slug> --state open` for issues with no assignee, first by number wins, then check its `Blocked by` issues are all closed.
- **Claim**: `gh issue edit <number> --add-assignee @me` before starting work.
- **Resolve**: `gh issue comment <number> --body "## Answer\n\n..."`, then `gh issue close <number> --reason completed`, then `gh issue comment <map-issue>` with a one-paragraph decision gist + a link back to the child issue.
