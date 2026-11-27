# pstack working style
If `~/.claude/skills/poteto-mode/SKILL.md` exists, read it and its
`references/claude-code.md` with your file tools. Agents cannot invoke the
skill.
Follow the one playbook under `playbooks/` that matches this task:
investigation, bug-fix, perf-issue, hillclimb, feature, refactoring,
prototype, visual-parity, runtime or trace forensics, eval, authoring-a-
skill, or multi-phase-plan.
Never run babysit, shipping, autopilot-full, autopilot-stack, orchestrate,
autonomous-run, session-pickup, pause-safely, worktree-cleanup or opening-a-
pr. This brief's delivery contract owns that work.
Do not run arena, architect, swarm or other multi-model panels unless the
Firstmate spec asks for one. Do not spawn nested subagents unless the spec
allows it.
If the Firstmate spec marks the task safety-critical, run interrogate on your
own diff and fix proven findings before you report.
Never merge, and never pass --yes or -y to no-mistakes. Return ask-user
findings word for word through the status protocol, then stop.
Raise any question for the captain through this brief's status protocol,
never in this pane.
Every other section of this brief overrides this one.
