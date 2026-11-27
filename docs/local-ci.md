# Running CI locally

This fork keeps GitHub Actions disabled in the repository settings, so the workflows in `.github/workflows/` match upstream and never run here.
The lint and portable behavior checks run locally in Docker instead, through the services in [`docker-compose.ci.yml`](../docker-compose.ci.yml).
The `PR must be raised via no-mistakes` rule is satisfied by delivering through no-mistakes, which is how every change here is raised.

Run the checks from the repository root.
The `git --exec-path=docker/ci fm-ci` form is the same string in PowerShell, cmd, bash, and zsh, and it also works from a linked git worktree:

```sh
git --exec-path=docker/ci fm-ci lint
git --exec-path=docker/ci fm-ci fast
git --exec-path=docker/ci fm-ci test-changed
git --exec-path=docker/ci fm-ci test
```

- `lint` runs `bin/fm-lint.sh` with the pinned ShellCheck and actionlint, the Pi type check, and the `fast` checks.
- `fast` runs the test coverage guard (`bin/fm-test-run.sh --check-coverage`) and the repo invariants (the `CLAUDE.md` and `.claude/skills` pointers, and no tracked personal fleet paths) in seconds.
  These are the `Test coverage guard` and `Repo invariants` jobs of upstream's `ci.yml`.
- `test-changed` runs `bin/fm-test-run.sh --changed` against `origin/main`; this is what the no-mistakes test step runs.
- `test` runs every portable lane CI shards across runners, back to back; run it before merging a large change.
- `.no-mistakes.yaml` runs the first and third commands as the gate's lint and test steps.
- The repository is mounted read-only and copied inside the container, so nothing is written to your checkout.
- The Herdr, herdr-core, and stock macOS lanes are not in Docker and are not run in this fork while GitHub Actions is disabled.
  Anyone who needs them runs them on a machine that has those tools.
- `docker compose -f docker-compose.ci.yml run --rm --build <service>` also works in a normal clone.
  In a linked git worktree `.git` is a pointer file, so that form needs `FM_CI_GIT_COMMON` set to the absolute `git rev-parse --path-format=absolute --git-common-dir`; the launcher above does this for you.
  `FM_CI_TESTS="tests/a.test.sh tests/b.test.sh"` runs a fixed list instead, and `FM_CI_JOBS` bounds parallelism.
