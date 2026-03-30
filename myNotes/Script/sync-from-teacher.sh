#!/usr/bin/env bash
set -Eeuo pipefail

TEACHER_URL="https://gitflic.ru/project/rurewa/mfua.git"
TEACHER_BRANCH="master"
TARGET_BRANCH="main"
REMOTE_NAME="teacher"

DELETE_MISSING=0

usage() {
  cat <<'EOF'
Usage:
  ./sync-from-teacher.sh [--delete-missing]

Options:
  --delete-missing   also remove tracked files from your repo if they do not exist in teacher's repo
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-missing)
      DELETE_MISSING=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

command -v git >/dev/null 2>&1 || {
  echo "git is not installed or not in PATH." >&2
  exit 1
}

# Find the directory where this script itself is stored
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Find repo root based on the script location, not current shell location
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "This script must be placed somewhere inside your local git repository." >&2
  exit 1
}

cd "$REPO_ROOT"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
  echo "You are on '$CURRENT_BRANCH'. Switch to '$TARGET_BRANCH' first." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit/stash/remove changes first." >&2
  exit 1
fi

BACKUP_BRANCH="backup-before-teacher-sync-$(date +%Y%m%d-%H%M%S)"
git branch "$BACKUP_BRANCH"
echo "Created backup branch: $BACKUP_BRANCH"

if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  git remote set-url "$REMOTE_NAME" "$TEACHER_URL"
else
  git remote add "$REMOTE_NAME" "$TEACHER_URL"
fi

echo "Fetching $REMOTE_NAME/$TEACHER_BRANCH ..."
git fetch --prune "$REMOTE_NAME" "$TEACHER_BRANCH"

REMOTE_REF="$REMOTE_NAME/$TEACHER_BRANCH"

echo "Copying tracked files from $REMOTE_REF into $TARGET_BRANCH ..."
git checkout "$REMOTE_REF" -- .

if [[ "$DELETE_MISSING" -eq 1 ]]; then
  echo "Removing tracked files that do not exist in $REMOTE_REF ..."

  MINE_LIST="$(mktemp)"
  TEACHER_LIST="$(mktemp)"
  trap 'rm -f "$MINE_LIST" "$TEACHER_LIST"' EXIT

  git ls-files | LC_ALL=C sort > "$MINE_LIST"
  git ls-tree -r --name-only "$REMOTE_REF" | LC_ALL=C sort > "$TEACHER_LIST"

  mapfile -t TO_DELETE < <(comm -23 "$MINE_LIST" "$TEACHER_LIST")

  if ((${#TO_DELETE[@]} > 0)); then
    git rm -f -- "${TO_DELETE[@]}"
  else
    echo "No tracked files to delete."
  fi
fi

git add -A

if git diff --cached --quiet; then
  echo "No changes to commit."
  echo "Backup branch kept at: $BACKUP_BRANCH"
  exit 0
fi

git commit -m "Sync files from teacher repo (${TEACHER_BRANCH})"
git push origin "$TARGET_BRANCH"

echo "Done."
echo "Backup branch: $BACKUP_BRANCH"