#!/usr/bin/env bash
# Package the finished work for hand-in at minute 60: checks CHOICES.md
# (present, at most 250 words), commits nothing, and writes a zip (git history
# included, caches and ignored files left out) next to this repo's README.
#
#   scripts/package.sh work/<name>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
proj="$(cd "${1:?usage: package.sh work/<name>}" && pwd)"
ws="$proj"; [ -d "$proj/workspace" ] && ws="$proj/workspace"
name="$(basename "$proj")"
warn=0

choices=""
for c in "$ws/CHOICES.md" "$proj/CHOICES.md"; do [ -f "$c" ] && choices="$c" && break; done
if [ -z "$choices" ]; then
  echo "WARN  CHOICES.md is missing (required deliverable)"; warn=1
else
  words="$(wc -w <"$choices")"
  if [ "$words" -gt 250 ]; then
    echo "WARN  CHOICES.md is $words words (limit 250)"; warn=1
  else
    echo "ok    CHOICES.md: $words/250 words"
  fi
  grep -qi 'TODO\|<fill' "$choices" && { echo "WARN  CHOICES.md still has TODO/<fill> placeholders"; warn=1; }
fi

if git -C "$ws" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  dirty="$(git -C "$ws" status --porcelain | wc -l)"
  echo "ok    git: $(git -C "$ws" rev-list --count HEAD) commits, $dirty uncommitted change(s) (uncommitted files are still included)"
  base="$(git -C "$ws" rev-list --max-parents=0 HEAD | tail -1)"
  echo "      changed since baseline: $(git -C "$ws" diff --stat "$base" | tail -1)"
fi

out="$ROOT/submission-$name-$(date +%H%M).zip"
rm -f "$out"
(
  cd "$(dirname "$proj")"
  if git -C "$ws" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
     && [ "$(git -C "$ws" rev-parse --show-toplevel)" != "$ROOT" ]; then
    top="$(git -C "$ws" rev-parse --show-toplevel)"
    rel="${top#"$(pwd)"/}"
    {
      # tracked + untracked-but-not-ignored files of the repo, plus its .git
      git -C "$top" ls-files -co --exclude-standard | sed "s#^#$rel/#"
      find "$rel/.git" -type f
      # anything in the project folder outside the repo (e.g. the brief)
      [ "$top" != "$proj" ] && find "$name" -path "$rel" -prune -o -type f -print
    } | sort -u | zip -q "$out" -@
  else
    zip -qr "$out" "$name" -x '*/__pycache__/*' '*/.pytest_cache/*' '*/.ruff_cache/*' '*/node_modules/*' '*/.venv/*' '*/var/*'
  fi
)
echo "ok    $(du -h "$out" | cut -f1)  ${out#"$ROOT"/}"
[ "$warn" = 0 ] || echo "      (packaged anyway - fix the WARN lines if there is time)"
