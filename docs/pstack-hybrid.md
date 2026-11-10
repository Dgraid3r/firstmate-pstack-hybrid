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

   This links every skill under `skills/` into `~/.claude/skills/`.
   A skill folder already there that is not a link to this clone is reported as a conflict and left alone.
   Add `--force` to move such folders into `~/.claude/skills/.pstack-backup-<time>/` and link in their place.
   Re-running is safe.
   Under Git Bash on Windows, the links are directory junctions. The script also repairs this clone's `.claude/skills` link to firstmate's internal skills, which a Windows checkout turns into a plain text file.

3. Optionally choose models. In a Claude Code session, run `/setup-pstack`.
   It writes `~/.claude/pstack-models.md` and imports it from `~/.claude/CLAUDE.md`.
   Without it, the defaults in [`skills/poteto-mode/references/claude-code.md`](../skills/poteto-mode/references/claude-code.md) apply.

4. Start firstmate as the README's [Install and launch](../README.md#install-and-launch) section describes.

New Claude Code sessions pick up the skills. A session that was already open needs a restart.

## Use

- In any Claude Code session, type `/poteto-mode` to work in that style. It never turns itself on.
- Inside firstmate, every worker's instructions tell it to follow the matching poteto-mode playbook whenever the skill is installed. The worker's delivery rules from firstmate still win, so no-mistakes or the PR path owns review and merging.
- [`skills/poteto-mode/references/claude-code.md`](../skills/poteto-mode/references/claude-code.md) translates every Cursor-specific part of pstack to Claude Code. That covers subagents, models, missing Cursor skills, delivery without Graphite, and which playbooks firstmate workers use.

## Update

- `git pull` updates every installed skill, because they are links into this clone.
- Run `bin/fm-install-skills.sh` again after a pull that adds new skills.
- To take upstream firstmate changes:

  ```sh
  git remote add upstream https://github.com/kunchenguid/firstmate.git
  git remote set-url --push upstream DISABLED
  git fetch upstream
  git merge upstream/main
  ```

  The second command makes accidental pushes to upstream impossible.

## Uninstall

Delete the skill links in `~/.claude/skills/`.
On Windows the links are directory junctions. Remove each with `cmd /c rmdir <path>`, never `rm -rf`, which can delete the files the junction points to.
