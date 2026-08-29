#!/bin/bash
# collect-context.sh — locate the CURRENT session's transcript and produce a
# compact conversation extract for wrap analysis agents.
#
# Usage: collect-context.sh <nonce> [out-dir]
#
#   <nonce>   FALLBACK ONLY, used when CLAUDE_CODE_SESSION_ID is unavailable.
#             A literal token the caller has ALREADY typed into the
#             conversation. The invocation command line itself is recorded in
#             the current session's transcript before execution, so a token
#             found in exactly one transcript identifies that session. The
#             caller must type literal random characters — a $(...) expansion
#             would put the unexpanded form in the transcript and never match.
#             It is NOT a reliable identifier on its own: sibling sessions run
#             by the same model from the same instruction pick the same
#             "random" token, so a multi-transcript hit yields MATCHED=ambiguous
#             rather than a confident pick.
#   [out-dir] Where to write the extract (default: $TMPDIR, else /tmp).
#
# Prints KEY=VALUE lines on stdout:
#   CONTEXT_FILE      path of the extract (user + assistant text only)
#   CONTEXT_BYTES     size of the extract
#   TRANSCRIPT        transcript the extract came from
#   TRANSCRIPT_AGE_S  seconds since that transcript was last written
#   MATCHED           "session-id" (certain) | "nonce" (certain, unique hit) |
#                     "ambiguous" (nonce hit >1 transcript — sibling collision,
#                     the extract may be another session) | "newest-fallback"
#                     (no hit at all). Caller must warn downstream on the last
#                     two and should not feed agents an unverified extract.
#   REPO, HEAD, DIRTY revision pin for agents (repo abs path, short sha,
#                     dirty-file count); REPO="(not a git repo)" outside git

set -euo pipefail

NONCE="${1:?usage: collect-context.sh <nonce> [out-dir]}"
OUT_DIR="${2:-${TMPDIR:-/tmp}}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq)" >&2; exit 1; }

# Claude Code encodes the project cwd by replacing every character outside
# [A-Za-z0-9-] with '-'. Example: /Users/foo/my_project -> -Users-foo-my-project.
# Two sanitizer generations exist on disk: an older one kept '_' and '.', so no
# single expression addresses both — build BOTH candidates and let is-a-directory
# decide. The previous `tr '/.' '--'` left '_' intact and therefore exited 1 in
# every repo whose path holds one, which reads as "not a Claude Code project".
PROJ_DIR=""
for slug in "$(printf '%s' "$PWD" | sed 's/[^A-Za-z0-9-]/-/g')" \
            "$(printf '%s' "$PWD" | tr '/.' '--')"; do
  [ -d "$HOME/.claude/projects/$slug" ] || continue
  PROJ_DIR="$HOME/.claude/projects/$slug"
  break
done
if [ -z "$PROJ_DIR" ]; then
  echo "ERROR: no session directory for $PWD under $HOME/.claude/projects (cwd not a Claude Code project root?)" >&2
  exit 1
fi

MATCHED="newest-fallback"
TRANSCRIPT=""

# Preferred: the session id names its own transcript file, so nothing has to be
# inferred. Claude Code exports it to every Bash subprocess.
if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] \
   && [ -f "$PROJ_DIR/$CLAUDE_CODE_SESSION_ID.jsonl" ]; then
  TRANSCRIPT="$PROJ_DIR/$CLAUDE_CODE_SESSION_ID.jsonl"
  MATCHED="session-id"
fi

# Fallback: the nonce. Scan EVERY transcript and count the hits rather than
# stopping at the first, because the nonce is not reliably unique.
#
# The caller typing "literal random characters" is the same model reading the
# same instruction and the same example, so sessions converge on the same token:
# `wrap-q7m4z8` was measured in 13 transcripts on 2026-08-28 and typed again by
# an unrelated session on 08-29, so the scheme has no entropy across siblings
# OR across days. The old loop broke at the first hit in newest-first order and
# still reported MATCHED=nonce, handing callers another session's conversation
# while telling them the match was certain. A collision must degrade to an
# explicit "ambiguous", never to a confident wrong answer.
if [ -z "$TRANSCRIPT" ]; then
  HITS=""
  for f in $(ls -t "$PROJ_DIR"/*.jsonl 2>/dev/null || true); do
    [ -f "$f" ] || continue
    n=$(grep -c -F "$NONCE" "$f" 2>/dev/null || true)
    [ "${n:-0}" -gt 0 ] && HITS="$HITS$f"$'\n'
  done
  HIT_COUNT=$(printf '%s' "$HITS" | grep -c . || true)
  if [ "${HIT_COUNT:-0}" -eq 1 ]; then
    TRANSCRIPT=$(printf '%s' "$HITS" | head -1)
    MATCHED="nonce"
  elif [ "${HIT_COUNT:-0}" -gt 1 ]; then
    TRANSCRIPT=$(printf '%s' "$HITS" | head -1)   # newest of the colliding set
    MATCHED="ambiguous"
  fi
fi

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
