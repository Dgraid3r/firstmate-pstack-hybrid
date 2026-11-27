# pstack hybrid setup

This fork combines firstmate with the pstack skill set (poteto-mode and the skills it routes to), adapted for Claude Code.
One clone gives you both.
Firstmate supervises and delegates.
Its workers, and any other Claude Code session on the machine, follow poteto-mode's playbooks.

## Requirements

- Git and [Claude Code](https://claude.com/claude-code).
- The pstack skills work on macOS, Linux and Windows.
- Firstmate itself runs on macOS and Linux only. On Windows, run firstmate inside WSL2 and do the whole setup there. The skills alone also install natively under Git Bash.
- Firstmate's own requirements are in the README's [Quick Start](../README.md#quick-start).

## Install

1. Clone the fork.

   ```sh
   git clone https://github.com/Dgraid3r/firstmate-pstack-hybrid.git firstmate
   cd firstmate
   ```

2. Preview the skill install, then run it.

   ```sh
   bin/fm-install-skills.sh --dry-run
   bin/fm-install-skills.sh
   ```

   This links every skill under `skills/` into `~/.claude/skills/`, and installs the worker agent types under `agents/` into `~/.claude/agents/`.
   A skill folder already there that is not a link to this clone is reported as a conflict and left alone.
   Add `--force` to move such folders into `~/.claude/skills/.pstack-backup-<time>/` and link in their place.
   Re-running is safe.
   Under Git Bash on Windows, the links are directory junctions. The script also repairs this clone's `.claude/skills` link to firstmate's internal skills, which a Windows checkout turns into a plain text file.
   Agent types are single files. On macOS and Linux they are symlinks. Under Git Bash on Windows they are copies, because a junction cannot link a file and a hard link would not survive `git pull`.
   A file already in `~/.claude/agents/` with the same content counts as installed. One with different content is a conflict, left alone unless you pass `--force`, which backs it up to `~/.claude/agents/.pstack-backup-<time>/`.

   The installer also copies [`templates/brief-include.pstack.md`](../templates/brief-include.pstack.md) to `config/brief-include.md` in the active home (`FM_HOME` if set, else this clone), creating `config/` if needed.
   Firstmate appends that file word for word to every ship and scout brief, as a final `# Home brief additions` section.
   That is how workers learn the pstack working style, without this fork editing `bin/fm-brief.sh`.
   `config/` is gitignored, so the file is per home and a `git pull` never changes it.
   Secondmate homes do not inherit it, so run the installer in each home, with that home's `FM_HOME` set.
   An existing `config/brief-include.md` that differs is reported as a conflict and left alone, and `--force` backs it up to `config/.pstack-backup-<time>/` first.

3. Optionally choose models. In a Claude Code session, run `/setup-pstack`.
   It writes `~/.claude/pstack-models.md` and imports it from `~/.claude/CLAUDE.md`.
   Without it, the defaults in [`skills/poteto-mode/references/claude-code.md`](../skills/poteto-mode/references/claude-code.md) apply.

4. Start firstmate as the README's [Install and launch](../README.md#install-and-launch) section describes.

New Claude Code sessions pick up the skills. A session that was already open needs a restart.

## Use

- In any Claude Code session, type `/poteto-mode` to work in that style. It never turns itself on.
- Inside firstmate, every worker's instructions tell it to follow the matching poteto-mode playbook whenever the skill is installed. The worker's delivery rules from firstmate still win, so no-mistakes or the PR path owns review and merging.
- [`skills/poteto-mode/references/claude-code.md`](../skills/poteto-mode/references/claude-code.md) translates every Cursor-specific part of pstack to Claude Code. That covers subagents, models, missing Cursor skills, delivery without Graphite, and which playbooks firstmate workers use.

## Worker types

Firstmate can supervise on a strong model while each task runs on a cheaper one.
The installer adds four Claude Code subagents from [`agents/`](../agents), each pinned to a model and effort in its own frontmatter:

| Type | Model, effort | Use |
| --- | --- | --- |
| `fm-planner` | opus, high | Read-only. Breaks a task into small, ordered, verifiable chunks, one PR each, and marks which are safety-critical. |
| `fm-builder` | sonnet, medium | Builds one routine chunk with poteto-mode's playbooks in a light form. |
| `fm-safety` | opus, high | Builds a safety-critical or security-sensitive chunk, with extra verification. |
| `fm-mechanic` | haiku, low | Command-driven finishing: resuming a validation run, checking branch and PR state, cleanup. Never writes code. |

The flow is the planner first, then a builder or safety worker per chunk, then the mechanic for finishing and cleanup.
Each worker follows its own task instructions from firstmate for scope, delivery and merge rules.
The expensive poteto panels (arena, interrogate, architect, swarm) stay off unless firstmate explicitly asks for one.
To change a type's model or effort, edit its file under `agents/` in this clone and re-run the installer, which refreshes Windows copies.
`/setup-pstack` still sets poteto-mode's own per-role models, which is separate from these worker types.

## Update

- `git pull` updates every installed skill, because they are links into this clone.
- Run `bin/fm-install-skills.sh` again after a pull that adds new skills or agent types. On Windows it also refreshes agent copies that a pull made stale, but never overwrites a file you edited.
- To take upstream firstmate changes:

  ```sh
  git remote add upstream https://github.com/kunchenguid/firstmate.git
  git remote set-url --push upstream DISABLED
  git fetch upstream
  git merge upstream/main
  ```

  The second command makes accidental pushes to upstream impossible.

## Uninstall

Delete the skill links in `~/.claude/skills/` and the `fm-*.md` agent files (plus `.pstack-agents.manifest`) in `~/.claude/agents/`.
On Windows the links are directory junctions. Remove each with `cmd /c rmdir <path>`, never `rm -rf`, which can delete the files the junction points to.
