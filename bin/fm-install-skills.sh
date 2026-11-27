#!/usr/bin/env bash
# Link this repo's public skills (skills/<name>/) into a user-level skills
# directory, so every Claude Code session on the machine can use them: the
# primary firstmate, the workers it launches, and sessions outside firstmate.
# Links rather than copies, so a `git pull` of this repo updates every
# installed skill with no reinstall. It also installs the worker agent types
# (agents/*.md) into a user-level agents directory, described below.
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
# Agent types (agents/<name>.md) are single files, so the same rules apply per
# file, with these differences:
#   - Unix: a file symlink, so `git pull` updates it with no reinstall.
#   - Windows (Git Bash) or --copy: a copy. Junctions cannot link files, and a
#     hard link would not survive `git pull`, which replaces files instead of
#     rewriting them in place. A re-run refreshes a copy that went stale. The
#     checksums of what this script installed are kept in
#     <agents-dest>/.pstack-agents.manifest, so a stale copy of an earlier
#     version (still matching the manifest) is refreshed, while a file the
#     user edited or wrote is a conflict.
#   - A pre-existing regular file with the same content as ours counts as
#     already installed: on Unix it is replaced by the symlink, as a copy it
#     is recorded in the manifest. No backup is needed, nothing is lost.
#   - A pre-existing file with different content is a conflict; --force moves
#     it to <agents-dest>/.pstack-backup-<epoch>/ first.
#
# It also copies templates/brief-include.pstack.md to <home>/config/brief-include.md
# when that file is missing (see "brief include" below); the same conflict and
# --force rules apply.
#
# This is a manual setup utility, not a supervision script, so it does not
# call fm-guard.sh and never touches firstmate state.
#
# Usage: fm-install-skills.sh [--dest DIR] [--agents-dest DIR] [--copy] [--force] [--dry-run]
#   --dest DIR         install skills into DIR (default: ~/.claude/skills)
#   --agents-dest DIR  install agent types into DIR (default: ~/.claude/agents)
#   --copy             install agent types as copies, not symlinks (default on Windows)
#   --force            back up and replace conflicting skills, agent types, and brief include
#   --dry-run          print what would change and change nothing
set -euo pipefail

usage() { sed -n '/^# Usage:/,/^set /p' "$0" | sed '$d; s/^# \{0,1\}//'; }

DEST="$HOME/.claude/skills"
ADEST="$HOME/.claude/agents"
COPY=0
FORCE=0
DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dest) [ $# -ge 2 ] || { usage >&2; exit 2; }; DEST=$2; shift 2 ;;
    --agents-dest) [ $# -ge 2 ] || { usage >&2; exit 2; }; ADEST=$2; shift 2 ;;
    --copy) COPY=1; shift ;;
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
[ "$WINDOWS" = 1 ] && COPY=1

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
  # --git-path resolves info/exclude when .git is a pointer file (linked worktree).
  exclude=$(git -C "$REPO" rev-parse --git-path info/exclude)
  case $exclude in /* | [A-Za-z]:*) ;; *) exclude="$REPO/$exclude" ;; esac
  if ! grep -qx '.claude/skills/' "$exclude" 2>/dev/null; then
    if [ "$DRY" = 1 ]; then echo "  would: exclude .claude/skills/ locally"; else mkdir -p "$(dirname "$exclude")" && echo '.claude/skills/' >> "$exclude"; fi
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

# --- agent types -------------------------------------------------------------

AGENTS_SRC="$REPO/agents"
MANIFEST="$ADEST/.pstack-agents.manifest"
ABACKUP="$ADEST/.pstack-backup-$(date +%s)"
alinked=0 akept=0 aconflicts=0

sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# manifest_get <name> -> the checksum recorded when this script installed <name>.
manifest_get() { if [ -f "$MANIFEST" ]; then awk -v n="$1" '$2 == n { print $1 }' "$MANIFEST"; fi; }

manifest_set() {  # <name> <checksum>
  [ "$DRY" = 1 ] && return 0
  local tmp="$MANIFEST.tmp"
  { if [ -f "$MANIFEST" ]; then awk -v n="$1" '$2 != n' "$MANIFEST"; fi; printf '%s %s\n' "$2" "$1"; } > "$tmp"
  mv "$tmp" "$MANIFEST"
}

place_agent() {  # <name> <source> <destination>
  if [ "$COPY" = 1 ]; then
    run cp -f "$2" "$3"
    [ "$DRY" = 1 ] || manifest_set "$1" "$(sha "$2")"
  else
    run ln -s "$2" "$3"
  fi
}

if [ -d "$AGENTS_SRC" ]; then
  [ "$DRY" = 1 ] || mkdir -p "$ADEST"
  for src in "$AGENTS_SRC"/*.md; do
    [ -f "$src" ] || continue
    name=$(basename "$src")
    dst="$ADEST/$name"

    if [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
      echo "link     agent $name"
      place_agent "$name" "$src" "$dst"
      alinked=$((alinked + 1))
      continue
    fi

    if [ -L "$dst" ]; then
      if [ "$COPY" = 0 ] && [ "$(readlink "$dst")" = "$src" ]; then
        akept=$((akept + 1))
        continue
      fi
    elif [ -f "$dst" ]; then
      have=$(sha "$dst")
      if [ "$have" = "$(sha "$src")" ]; then
        if [ "$COPY" = 1 ]; then
          [ "$(manifest_get "$name")" = "$have" ] || { [ "$DRY" = 1 ] || manifest_set "$name" "$have"; }
          akept=$((akept + 1))
        else
          echo "link     agent $name (identical copy replaced by a link)"
          run rm -f "$dst"
          place_agent "$name" "$src" "$dst"
          alinked=$((alinked + 1))
        fi
        continue
      fi
      if [ "$COPY" = 1 ] && [ "$(manifest_get "$name")" = "$have" ]; then
        echo "refresh  agent $name (stale copy)"
        place_agent "$name" "$src" "$dst"
        alinked=$((alinked + 1))
        continue
      fi
    fi

    if [ "$FORCE" = 1 ]; then
      echo "replace  agent $name (old file kept in $ABACKUP/$name)"
      run mkdir -p "$ABACKUP"
      run mv "$dst" "$ABACKUP/$name"
      place_agent "$name" "$src" "$dst"
      alinked=$((alinked + 1))
    else
      echo "conflict agent $name: $dst exists and is not this repo's file (use --force to back it up and replace it)"
      aconflicts=$((aconflicts + 1))
    fi
  done
  echo "agents: installed $alinked, already installed $akept, conflicts $aconflicts, into $ADEST"
fi

# --- brief include -----------------------------------------------------------
# templates/brief-include.pstack.md becomes <home>/config/brief-include.md, the
# file fm-brief.sh appends to every ship and scout brief. The home is resolved
# the way fm-brief.sh does: FM_CONFIG_OVERRIDE, else $FM_HOME/config, else this
# repo's config/. The file is gitignored and per home, so a secondmate home needs
# its own run. An existing file is never overwritten; one that differs is a
# conflict, and --force backs it up first.
INC_SRC="$REPO/templates/brief-include.pstack.md"
bconflicts=0
CONFIG_DIR="${FM_CONFIG_OVERRIDE:-${FM_HOME:-$REPO}/config}"
INC_DST="$CONFIG_DIR/brief-include.md"
place_include() {
  run mkdir -p "$CONFIG_DIR"
  run cp -f "$INC_SRC" "$INC_DST"
}
if [ ! -e "$INC_DST" ] && [ ! -L "$INC_DST" ]; then
  echo "install  brief-include.md into $CONFIG_DIR"
  place_include
elif [ -f "$INC_DST" ] && [ ! -L "$INC_DST" ] && [ "$(sha "$INC_DST")" = "$(sha "$INC_SRC")" ]; then
  :
elif [ "$FORCE" = 1 ]; then
  IBACKUP="$CONFIG_DIR/.pstack-backup-$(date +%s)"
  echo "replace  brief-include.md (old file kept in $IBACKUP/brief-include.md)"
  run mkdir -p "$IBACKUP"
  run mv "$INC_DST" "$IBACKUP/brief-include.md"
  place_include
else
  echo "conflict brief-include.md: $INC_DST exists and differs from templates/brief-include.pstack.md (use --force to back it up and replace it)"
  bconflicts=1
fi

[ "$conflicts" = 0 ] && [ "$aconflicts" = 0 ] && [ "$bconflicts" = 0 ]
