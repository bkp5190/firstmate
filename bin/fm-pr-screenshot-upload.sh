#!/usr/bin/env bash
# Upload one or more local image files to GitHub's attachment endpoint and
# print a markdown embed line for each, so a crewmate can paste real evidence
# screenshots into a PR body, PR comment, or `done:` status line instead of
# naming a local file path that is meaningless to anyone viewing the PR.
#
# UNOFFICIAL ENDPOINT: uploads.github.com/user-attachments/assets has no
# published GitHub REST API documentation.
# It is the same endpoint the github.com web UI uses for drag-and-drop image
# attachments, and it could change or stop working without notice.
# Verified working 2026-09-04 with a classic `gh` OAuth token against a repo
# the token has PUSH access to; a pull-only token gets a bare 404 with no
# clearer signal, so an upload failure against a repo you expect to have
# write access to is worth double-checking that access first.
#
# Usage:
#   fm-pr-screenshot-upload.sh <owner/repo> <local-file-path> [<local-file-path> ...]
#
# Prints one "![filename](url)" markdown line per file to stdout, in the same
# order as the arguments, as each upload completes.
# On any file's failure, already-printed lines remain valid output; the error
# goes to stderr and the script exits nonzero after attempting every file.
#
# Requires `gh` (authenticated, with push access to <owner/repo>), `curl`, and
# `jq`.
set -u

usage() {
  cat <<'EOF'
Usage: fm-pr-screenshot-upload.sh <owner/repo> <local-file-path> [<local-file-path> ...]

Uploads each local image file to GitHub's attachment endpoint and prints one
"![filename](url)" markdown line per file to stdout - paste the output
straight into a PR body, PR comment, or `done:` status line so evidence
screenshots actually render instead of naming an unreachable local path.

Requires `gh` authenticated with PUSH access to <owner/repo> (pull-only
access returns a bare 404), plus `curl` and `jq`.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ "$#" -lt 2 ]; then
  echo "error: usage: fm-pr-screenshot-upload.sh <owner/repo> <local-file-path> [<local-file-path> ...]" >&2
  exit 2
fi

REPO=$1
shift

for cmd in gh curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: $cmd is required on PATH" >&2; exit 1; }
done

case "$REPO" in
  */*) ;;
  *) echo "error: repo must be in <owner/repo> form, got: $REPO" >&2; exit 2 ;;
esac

image_media_type() {
  local path=$1 lower detected
  lower=$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *.png) printf 'image/png\n'; return 0 ;;
    *.jpg|*.jpeg) printf 'image/jpeg\n'; return 0 ;;
    *.gif) printf 'image/gif\n'; return 0 ;;
    *.webp) printf 'image/webp\n'; return 0 ;;
  esac
  if command -v file >/dev/null 2>&1; then
    detected=$(file --mime-type -b -- "$path" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case "$detected" in
      image/*) printf '%s\n' "$detected"; return 0 ;;
    esac
  fi
  return 1
}

TOKEN=$(gh auth token 2>/dev/null) || { echo "error: gh is not authenticated" >&2; exit 1; }
[ -n "$TOKEN" ] || { echo "error: gh is not authenticated" >&2; exit 1; }

REPO_ID=$(gh api "repos/$REPO" --jq '.id' 2>/dev/null) || {
  echo "error: could not resolve repo id for $REPO (check the repo exists and gh can read it)" >&2
  exit 1
}
[ -n "$REPO_ID" ] || { echo "error: could not resolve repo id for $REPO" >&2; exit 1; }

RC=0
for path in "$@"; do
  if [ ! -f "$path" ]; then
    echo "error: no such file: $path" >&2
    RC=1
    continue
  fi
  media_type=$(image_media_type "$path") || {
    echo "error: could not determine an image content type for $path" >&2
    RC=1
    continue
  }
  name=$(basename -- "$path")
  name_enc=$(jq -rn --arg s "$name" '$s|@uri')
  type_enc=$(jq -rn --arg s "$media_type" '$s|@uri')
  response=$(curl -sS -X POST \
    "https://uploads.github.com/user-attachments/assets?name=$name_enc&content_type=$type_enc&repository_id=$REPO_ID" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json" \
    --data-binary "@$path") || {
    echo "error: upload request failed for $path" >&2
    RC=1
    continue
  }
  url=$(printf '%s' "$response" | jq -r '.url // empty' 2>/dev/null)
  if [ -z "$url" ]; then
    echo "error: upload failed for $path: $response" >&2
    RC=1
    continue
  fi
  name_md=$(printf '%s' "$name" | sed 's/\]/\\]/g')
  printf '![%s](%s)\n' "$name_md" "$url"
done

exit "$RC"
