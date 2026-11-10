---
name: setup-pstack
description: Configure which models pstack uses per role. Writes a model rule that Claude Code loads in every session and that overrides the skill defaults. Use for /setup-pstack, "configure pstack models", or changing pstack's model choices.
---

# Setup pstack

Write `~/.claude/pstack-models.md`, the per-role model choices for pstack, and make sure `~/.claude/CLAUDE.md` imports it so every session sees it. The skills read it and fall back to the defaults in `poteto-mode/references/claude-code.md` when a line is absent, so this is an override layer, not a requirement.

## Steps

### 1. Know the available models

The `Agent` tool's `model` parameter accepts `haiku`, `sonnet`, `opus` and `fable`. Those four are the only values to write. The alias `inherit-parent` is also valid and means the role runs on the parent session's model (omit `model`).

### 2. Load current state

If `~/.claude/pstack-models.md` exists, read it and treat its values as the current choices. Otherwise start from the defaults in `poteto-mode/references/claude-code.md`.

### 3. Map and confirm

Show every role with its current model. Ask whether to accept as-is or change specific roles, offering the four models plus `inherit-parent`. Prefer `AskUserQuestion` over free text. For panel roles (how critics, arena runners, architect runners, interrogate reviewers) the value is a list, and one subagent runs per entry, so the list length sets the count. `arena cross-judge pool` is also a list, and Arena picks one value from it that differs from the parent's model when possible. `swarm workers` is the default model for every worker unless a race or comparison assigns another model per arm.

### 4. Validate

Every value must be one of the four models or `inherit-parent`. Anything else breaks every delegation that reads it, so stop and ask again.

### 5. Write the rule

Overwrite `~/.claude/pstack-models.md` with one line per role, using the labels below, so re-runs stay idempotent. Then make sure `~/.claude/CLAUDE.md` contains the line `@~/.claude/pstack-models.md`. Create the file if it is missing, and add the line only when it is not already there. Shape:

```
# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` as a value: the role runs on the parent session's model (omit the Agent `model`). Alias entries in a panel list still count toward its fan-out.
feature, refactoring: sonnet
bug-fix: opus
perf-issue: opus
hillclimb: opus
judgment and prose: opus
hardest tasks: fable
how explorer: sonnet
how explainer: opus
how critics: fable, opus, sonnet
why investigators: sonnet
why synthesizer: opus
reflect tooling: opus
reflect judgment, divergent, synthesizer: opus
arena runners: fable, opus, sonnet
arena cross-judge pool: fable, opus, sonnet
swarm workers: sonnet
architect runners: fable, opus, sonnet
interrogate reviewers: fable, opus, sonnet
```

### 6. Confirm

Tell the user the rule was written and that it applies to new sessions. Re-running this skill updates it.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or an existing harness). If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one with /create-verification-skill." On yes, invoke `/create-verification-skill` (resolves wherever pstack is installed — workspace, user, or plugin). On no, move on without pushing.
