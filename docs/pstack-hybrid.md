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

   This links every skill under `skills/` into `~/.claude/skills/`, and installs the agent types under `agents/` into `~/.claude/agents/`.
   A skill folder already there that is not a link to this clone is reported as a conflict and left alone.
   Add `--force` to move such folders into `~/.claude/skills/.pstack-backup-<time>/` and link in their place.
   Re-running is safe.
   Under Git Bash on Windows, the links are directory junctions. The script also repairs this clone's `.claude/skills` link to firstmate's internal skills, which a Windows checkout turns into a plain text file.
   Agent types are single files. On macOS and Linux they are symlinks. Under Git Bash on Windows they are copies, because a junction cannot link a file and a hard link would not survive `git pull`.
   A file already in `~/.claude/agents/` with the same content counts as installed. One with different content is a conflict, left alone unless you pass `--force`, which backs it up to `~/.claude/agents/.pstack-backup-<time>/`.

   The installer also copies [`templates/brief-include.pstack.md`](../templates/brief-include.pstack.md) to `brief-include.md` in the active home's config directory, creating it if needed.
   That directory is `FM_CONFIG_OVERRIDE` if set, else `config/` under `FM_HOME`, else this clone's `config/`.
   Firstmate appends that file to every ship and scout brief, as described in [Home brief include](configuration.md#home-brief-include-configbrief-includemd).
   That is how workers learn the pstack working style, without this fork editing `bin/fm-brief.sh`.
   `config/` is gitignored, so the file is per home and a `git pull` never changes it.
   Secondmate homes do not inherit it, so for each one, run this clone's installer with `FM_HOME=<secondmate home> bin/fm-install-skills.sh`.
   Do not run the secondmate home's own copy of the script: it reports the skills linked to this clone as conflicts, and `--force` would repoint those machine-wide links at that home.
   The same run installs `config/crew-dispatch.json`, described under [Worker types](#worker-types).
   Secondmate homes inherit that file from the primary home at each config convergence (a secondmate spawn, a bootstrap sweep or a `bin/fm-config-push.sh` run), so install it only in the primary home and never install or edit it per secondmate.
   The installer does not check which kind of home it runs in, so it writes the dispatch template into any home that lacks one.
   Run it with `FM_HOME` set to a secondmate home for the brief include only; the next config convergence replaces or removes a template written there.
   A conflict on that file in a secondmate home is expected and makes the run exit 1. Do not pass `--force` there, because that replaces the inherited file with the template until the next config convergence.
   An existing `config/brief-include.md` or `config/crew-dispatch.json` that differs is reported as a conflict and left alone, and `--force` backs it up to `config/.pstack-backup-<time>/` first.

3. Optionally choose models. In a Claude Code session, run `/setup-pstack`.
   It writes `~/.claude/pstack-models.md` and imports it from `~/.claude/CLAUDE.md`.
   Without it, the defaults in [`skills/poteto-mode/references/claude-code.md`](../skills/poteto-mode/references/claude-code.md) apply.

4. Start firstmate as the README's [Install and launch](../README.md#install-and-launch) section describes.

New Claude Code sessions pick up the skills. A session that was already open needs a restart.

## Use

- In any Claude Code session, type `/poteto-mode` to work in that style. It never turns itself on.
- Inside firstmate, a home whose `config/brief-include.md` holds the pstack template tells every ship and scout worker to follow the matching poteto-mode playbook whenever the skill is installed. The worker's delivery rules from firstmate still win, so no-mistakes or the PR path owns review and merging.
- [`skills/poteto-mode/references/claude-code.md`](../skills/poteto-mode/references/claude-code.md) translates every Cursor-specific part of pstack to Claude Code. That covers subagents, models, missing Cursor skills, delivery without Graphite, and which playbooks firstmate workers use.

## Worker types

Firstmate supervises on a strong model while each task runs on a cheaper one.
It does that through crew dispatch, not through agent types.
A crewmate is a full session that `fm-spawn.sh` launches with `--harness`, `--model` and `--effort`, so its tier is fixed at spawn.
Firstmate never launches the subagent types under [`agents/`](../agents).

The installer copies [`docs/examples/crew-dispatch.pstack.json`](examples/crew-dispatch.pstack.json) to `config/crew-dispatch.json`, as [Install](#install) step 2 describes, including the secondmate home rules.
The schema is in [Crew dispatch profiles](configuration.md#crew-dispatch-profiles-configcrew-dispatchjson).
The template sets these tiers:

| Work | Model, effort |
| --- | --- |
| Scout work: investigation, diagnosis, breaking a large ask into ordered chunks | opus, high |
| Ship work touching auth, encryption, data deletion, crisis handling or other safety-critical code | opus, high |
| Everything else | sonnet, medium |

The `why` of the template's safety rule tells firstmate to write the literal marker "safety-critical" in the brief's `## Firstmate spec`.
The pstack brief include then tells the worker to run interrogate on its own diff and fix proven findings before it reports.
[That include](../templates/brief-include.pstack.md) also sets the workers' other rules, such as limits on panels and nested subagents.
To change a tier, edit `config/crew-dispatch.json` in the primary home, then run `bin/fm-config-push.sh` to send it to live secondmate homes.
An edited file differs from the template, so later installer runs in the primary home report a conflict on it and exit 1.

### Agent types for use outside firstmate

[`agents/`](../agents) holds three Claude Code subagents, each pinned to a model and effort in its own frontmatter.
They are for your own Claude Code sessions outside firstmate, where you can ask for one by name:

| Type | Model, effort | Use |
| --- | --- | --- |
| `fm-planner` | opus, high | Read-only. Breaks a task into small, ordered, verifiable chunks, one PR each, and marks which are safety-critical. |
| `fm-builder` | sonnet, medium | Builds one routine chunk with poteto-mode's playbooks in a light form. |
| `fm-safety` | opus, high | Builds a safety-critical or security-sensitive chunk, with extra verification. |

To change a type's model or effort, edit its file under `agents/` in this clone and re-run the installer, which refreshes Windows copies.
`/setup-pstack` still sets poteto-mode's own per-role models, which is separate from these types.

## Update

- `git pull` updates every installed skill, because they are links into this clone.
- Run `bin/fm-install-skills.sh` again after a pull that adds new skills or agent types, or that adds or changes `templates/brief-include.pstack.md` or `docs/examples/crew-dispatch.pstack.json`. On Windows it also refreshes agent copies that a pull made stale, but never overwrites a file you edited.
  The installer does not remove an `fm-mechanic.md` left in `~/.claude/agents/` by an earlier install; that type is gone, so delete the file.
- `config/brief-include.md` and `config/crew-dispatch.json` are not refreshed like an agent copy. After a template changes, even an unedited older file is a conflict and the run exits 1. In the primary home, `--force` backs it up and installs the new text, and also replaces any other conflicting skill or agent file. It also replaces an edited `config/crew-dispatch.json`, moving it to `config/.pstack-backup-<time>/`, so re-apply custom tiers from there. To refresh only one config file, rename that file and run the installer without `--force`. For each secondmate home, refresh only the brief include: rename its old `config/brief-include.md`, then run the installer as in Install step 2, without `--force`.
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
In each home where you installed it, delete `config/brief-include.md`, or firstmate keeps appending it to new briefs. If you added your own rules to that file, remove only the pstack text.
Delete `config/crew-dispatch.json` in the primary home only, unless you have your own dispatch rules in it. Secondmate homes drop their inherited copy at the next config convergence.
