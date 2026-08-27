---
name: session-wrap
description: This skill should be used when the user asks to "wrap up session", "end session", "session wrap", "/wrap", "document learnings", "what should I commit", or wants to analyze completed work before ending a coding session.
version: 2.0.0
---

# Session Wrap Skill

Comprehensive session wrap-up workflow with multi-agent analysis.

## Execution Flow

```
┌─────────────────────────────────────────────────────┐
│  1. Check Git Status                                │
├─────────────────────────────────────────────────────┤
│  2. Phase 1: 4 Analysis Agents (Parallel)           │
│     ┌─────────────────┬─────────────────┐           │
│     │  doc-updater    │  automation-    │           │
│     │  (docs update)  │  scout          │           │
│     ├─────────────────┼─────────────────┤           │
│     │  learning-      │  followup-      │           │
│     │  extractor      │  suggester      │           │
│     └─────────────────┴─────────────────┘           │
├─────────────────────────────────────────────────────┤
│  3. Phase 2: Validation Agent (Sequential)          │
│     ┌───────────────────────────────────┐           │
│     │       duplicate-checker           │           │
│     │  (Validate Phase 1 proposals)     │           │
│     └───────────────────────────────────┘           │
├─────────────────────────────────────────────────────┤
│  4. Integrate Results & AskUserQuestion             │
├─────────────────────────────────────────────────────┤
│  5. Execute Selected Actions                        │
│     • Save session summary → .claude-sessions/      │
│     • Create commit                                 │
│     • Update CLAUDE.md                              │
│     • Create automation                             │
└─────────────────────────────────────────────────────┘
```

## Step 1: Check Git Status

```bash
git status --short
git diff --stat HEAD~3 2>/dev/null || git diff --stat
```

## Step 2: Phase 1 - Analysis Agents (Parallel)

Execute 4 agents in parallel (single message with 4 Task calls).

### Session Summary (Provide to all agents)

```
Session Summary:
- Work: [Main tasks performed in session]
- Files: [Created/modified files]
- Decisions: [Key decisions made]
```

### Parallel Execution

```
Task(
    subagent_type="doc-updater",
    description="Document update analysis",
    prompt="[Session Summary]\n\nAnalyze if CLAUDE.md, context.md need updates."
)

Task(
    subagent_type="automation-scout",
    description="Automation pattern analysis",
    prompt="[Session Summary]\n\nAnalyze repetitive patterns or automation opportunities."
)

Task(
    subagent_type="learning-extractor",
    description="Learning points extraction",
    prompt="[Session Summary]\n\nExtract learnings, mistakes, and new discoveries."
)

Task(
    subagent_type="followup-suggester",
    description="Follow-up task suggestions",
    prompt="[Session Summary]\n\nSuggest incomplete tasks and next session priorities."
)
```

### Agent Roles

| Agent | Role | Output |
|-------|------|--------|
| **doc-updater** | Analyze CLAUDE.md/context.md updates | Specific content to add |
| **automation-scout** | Detect automation patterns | skill/command/agent suggestions |
| **learning-extractor** | Extract learning points | TIL format summary |
| **followup-suggester** | Suggest follow-up tasks | Prioritized task list |

## Step 3: Phase 2 - Validation Agent (Sequential)

Run after Phase 1 completes (dependency on Phase 1 results).

```
Task(
    subagent_type="duplicate-checker",
    description="Phase 1 proposal validation",
    prompt="""
Validate Phase 1 analysis results.

## doc-updater proposals:
[doc-updater results]

## automation-scout proposals:
[automation-scout results]

Check if proposals duplicate existing docs/automation:
1. Complete duplicate: Recommend skip
2. Partial duplicate: Suggest merge approach
3. No duplicate: Approve for addition
"""
)
```

## Step 4: Integrate Results

```markdown
## Wrap Analysis Results

### Documentation Updates
[doc-updater summary]
- Duplicate check: [duplicate-checker feedback]

### Automation Suggestions
[automation-scout summary]
- Duplicate check: [duplicate-checker feedback]

### Learning Points
[learning-extractor summary]

### Follow-up Tasks
[followup-suggester summary]
```

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
            {"label": "Update CLAUDE.md", "description": "Document new knowledge/workflows"},
            {"label": "Create automation", "description": "Generate skill/command/agent"},
            {"label": "Skip", "description": "End without action"}
        ]
    }]
)
```

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
   stale item. See project memory `learning_stale-session-todos.md` for details.

4. **Write session file** with this template:
   ```markdown
   # [Session Title]

   ## 요약
   [1-2 sentence summary of what was done]

   ## 주요 작업
   - [Task 1]
   - [Task 2]

   ## 미완료 작업 / TODO
   - [ ] [Incomplete task 1]
   - [ ] [Incomplete task 2]

   ## 다음 세션 제안
   [followup-suggester recommendations]
   ```

5. **Confirm save location**:
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
