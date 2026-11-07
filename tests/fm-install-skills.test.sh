#!/usr/bin/env bash
# fm-install-skills.test.sh - bin/fm-install-skills.sh installs the worker agent
# types (agents/*.md) into a user-level agents directory with the same safety
# model as skills: --dry-run previews, a foreign file is a conflict, --force
# backs it up, and a re-run is a no-op. Runs against a throwaway copy of the
# installer and a tiny agents/ tree, so the real home directory is never touched.
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP=$(fm_test_tmproot fm-install-skills)
REPO="$TMP/repo"
mkdir -p "$REPO/bin" "$REPO/skills/demo" "$REPO/agents"
cp "$ROOT/bin/fm-install-skills.sh" "$REPO/bin/"
printf 'skill\n' > "$REPO/skills/demo/SKILL.md"
printf 'planner v1\n' > "$REPO/agents/fm-a.md"
printf 'builder v1\n' > "$REPO/agents/fm-b.md"

# Each case gets fresh destinations; install <mode> runs the installer in
# "link" (default symlinks, only where the host can make them) or "copy" mode.
fresh() { rm -rf "$TMP/skills" "$TMP/agents"; mkdir -p "$TMP/skills" "$TMP/agents"; }
install() {  # <mode> [args...]
  local mode=$1; shift
  local extra=()
  [ "$mode" = copy ] && extra=(--copy)
  bash "$REPO/bin/fm-install-skills.sh" --dest "$TMP/skills" --agents-dest "$TMP/agents" "${extra[@]}" "$@" 2>&1
}

# Symlink mode needs a host where `ln -s` really links (Git Bash on Windows copies).
LINKS=1
ln -s "$REPO/agents/fm-a.md" "$TMP/probe" 2>/dev/null && [ -L "$TMP/probe" ] || LINKS=0
rm -f "$TMP/probe"
MODES=copy
[ "$LINKS" = 1 ] && MODES="copy link"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) MODES=copy ;; esac

test_installs_and_is_idempotent() {
  local mode out
  for mode in $MODES; do
    fresh
    out=$(install "$mode")
    assert_contains "$out" "link     agent fm-a.md" "$mode: first run installs fm-a"
    assert_contains "$out" "installed 2, already installed 0, conflicts 0" "$mode: first run summary"
    assert_equals "planner v1" "$(cat "$TMP/agents/fm-a.md")" "$mode: installed content"
    [ "$mode" = link ] && { [ -L "$TMP/agents/fm-a.md" ] || fail "link mode did not symlink"; }
    out=$(install "$mode")
    assert_contains "$out" "installed 0, already installed 2, conflicts 0" "$mode: re-run is a no-op"
  done
  pass "installs agent types and re-running is a no-op"
}

test_dry_run_changes_nothing() {
  local mode out
  for mode in $MODES; do
    fresh
    out=$(install "$mode" --dry-run)
    assert_contains "$out" "link     agent fm-a.md" "$mode: dry run reports the install"
    assert_absent "$TMP/agents/fm-a.md" "$mode: dry run installed a file"
    assert_absent "$TMP/agents/.pstack-agents.manifest" "$mode: dry run wrote the manifest"
  done
  pass "--dry-run previews without installing"
}

test_conflict_then_force_backup() {
  local mode out code
  for mode in $MODES; do
    fresh
    printf 'mine\n' > "$TMP/agents/fm-a.md"
    code=0
    out=$(install "$mode") || code=$?
    expect_code 1 "$code" "$mode: conflict exit status"
    assert_contains "$out" "conflict agent fm-a.md" "$mode: conflict reported"
    assert_equals "mine" "$(cat "$TMP/agents/fm-a.md")" "$mode: conflicting file left alone"
    assert_contains "$out" "link     agent fm-b.md" "$mode: other agents still install"
    out=$(install "$mode" --force)
    assert_contains "$out" "replace  agent fm-a.md" "$mode: --force replaces"
    assert_equals "planner v1" "$(cat "$TMP/agents/fm-a.md")" "$mode: replaced content"
    assert_equals "mine" "$(cat "$TMP"/agents/.pstack-backup-*/fm-a.md)" "$mode: backup holds the old file"
  done
  pass "a foreign file is a conflict and --force backs it up"
}

test_identical_preexisting_copy_is_adopted() {
  local mode out
  for mode in $MODES; do
    fresh
    printf 'planner v1\n' > "$TMP/agents/fm-a.md"
    out=$(install "$mode")
    assert_not_contains "$out" "conflict agent" "$mode: identical file is not a conflict"
    [ "$mode" = link ] && { [ -L "$TMP/agents/fm-a.md" ] || fail "identical file not replaced by a link"; }
    out=$(install "$mode")
    assert_contains "$out" "already installed 2" "$mode: adopted file stays installed"
  done
  pass "an identical pre-existing file counts as installed"
}

test_stale_copy_refreshes_but_edited_copy_conflicts() {
  local out code
  fresh
  install copy >/dev/null
  printf 'planner v2\n' > "$REPO/agents/fm-a.md"
  out=$(install copy)
  assert_contains "$out" "refresh  agent fm-a.md" "stale copy is refreshed"
  assert_equals "planner v2" "$(cat "$TMP/agents/fm-a.md")" "refreshed content"
  printf 'my edit\n' > "$TMP/agents/fm-b.md"
  printf 'builder v2\n' > "$REPO/agents/fm-b.md"
  code=0
  out=$(install copy) || code=$?
  expect_code 1 "$code" "edited copy conflict status"
  assert_contains "$out" "conflict agent fm-b.md" "edited copy is a conflict"
  assert_equals "my edit" "$(cat "$TMP/agents/fm-b.md")" "edited copy left alone"
  pass "a stale copy refreshes and a user-edited copy is a conflict"
}

fm_test_run test_installs_and_is_idempotent test_dry_run_changes_nothing \
  test_conflict_then_force_backup test_identical_preexisting_copy_is_adopted \
  test_stale_copy_refreshes_but_edited_copy_conflicts
