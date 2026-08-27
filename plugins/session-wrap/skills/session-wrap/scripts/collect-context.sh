#!/bin/bash
# collect-context.sh — locate the CURRENT session's transcript and produce a
# compact conversation extract for wrap analysis agents.
#
# Usage: collect-context.sh <nonce> [out-dir]
#
#   <nonce>   A literal token the caller has ALREADY typed into the
#             conversation. The invocation command line itself is recorded in
#             the current session's transcript before execution, so the
#             transcript containing this token IS the current session. The
#             caller must type literal random characters — a $(...) expansion
#             would put the unexpanded form in the transcript and never match.
#   [out-dir] Where to write the extract (default: $TMPDIR, else /tmp).
#
# Prints KEY=VALUE lines on stdout:
#   CONTEXT_FILE      path of the extract (user + assistant text only)
#   CONTEXT_BYTES     size of the extract
#   TRANSCRIPT        transcript the extract came from
#   TRANSCRIPT_AGE_S  seconds since that transcript was last written
#   MATCHED           "nonce" (certain) or "newest-fallback" (may be a sibling
#                     session — caller must warn downstream)
#   REPO, HEAD, DIRTY revision pin for agents (repo abs path, short sha,
#                     dirty-file count); REPO="(not a git repo)" outside git

set -euo pipefail

NONCE="${1:?usage: collect-context.sh <nonce> [out-dir]}"
OUT_DIR="${2:-${TMPDIR:-/tmp}}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq)" >&2; exit 1; }

# Claude Code encodes the project cwd by replacing path separators and dots
# with '-'. Example: /Users/foo/my.project -> -Users-foo-my-project
SLUG=$(printf '%s' "$PWD" | tr '/.' '--')
PROJ_DIR="$HOME/.claude/projects/$SLUG"
if [ ! -d "$PROJ_DIR" ]; then
  echo "ERROR: no session directory at $PROJ_DIR (cwd not a Claude Code project root?)" >&2
  exit 1
fi

# Find the transcript containing the nonce, newest first — the current session
# appended the invocation moments ago, so the first file checked usually hits.
MATCHED="newest-fallback"
TRANSCRIPT=""
while read -r f; do
  [ -f "$f" ] || continue
  n=$(grep -c -F "$NONCE" "$f" 2>/dev/null || true)
  if [ "${n:-0}" -gt 0 ]; then
    TRANSCRIPT="$f"
    MATCHED="nonce"
    break
  fi
done < <(ls -t "$PROJ_DIR"/*.jsonl 2>/dev/null || true)

if [ -z "$TRANSCRIPT" ]; then
  TRANSCRIPT=$(ls -t "$PROJ_DIR"/*.jsonl 2>/dev/null | head -1 || true)
fi
if [ -z "$TRANSCRIPT" ]; then
  echo "ERROR: no transcripts under $PROJ_DIR" >&2
  exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
CONTEXT_FILE="$OUT_DIR/wrap-context-$STAMP.txt"

# Extract only conversation text. Everything else (thinking, tool_use blocks,
# file-history snapshots, queue operations) is noise for wrap analysis and is
# the bulk of the file size. jq may exit non-zero on a malformed trailing line
# of a live transcript; a partial extract is still valid, so tolerate it.
jq -r '
  if .type == "user" then
    ( .message.content
      | if type == "string" then .
        else ([.[]? | select(.type? == "text") | .text] | join("\n"))
        end
      | select(length > 0)
      | "== USER ==\n" + . )
  elif .type == "assistant" then
    ( [.message.content[]? | select(.type? == "text") | .text]
      | select(length > 0)
      | "== ASSISTANT ==\n" + join("\n") )
  else
    empty
  end
' "$TRANSCRIPT" 2>/dev/null > "$CONTEXT_FILE" || true

CONTEXT_BYTES=$(stat -f %z "$CONTEXT_FILE" 2>/dev/null || stat -c %s "$CONTEXT_FILE" 2>/dev/null || echo 0)
if [ "${CONTEXT_BYTES:-0}" -eq 0 ]; then
  echo "ERROR: extract came out empty (transcript: $TRANSCRIPT)" >&2
  exit 1
fi

NOW=$(date +%s)
MTIME=$(stat -f %m "$TRANSCRIPT" 2>/dev/null || stat -c %Y "$TRANSCRIPT" 2>/dev/null || echo "$NOW")
AGE=$((NOW - MTIME))

if REPO=$(git rev-parse --show-toplevel 2>/dev/null); then
  HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo none)
  DIRTY=$(git status --porcelain 2>/dev/null | grep -c . || true)
else
  REPO="(not a git repo)"
  HEAD="none"
  DIRTY=0
fi

printf 'CONTEXT_FILE=%s\n' "$CONTEXT_FILE"
printf 'CONTEXT_BYTES=%s\n' "$CONTEXT_BYTES"
printf 'TRANSCRIPT=%s\n' "$TRANSCRIPT"
printf 'TRANSCRIPT_AGE_S=%s\n' "$AGE"
printf 'MATCHED=%s\n' "$MATCHED"
printf 'REPO=%s\n' "$REPO"
printf 'HEAD=%s\n' "$HEAD"
printf 'DIRTY=%s\n' "${DIRTY:-0}"
