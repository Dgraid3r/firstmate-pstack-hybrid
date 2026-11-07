#!/usr/bin/env bash
# Link this repo's public skills (skills/<name>/) into a user-level skills
# directory, so every Claude Code session on the machine can use them: the
# primary firstmate, the workers it launches, and sessions outside firstmate.
# Links rather than copies, so a `git pull` of this repo updates every
# installed skill with no reinstall.
#
# For each skills/<name>/ that has a SKILL.md:
#   - missing target          -> link it
#   - target already links here -> leave it (re-runs are no-ops)
#   - anything else at target  -> leave it and report a conflict; with --force,
#     move it to <dest>/.pstack-backup-<epoch>/<name> first, then link
# A conflict never blocks the other skills. Exit status is 0 when every skill
# is linked, 1 when any conflict or error remains, 2 on bad usage.
#
# Links are symlinks on macOS and Linux. Under Git Bash on Windows, `ln -s`
# silently copies, so directory junctions (mklink /J) are used instead; they
# need no administrator rights or Developer Mode.
#
# On Windows it also repairs this repo's own .claude/skills -> ../.agents/skills
# link, which a clone without symlink support checks out as a plain text file,
# hiding firstmate's internal skills from Claude Code. The file becomes a
# junction, marked skip-worktree and excluded locally so git status stays clean.
#
# This is a manual setup utility, not a supervision script, so it does not
# call fm-guard.sh and never touches firstmate state.
#
# Usage: fm-install-skills.sh [--dest DIR] [--force] [--dry-run]
#   --dest DIR  install into DIR (default: ~/.claude/skills)
#   --force     back up and replace entries that are not links to this repo
#   --dry-run   print what would change and change nothing
set -euo pipefail

usage() { sed -n '/^# Usage:/,/^set /p' "$0" | sed '$d; s/^# \{0,1\}//'; }

DEST="$HOME/.claude/skills"
FORCE=0
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dest) [ $# -ge 2 ] || { usage >&2; exit 2; }; DEST=$2; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

SRC_ROOT=$(cd "$(dirname "$0")/../skills" && pwd -P)

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;;
  *) WINDOWS=0 ;;
esac

# One spelling per path, so MSYS mount aliases (/tmp vs /c/Users/...) compare equal.
norm() {
  if [ "$WINDOWS" = 1 ]; then cygpath -w "$1" | tr '[:upper:]' '[:lower:]'; else printf '%s\n' "$1"; fi
}

# The normalized real path a link resolves to, or empty when the entry is not a link.
link_target() {
  local entry=$1
  if [ "$WINDOWS" = 1 ]; then
    [ -d "$entry" ] || return 0
    local real logical
    real=$(norm "$(cd "$entry" && pwd -P)")
    logical=$(norm "$(cd "$(dirname "$entry")" && pwd -P)/$(basename "$entry")")
    [ "$real" != "$logical" ] && printf '%s\n' "$real"
    return 0
  fi
  [ -L "$entry" ] && (cd "$entry" 2>/dev/null && pwd -P)
  return 0
}

make_link() {
  local src=$1 dst=$2
  if [ "$WINDOWS" = 1 ]; then
    MSYS2_ARG_CONV_EXCL="*" cmd /c mklink /J "$(cygpath -w "$dst")" "$(cygpath -w "$src")" >/dev/null
  else
    ln -s "$src" "$dst"
  fi
}

run() { if [ "$DRY" = 1 ]; then echo "  would: $*"; else "$@"; fi; }

REPO=$(cd "$SRC_ROOT/.." && pwd -P)
INTERNAL="$REPO/.claude/skills"
if [ "$WINDOWS" = 1 ] && [ -f "$INTERNAL" ] && [ "$(cat "$INTERNAL")" = "../.agents/skills" ]; then
  echo "repair   .claude/skills (link to .agents/skills)"
  run rm "$INTERNAL"
  run make_link "$REPO/.agents/skills" "$INTERNAL"
  run git -C "$REPO" update-index --skip-worktree .claude/skills
  if ! grep -qx '.claude/skills/' "$REPO/.git/info/exclude" 2>/dev/null; then
    if [ "$DRY" = 1 ]; then echo "  would: exclude .claude/skills/ locally"; else echo '.claude/skills/' >> "$REPO/.git/info/exclude"; fi
  fi
fi

[ "$DRY" = 1 ] || mkdir -p "$DEST"
BACKUP="$DEST/.pstack-backup-$(date +%s)"
linked=0 kept=0 conflicts=0

for dir in "$SRC_ROOT"/*/; do
  name=$(basename "$dir")
  [ -f "$dir/SKILL.md" ] || continue
  src="$SRC_ROOT/$name"
  dst="$DEST/$name"

  if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "link     $name"
    run make_link "$src" "$dst"
    linked=$((linked + 1))
    continue
  fi

  if [ "$(link_target "$dst")" = "$(norm "$src")" ]; then
    kept=$((kept + 1))
    continue
  fi

  if [ "$FORCE" = 1 ]; then
    echo "replace  $name (old copy kept in $BACKUP/$name)"
    run mkdir -p "$BACKUP"
    run mv "$dst" "$BACKUP/$name"
    run make_link "$src" "$dst"
    linked=$((linked + 1))
  else
    echo "conflict $name: $dst exists and is not a link to this repo (use --force to back it up and replace it)"
    conflicts=$((conflicts + 1))
  fi
done

echo "linked $linked, already linked $kept, conflicts $conflicts, into $DEST"
[ "$conflicts" = 0 ]
