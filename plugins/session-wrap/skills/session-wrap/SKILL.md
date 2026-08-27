---
name: session-wrap
description: This skill should be used when the user asks to "wrap up session", "end session", "session wrap", "/wrap", "document learnings", "what should I commit", or wants to analyze completed work before ending a coding session.
version: 3.0.0
---

# Session Wrap Skill

Session wrap-up workflow: feed agents the REAL conversation (not a 3-line summary), run a slim two-agent analysis pinned to a specific repo revision, validate proposals only when there are proposals, and save a handoff-grade session summary.

## Execution Flow

```
┌─────────────────────────────────────────────────────┐
│  1. Collect Context (git status + transcript        │
│     extract + repo@HEAD pin via collect-context.sh) │
├─────────────────────────────────────────────────────┤
│  2. Phase 1: 2 Analysis Agents (Parallel)           │
│     ┌─────────────────┬─────────────────┐           │
│     │ knowledge-      │ continuity-     │           │
│     │ curator         │ auditor         │           │
│     │ (learnings +    │ (TODOs, verify  │           │
│     │  placement)     │  cmds, autom.)  │           │
│     └─────────────────┴─────────────────┘           │
├─────────────────────────────────────────────────────┤
│  3. Phase 2: duplicate-checker (CONDITIONAL —       │
│     only if Phase 1 proposed additions)             │
├─────────────────────────────────────────────────────┤
│  4. Integrate Results & AskUserQuestion             │
├─────────────────────────────────────────────────────┤
│  5. Execute Selected Actions                        │
│     • Save session summary → .claude-sessions/      │
│     • Create commit / Update docs / Automation      │
└─────────────────────────────────────────────────────┘
```

## Step 1: Collect Context

```bash
git status --short
git log --oneline -10
```

Then run the context collector. **Type a literal random token yourself** (e.g. `wrap-k3v9x2` — actual random characters you generate; never `$(...)` substitution, because the transcript must contain the literal token for self-identification):

```bash
bash ${baseDir}/scripts/collect-context.sh wrap-XXXXXX
```

It prints `KEY=VALUE` lines:

- `CONTEXT_FILE` — compact extract of the current conversation (user + assistant text only, thinking/tool noise stripped)
- `MATCHED` — `nonce` (certain: this session) or `newest-fallback` (uncertain: could be a concurrent sibling session; if so, warn in the final report)
- `REPO`, `HEAD`, `DIRTY` — the revision pin agents must verify claims against

Compose a Session Summary yourself (work done, files touched, key decisions). Agents receive BOTH your summary and the context file — your summary orients, the context file is the evidence source.

## Step 2: Phase 1 - Analysis Agents (Parallel)

Execute 2 agents in parallel (single message with 2 Task calls). Include this common block VERBATIM at the top of both prompts:

```
Session Summary:
- Work: [main tasks performed]
- Files: [created/modified files]
- Decisions: [key decisions made]

Context file: [CONTEXT_FILE path] — Read it; it is the actual conversation.
Repo: [REPO] @ [HEAD] (dirty files: [DIRTY])

Ground rules (unconditional):
- Verify any claim about current file/repo state by reading files under the
  repo path above. If the checkout you read is NOT at the HEAD above, report
  the mismatch instead of raising findings from it.
- Every finding carries evidence: file:line, a command you ran with its
  output, or a quote from the context file. Label OBSERVED vs INFERRED.
- Your report is raw input; the main session verifies before acting.
```

```
Task(
    subagent_type="knowledge-curator",
    description="Learnings + placement analysis",
    prompt="[Common block]\n\nExtract session learnings and route each to its correct documentation home, with duplicate-check evidence per proposal."
)

Task(
    subagent_type="continuity-auditor",
    description="Continuity + automation audit",
    prompt="[Common block]\n\nIdentify incomplete work (verified, with per-TODO verification commands), automation opportunities, priorities, and an anti-task list."
)
```

| Agent | Role | Output |
|-------|------|--------|
| **knowledge-curator** | Learnings, mistakes, placement routing (memory/CLAUDE.md/project docs) | Placement proposals with dedup evidence |
| **continuity-auditor** | Incomplete work, follow-up priorities, automation patterns, refuted approaches | Verified TODO list + anti-task list |

## Step 3: Phase 2 - Validation (Conditional)

Run `duplicate-checker` ONLY if Phase 1 produced addition proposals (docs, memory, automation). If both agents reported "no additions", skip and note "Phase 2 skipped: no addition proposals".

```
Task(
    subagent_type="duplicate-checker",
    description="Phase 1 proposal validation",
    prompt="""
Validate these Phase 1 proposals for duplicates.

## knowledge-curator proposals:
[results]

## continuity-auditor automation proposals:
[results]

Classify each: Approved / Merge (with target) / Skip (with existing location).
"""
)
```

## Step 4: Integrate Results

```markdown
## Wrap Analysis Results

### Knowledge & Placement
[knowledge-curator summary + duplicate-checker verdicts]

### Follow-up Tasks
[continuity-auditor summary]

### Automation Suggestions
[continuity-auditor automation section + duplicate-checker verdicts]
```

Where an agent's claim conflicts with what you observed in the session yourself, your observation wins — agents saw an extract; verify their flagged lines before presenting them as facts.

## Step 5: Action Selection

```
AskUserQuestion(
    questions=[{
        "question": "Which actions would you like to perform?",
        "header": "Wrap Options",
        "multiSelect": true,
        "options": [
            {"label": "Save session summary (Recommended)", "description": "Save to .claude-sessions/ for next session context"},
            {"label": "Create commit", "description": "Commit changes"},
            {"label": "Update docs/memory", "description": "Apply approved placement proposals"},
            {"label": "Create automation", "description": "Generate skill/command/agent"},
            {"label": "Skip", "description": "End without action"}
        ]
    }]
)
```

If the user's global configuration declares machine-local wrap options (e.g. a "Session Wrap Settings" section with an extra backup destination), offer those options too — that section, not this skill, owns machine-specific paths and gates.

## Step 6: Execute Selected Actions

Execute only the actions selected by user.

### Save Session Summary

If "Save session summary" selected:

1. **Create directory** (if not exists):
   ```bash
   mkdir -p .claude-sessions
   ```

2. **Generate filename**: `YYYY-MM-DD-HH-mm-topic.md`
   - Topic: 2-4 word summary in kebab-case (e.g., `auth-bug-fix`, `api-refactor`)

3. **Verify TODOs before writing** (author-side stale-TODO prevention):

   For each TODO that will appear in `미완료 작업 / TODO` — **especially items
   inherited from prior-session carryover context** (loaded `.claude-sessions/*.md`
   history, "P0 from last session", etc.) — verify the state before writing:

   ```bash
   # Per-TODO verification
   git log --oneline --since="2 weeks ago" -- <relevant-path> | grep -i "<todo-keyword>"
   ```

   Plus a targeted file read of the referenced code/file. Classify each TODO:

   - **STILL_OPEN**: no matching commit, current code still matches the described problem → keep
   - **LIKELY_DONE**: matching commit + file state no longer matches → drop from the list
   - **UNCLEAR**: partial match or ambiguous evidence → keep but flag with `(verify)` suffix

   Write only STILL_OPEN and UNCLEAR entries into the session file. Do not
   propagate LIKELY_DONE items — the next session will inherit them as stale
   carryover and burn cycles re-verifying.

   **Why:** multi-session parallel work makes carryover TODO lists go stale
   fast. Trusting them without `git log --grep` cross-check taxes ~10min per
   stale item.

4. **Handoff contract** (unconditional — applies to every session file):

   - Every TODO carries the command that answers whether it is still open,
     so the next session verifies in one paste instead of re-deriving.
   - Live measurements are NOT handed off — write the re-measure command
     instead. Exception: retention-bound captures (in-memory logs, rotating
     buffers) — there the timestamped capture IS the deliverable; keep it.
   - If the session refuted approaches, include a `하지 말 것` (anti-task)
     section: each refuted approach with the evidence that killed it and the
     axis it was refuted on.

5. **Write session file** with this template:
   ```markdown
   # [Session Title]

   ## 요약
   [1-2 sentence summary of what was done]

   ## 주요 작업
   - [Task 1, with evidence of verification]

   ## 미완료 작업 / TODO
   - [ ] [P1. Task — one-line state] 확인: `command that answers if still open`

   ## 하지 말 것
   - [Refuted approach — refuting evidence and its axis] (omit section if none)

   ## 다음 세션 제안
   [continuity-auditor recommendations, filtered by your own judgment]
   ```

6. **Lint before save**: if the user's environment defines a prose linter for
   human-read session documents (check their global config), run it on the
   file and fix violations before reporting the save.

7. **Confirm save location**:
   ```
   ✅ Session saved: .claude-sessions/YYYY-MM-DD-HH-mm-topic.md
   ```

---

## Quick Reference

### When to Use

- End of significant work session
- Before switching to different project
- After completing a feature or fixing a bug

### When to Skip

- Very short session with trivial changes
- Only reading/exploring code
- Quick one-off question answered

### Arguments

- Empty: Proceed interactively (full workflow)
- Message provided: Use as commit message and commit directly

## Additional Resources

See `references/multi-agent-patterns.md` for detailed orchestration patterns.
