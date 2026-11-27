#!/usr/bin/env bash
# fm-ci-entrypoint - run one local CI mode inside the docker-compose.ci.yml image.
#
# FM_CI_LINT_FULL=1 makes lint cover the whole canonical set like GitHub CI.
# Modes: lint | fast | test | test-changed | test-lane <lane> | shell
# `lint` also runs the `fast` checks, the ones the "Test coverage guard" and
# "Repo invariants" jobs of .github/workflows/ci.yml run.
# The checkout is mounted read-only at /src. This script copies it to /work and
# runs there, so nothing is ever written into the checkout. If the checkout's git
# metadata is reachable (a normal clone, or a worktree with FM_CI_GIT_COMMON
# mounted at /gitroot) /work gets HEAD and origin/* refs through alternates, so
# --changed and git ls-files behave as on the host. Otherwise /work is a
# one-commit snapshot and only modes that need no base ref work.
set -eu

SRC=/src
WORK=/work
mode=${1:-}
[ $# -eq 0 ] || shift

die() { printf 'fm-ci: %s\n' "$*" >&2; exit 2; }

[ -d "$SRC/bin" ] || die "the repository is not mounted at $SRC; run docker compose from the repository root"

# --- 1. working-tree copy (never the host .git) -------------------------------
mkdir -p "$WORK"
find "$WORK" -mindepth 1 -delete
tar -C "$SRC" --exclude=./.git --exclude=./node_modules --exclude=./.no-mistakes -cf - . | tar -C "$WORK" -xf -
cd "$WORK"

# --- 2. git metadata ----------------------------------------------------------
git config --global --add safe.directory '*'
git config --global user.name fm-ci
git config --global user.email fm-ci@example.invalid
git config --global init.defaultBranch main
common=
if [ -d "$SRC/.git/objects" ]; then
  common=$SRC/.git
elif [ -d /gitroot/objects ]; then
  common=/gitroot
fi
git init -q "$WORK"
base_available=0
if [ -n "$common" ]; then
  if [ -d "$SRC/.git" ]; then
    gitdir=$SRC/.git
  else
    name=$(sed -n 's/^gitdir: //p' "$SRC/.git" | head -n1)
    name=$(printf '%s' "$name" | tr '\\' '/')
    name=${name%/}
    name=${name##*/}
    gitdir=$common/worktrees/$name
  fi
  head=$(git --git-dir="$gitdir" rev-parse --verify -q HEAD || true)
  if [ -n "$head" ]; then
    printf '%s\n' "$common/objects" >"$WORK/.git/objects/info/alternates"
    git --git-dir="$common" for-each-ref --format='%(objectname) %(refname)' refs/remotes/origin \
      | while read -r sha ref; do git update-ref "$ref" "$sha"; done
    # Never name this branch main: fm-lint.sh treats main as "lint everything".
    git symbolic-ref HEAD refs/heads/fm-ci
    git update-ref refs/heads/fm-ci "$head"
    git read-tree HEAD
    if git rev-parse --verify -q refs/remotes/origin/main >/dev/null; then base_available=1; fi
  fi
fi
if [ -z "$(git rev-parse --verify -q HEAD || true)" ]; then
  git add -A >/dev/null 2>&1
  git commit -q -m "fm-ci snapshot" >/dev/null
fi
# A Windows checkout (core.autocrlf) holds CRLF copies of files the index stores
# as LF, which both breaks Linux fixtures and makes every file look changed.
git ls-files --eol | awk '$1 == "i/lf" && $2 == "w/crlf" { sub(/^[^\t]*\t/, ""); print }' \
  | while IFS= read -r p; do sed -i 's/\r$//' "$p"; done
# A Windows bind mount reports every file with one mode; restore the index modes
# so scripts are executable exactly where the repository says and nowhere else.
git ls-files -s | awk -F'\t' '{ split($1, a, " "); if (a[1] == "100755") print $2 }' | xargs -r -d '\n' chmod 755
git ls-files -s | awk -F'\t' '{ split($1, a, " "); if (a[1] == "100644") print $2 }' | xargs -r -d '\n' chmod 644
# A Windows checkout keeps symlinks as small text files; restore them as the
# index records them so symlink-dependent checks see Linux semantics.
git ls-files -s | awk '$1 == "120000" { sub(/^[^\t]*\t/, ""); print }' | while IFS= read -r p; do
  if [ -f "$p" ] && [ ! -L "$p" ]; then
    target=$(cat "$p")
    rm -f "$p"
    ln -s "$target" "$p"
  fi
done

# --- 3. modes -----------------------------------------------------------------
jobs=${FM_CI_JOBS:-$(nproc)}
timing_dir=${FM_CI_TIMING_DIR:-/tmp/fm-test}
mkdir -p "$timing_dir"

run_lane() {
  printf '\n=== lane %s ===\n' "$1"
  bash bin/fm-test-run.sh --lane "$1" \
    --fail-on-gate-skip 'Pi extension typecheck prerequisite not found' \
    --json "$timing_dir/fm-test-timing-$1.json"
}

run_fast() {
  printf '\n=== fast checks (coverage guard, repo invariants) ===\n'
  bash bin/fm-test-run.sh --check-coverage
  # Mirrors the "Repo invariants" job of .github/workflows/ci.yml.
  [ ! -L CLAUDE.md ] || die "CLAUDE.md must be a real @AGENTS.md pointer file, not a symlink"
  printf '%s\n' \
    '<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->' \
    '@AGENTS.md' >/tmp/claude-pointer
  cmp -s CLAUDE.md /tmp/claude-pointer || die "CLAUDE.md must be the canonical @AGENTS.md pointer"
  [ "$(readlink .claude/skills)" = "../.agents/skills" ] || die ".claude/skills must be a symlink to ../.agents/skills"
  tracked=$(git ls-files -- data state config projects .no-mistakes)
  [ -z "$tracked" ] || die "Personal fleet paths are tracked in git: $tracked"
}

case "$mode" in
  fast)
    run_fast
    ;;
  lint)
    # fm-lint.sh accepts 1 or 2 workers.
    if [ "$jobs" -ge 2 ]; then export FM_LINT_JOBS=2; else export FM_LINT_JOBS=1; fi
    if [ "${FM_CI_LINT_FULL:-}" = 1 ]; then
      # CI parity: the whole canonical set, as GitHub's lint partitions run it.
      CI=true bash bin/fm-lint.sh
    else
      # Same default as the no-mistakes gate: files changed since origin/main.
      bash bin/fm-lint.sh
    fi
    bash tests/fm-pi-primary-types.test.sh
    run_fast
    ;;
  test)
    # Every portable lane GitHub CI shards across runners, run back to back.
    # The Herdr, herdr-core and macOS lanes are not included (docs/local-ci.md).
    lanes=$(bash bin/fm-test-run.sh --list-lanes | grep -E '^portable-(parallel-[0-9]+|serial-[0-9]+of[0-9]+)$' || true)
    [ -n "$lanes" ] || die "the runner listed no portable lanes"
    failed=
    for lane in $lanes; do
      run_lane "$lane" || failed="$failed $lane"
    done
    [ -z "$failed" ] || { printf 'fm-ci: failed lanes:%s\n' "$failed" >&2; exit 1; }
    ;;
  test-lane)
    [ $# -ge 1 ] || die "usage: test-lane <lane>"
    run_lane "$1"
    ;;
  test-changed)
    if [ -n "${FM_CI_TESTS:-}" ]; then
      # shellcheck disable=SC2086
      exec bash bin/fm-test-run.sh $FM_CI_TESTS
    fi
    [ "$base_available" = 1 ] \
      || die "no origin/main in the mounted git metadata. In a git worktree set FM_CI_GIT_COMMON to the common git dir (docs/local-ci.md), or list tests in FM_CI_TESTS."
    exec bash bin/fm-test-run.sh --changed --base "${FM_CI_BASE:-origin/main}"
    ;;
  shell)
    exec bash
    ;;
  *)
    die "unknown mode '$mode' (lint | fast | test | test-changed | test-lane <lane> | shell)"
    ;;
esac
