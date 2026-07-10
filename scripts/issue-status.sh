#!/usr/bin/env bash
# Compact GitHub issue overview for session start.
#
# Pulls only number/state/labels/title by default -- no body, no comments --
# so a session-start check doesn't dump full comment history and re-serialized
# JSON into agent context. Use `issue-status.sh view <n>` to zoom into a
# specific issue once you know which one you need.
set -euo pipefail

REPO="ssalter21/fantasy-ship-game"
STATE="open"
LABEL=""
UNASSIGNED=""
LIMIT=50

usage() {
  cat <<'USAGE'
Usage: issue-status.sh [command] [options]

Commands:
  list (default)      Compact one-line-per-issue overview
  map                  Print open "map" tracking issue(s): title, url, body
  view <number>        Full issue detail (title, body, labels, state) -- no comments
  view <number> --comments   Full issue detail including comments (expensive; use sparingly)

Options (for `list`):
  --state <open|closed|all>   Filter by state (default: open)
  --label <label>              Filter by label (e.g. effort:vertical-slice)
  --unassigned                 Only unassigned issues (frontier candidates)
  --limit <n>                  Max issues to list (default: 50)
  -h, --help                   Show this help
USAGE
}

cmd="list"
case "${1:-}" in
  list|map|view) cmd="$1"; shift ;;
  -h|--help) usage; exit 0 ;;
esac

if [[ "$cmd" == "map" ]]; then
  gh issue list --repo "$REPO" --state open --label map \
    --json number,title,url \
    --jq '.[] | "#\(.number)  \(.title)  \(.url)"'
  echo "---"
  gh issue list --repo "$REPO" --state open --label map \
    --json number,body \
    --jq '.[] | "== #\(.number) ==\n\(.body)\n"'
  exit 0
fi

if [[ "$cmd" == "view" ]]; then
  number="${1:-}"
  if [[ -z "$number" ]]; then
    echo "issue-status.sh view <number> [--comments]" >&2
    exit 1
  fi
  shift
  fields="number,title,body,labels,state,url"
  if [[ "${1:-}" == "--comments" ]]; then
    fields+=",comments"
  fi
  gh issue view "$number" --repo "$REPO" --json "$fields"
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state) STATE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --unassigned) UNASSIGNED=1; shift ;;
    --limit) LIMIT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

args=(--repo "$REPO" --state "$STATE" --limit "$LIMIT" --json number,title,state,labels,assignees)
[[ -n "$LABEL" ]] && args+=(--label "$LABEL")

filter='.[]'
[[ -n "$UNASSIGNED" ]] && filter+=' | select(.assignees | length == 0)'
filter+=' | "#\(.number) [\(.state)] (\([.labels[].name] | join(","))) - \(.title)"'

gh issue list "${args[@]}" --jq "$filter"
