# Session Wrap Plugin

A Claude Code plugin for session wrap-up with real-transcript-fed multi-agent analysis.

## Features

- **Real Session Context**: `collect-context.sh` extracts the actual conversation (93% size reduction) and feeds it to analysis agents — no more analysis from a 3-line summary
- **Revision-Pinned Analysis**: agents receive `repo @ HEAD` and must verify claims against that checkout, reporting mismatches instead of raising stale-checkout false alarms
- **Slim 2-Phase Architecture**: two parallel analysis agents, plus a validation agent that runs only when there are proposals to validate
- **Verified TODO Handoffs**: every follow-up task is checked against git/file state before it is written, and carries the command that answers whether it is still open
- **Learning Capture with Placement**: learnings routed to their correct home (auto-memory, CLAUDE.md, project docs) with duplicate-check evidence per proposal
- **Anti-Task Lists**: approaches refuted during the session are recorded with their refuting evidence, so the next session does not retry them

## Installation

### Option 1: Plugin Directory

```bash
# Clone or copy to your plugins directory
git clone https://github.com/team-attention/plugins-for-claude-natives
cd plugins-for-claude-natives/plugins/session-wrap

# Or copy directly
cp -r session-wrap ~/.claude/plugins/
```

### Option 2: Direct Use

```bash
claude --plugin-dir /path/to/session-wrap
```

## Usage

### Basic Usage

```
/wrap
```

Runs the full wrap-up workflow:
1. Collect context: git status + transcript extract + repo@HEAD pin
2. Phase 1: 2 analysis agents in parallel
3. Phase 2: validate proposals for duplicates (only if there are proposals)
4. Present results and let you choose actions
5. Execute selected actions

### Quick Commit

```
/wrap fix typo in README
```

When arguments are provided, creates a commit with that message directly.

## Architecture

```
collect-context.sh  →  conversation extract + repo@HEAD pin
                            │
Phase 1: Analysis (Parallel)
┌─────────────────────┬─────────────────────┐
│ knowledge-curator   │ continuity-auditor  │
│ learnings +         │ verified TODOs +    │
│ placement + dedup   │ automation + anti-  │
│ evidence            │ task list           │
└──────────┬──────────┴──────────┬──────────┘
           └──────────┬──────────┘
                      ▼
Phase 2: Validation (CONDITIONAL — only if additions proposed)
┌─────────────────────────────────────────────┐
│              duplicate-checker              │
└─────────────────────────────────────────────┘
                      │
                      ▼
              User Selection
```

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| `knowledge-curator` | inherit | Extract learnings, route each to its documentation home, dedup with evidence |
| `continuity-auditor` | inherit | Verify incomplete work, attach verification commands, automation scouting, anti-task list |
| `duplicate-checker` | haiku | Independent second-pass duplicate validation (conditional) |

## Skills

### session-wrap
Wrap-up workflow: context collection, 2-agent analysis, conditional validation, handoff-grade session summaries.

**Trigger phrases:** "session wrap-up", "wrap up session", "end session", "/wrap"

### history-insight
Claude Code 세션 히스토리를 분석하고 인사이트를 추출합니다.

**Trigger phrases:** "capture session", "save session history", "what we discussed", "today's work", "session history"

### session-analyzer
Post-hoc analysis tool for validating Claude Code session behavior against SKILL.md specifications.

**Trigger phrases:** "analyze session", "세션 분석", "evaluate skill execution", "check session logs"

## Directory Structure

```
session-wrap/
├── .claude-plugin/
│   └── plugin.json           # Plugin manifest
├── commands/
│   └── wrap.md               # /wrap command (pointer to the skill)
├── agents/
│   ├── knowledge-curator.md  # Learnings + placement + dedup
│   ├── continuity-auditor.md # Verified TODOs + automation + anti-tasks
│   └── duplicate-checker.md  # Conditional validation
├── skills/
│   ├── session-wrap/
│   │   ├── SKILL.md          # Workflow definition
│   │   ├── scripts/
│   │   │   └── collect-context.sh
│   │   └── references/
│   │       └── multi-agent-patterns.md
│   ├── history-insight/
│   │   ├── SKILL.md          # Session history analysis
│   │   ├── scripts/
│   │   │   └── extract-session.sh
│   │   └── references/
│   │       └── session-file-format.md
│   └── session-analyzer/
│       ├── SKILL.md          # Post-hoc session validation
│       ├── scripts/
│       │   ├── extract-hook-events.sh
│       │   ├── extract-subagent-calls.sh
│       │   └── find-session-files.sh
│       └── references/
│           ├── analysis-patterns.md
│           └── common-issues.md
└── README.md
```

## When to Use

**Use `/wrap` when:**
- Ending a significant work session
- Before switching to a different project
- After completing a feature or bug fix
- When unsure what to document

**Skip when:**
- Very short session with trivial changes
- Only reading/exploring code
- Quick one-off question answered

## Integration with plugin-dev

When `continuity-auditor` recommends creating a new skill/command/agent, use:

```
/plugin-dev:create-plugin
```

This will guide you through creating a well-structured automation.

## Migrating from 1.x

The four Phase 1 agents (`doc-updater`, `automation-scout`, `learning-extractor`, `followup-suggester`) were consolidated into two (`knowledge-curator`, `continuity-auditor`). Motivation, measured on real usage: each agent spawn cost ~70k tokens of context inheritance before doing any work, a full wrap took ~30 minutes of wall clock, and the validation phase was skipped by operators in a third of runs — while analysis quality was limited by agents seeing only a summary, which the transcript feed fixes.

## References

- [Anthropic Multi-Agent Research](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Azure AI Agent Design Patterns](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)

## License

MIT
