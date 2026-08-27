---
description: Session wrap-up - analyze session, suggest documentation updates, automation opportunities, and follow-up tasks
allowed-tools: Bash(git *), Bash(bash *), Read, Write, Edit, Glob, Grep, Task, AskUserQuestion
---

# Session Wrap-up (/wrap)

Wrap up the current session by analyzing work done and suggesting improvements.

## Prerequisites

Before starting, load the session-wrap skill for detailed workflow guidance.

## Quick Usage

- `/wrap` - Interactive session wrap-up (recommended)
- `/wrap [message]` - Quick commit with provided message

## Execution

Follow the workflow defined in the **session-wrap** skill:

1. Collect context (git status + `collect-context.sh` transcript extract + repo@HEAD pin)
2. Phase 1: Run 2 analysis agents in parallel (knowledge-curator, continuity-auditor)
3. Phase 2: Run duplicate-checker ONLY if Phase 1 proposed additions
4. Integrate results and present options
5. Execute selected actions

Refer to `skills/session-wrap/SKILL.md` for detailed execution steps and agent configurations. This file is a pointer — workflow rules live in the skill, never here.
