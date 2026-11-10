# pstack on Claude Code

pstack was written for Cursor. This file is the single translation from Cursor to Claude Code. When you run in Claude Code, it overrides every Cursor-specific instruction in every pstack skill. Read it once per session before following a playbook.

## Tools

| Cursor | Claude Code |
| --- | --- |
| `Task` tool | `Agent` tool |
| `subagent_type: "poteto-agent"`, `generalPurpose` | `general-purpose`. Use `fork` when the delegate needs this conversation's context |
| `readonly` agent mode | `Explore` for read-only search. Use `general-purpose` when the delegate must run commands |
| `run_in_background: true` | Same parameter on `Agent` and `Bash` |
| Model slugs (`grok-*`, `gpt-*`, `claude-*-thinking-*`) | The `Agent` tool's `model` values: `haiku`, `sonnet`, `opus`, `fable`. Per-role choices come from `~/.claude/pstack-models.md` (see `setup-pstack`) |
| `AskQuestion` | `AskUserQuestion` |
| Cloud agents | `Agent` with `isolation: "remote"` where available. Otherwise run locally |

## Default models

Use these when `~/.claude/pstack-models.md` has no line for a role.

- Code delegates (feature, refactoring, swarm workers, explorers, investigators) use `sonnet`.
- Bug fixes, perf work, hillclimbs and reflect tooling use `opus`.
- Judgment, prose, synthesis and explainers use `opus`.
- The hardest tasks (cross-cutting design, subtle concurrency or algorithms) use `fable`.
- Panels (how critics, arena runners and cross-judge pool, architect runners, interrogate reviewers) use `fable, opus, sonnet`.

Every panel member is a Claude model. Treat panel agreement as a weaker signal than it is in the cross-vendor original.

## Paths

| Cursor | Claude Code |
| --- | --- |
| `.cursor/skills/` | `.claude/skills/` |
| `~/.cursor/skills/` | `~/.claude/skills/` |
| `~/.cursor/rules/pstack-models.mdc` | `~/.claude/pstack-models.md`, imported from `~/.claude/CLAUDE.md` |
| `~/.cursor/projects/<slug>/agent-transcripts/<uuid>/<uuid>.jsonl` | `~/.claude/projects/<slug>/<session-id>.jsonl` |
| `~/.cursor/plugins/` | Claude Code plugins, `~/.claude/plugins/` |

## Skills that do not exist here

- `/deslop` (cursor-team-kit). Run `unslop` on prose and `no-comments` on the diff.
- `control-cli`, `control-ui` (cursor-team-kit). Use the `run` skill to launch and drive the app. Use the browser tools (Claude in Chrome, Playwright) for web UIs.
- `create-skill` (Cursor built-in). Use the `skill-creator` skill plus `playbooks/authoring-a-skill.md`.
- Bugbot and the agentic security review are Cursor services. Apply `references/bugbot-triage.md` to whatever reviewer comments instead: GitHub reviews, no-mistakes findings, CI annotations.

## Delivery

Graphite (`gt`, merge-when-ready, stacks) is not used.

- Outside firstmate, use plain git branches and `gh pr create`. Stack dependent PRs by basing each branch on the previous one. Never arm an auto-merge.
- Inside firstmate, the task's delivery mode owns delivery. No-mistakes, direct-PR and local-only each have their own path to a PR or a ready branch. Merging always waits for the captain's word or the project's standing approval.

## Inside firstmate

Firstmate is the supervisor and never writes project code, so it does not run the build playbooks itself. Its workers do.

- Workers use Investigation, Bug fix, Perf issue, Hillclimb, Feature, Refactoring, Prototype, Visual parity, Runtime and Trace forensics, Eval, Authoring a skill and Multi-phase plan.
- Workers skip Babysit, Shipping, Autopilot-full, Autopilot-stack, Orchestrate, Autonomous run, Session pickup, Pause safely and Worktree cleanup. Firstmate and the delivery mode already own those jobs.
- Opening a PR follows the worker's instructions from firstmate, not `playbooks/opening-a-pr.md`.
- The bun scripts under `poteto-mode/scripts/` are optional. Skip them when `bun` is not installed.
