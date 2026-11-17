#!/usr/bin/env bash
# Take the interview project as received (zip, folder or git URL), put it in
# work/<name>, snapshot it in git so every change is diffable, and make its
# Docker base images work in this session. Does NOT run `make setup`: do that
# next, before the 60-minute clock starts.
#
#   scripts/start-project.sh ~/uploads/project.zip
#   scripts/start-project.sh examples/02-interview_projects/software-engineer/005-blocked-despite-waiver practice-005
#   scripts/start-project.sh https://github.com/org/repo
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
src="${1:?usage: start-project.sh <zip | folder | git-url> [name]}"
name="${2:-}"

if [ -z "$name" ]; then
  name="$(basename "${src%/}")"; name="${name%.zip}"; name="${name%.git}"
fi
dest="$ROOT/work/$name"
[ -e "$dest" ] && { echo "work/$name already exists - pass another name as 2nd argument" >&2; exit 1; }
mkdir -p "$ROOT/work"

case "$src" in
  http://*|https://*|git@*)
    GIT_LFS_SKIP_SMUDGE=1 git clone -q "$src" "$dest" ;;
  *.zip)
    mkdir -p "$dest"
    unzip -q "$src" -d "$dest"
    # A zip that wraps everything in one top-level folder: lift it up.
    entries=("$dest"/*)
    if [ "$(ls -A "$dest" | grep -cv '^__MACOSX$')" = 1 ] && [ -d "${entries[0]}" ]; then
      inner="${entries[0]}"
      mv "$inner" "$dest.tmp" && rm -rf "$dest" && mv "$dest.tmp" "$dest"
    fi ;;
  *)
    [ -d "$src" ] || { echo "not a zip, folder or git URL: $src" >&2; exit 1; }
    cp -a "$src" "$dest"
    rm -rf "$dest/.git" 2>/dev/null || true ;;
esac

# The code lives in workspace/ in Ostorlab's layout; otherwise at the top.
ws="$dest"
[ -d "$dest/workspace" ] && ws="$dest/workspace"

# Baseline commit so `git diff` shows exactly what we changed.
if ! git -C "$ws" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
   || [ "$(git -C "$ws" rev-parse --show-toplevel)" = "$ROOT" ]; then
  git -C "$ws" init -q -b main
  git -C "$ws" add -A
  git -C "$ws" -c user.name="baseline" -c user.email="baseline@localhost" \
      commit -q -m "Baseline: project as received"
  echo "git: initialised in ${ws#"$ROOT"/} with a baseline commit"
else
  echo "git: existing repository kept (HEAD $(git -C "$ws" log -1 --format='%h %s' | cut -c1-60))"
fi

# Docker base images: pull and trust the session proxy CA under the same tag.
mapfile -t images < <(
  {
    find "$ws" -maxdepth 3 -iname 'Dockerfile*' -not -path '*/.git/*' -exec awk 'toupper($1)=="FROM" && $2 !~ /^\$/ {print $2}' {} + 2>/dev/null
    find "$ws" -maxdepth 2 \( -name 'docker-compose*.y*ml' -o -name 'compose*.y*ml' \) -exec grep -hoE '^\s*image: *[^ #]+' {} + 2>/dev/null \
      | awk '{print $2}' | tr -d "\"'" | grep -vE ':(dev|local|latest-dev)$' || true
  } | grep -v '^scratch$' | sort -u
)
if [ "${#images[@]}" -gt 0 ]; then
  echo "docker images referenced: ${images[*]}"
  if docker info >/dev/null 2>&1; then
    for img in "${images[@]}"; do
      "$ROOT/scripts/trust-image.sh" "$img" || echo "  WARN: could not prepare $img (a locally built image name is fine)"
    done
  else
    echo "  WARN: docker daemon is not running - run scripts/bootstrap.sh"
  fi
else
  echo "no Dockerfile/compose images found (host-only project?)"
fi

echo
echo "PROJECT   ${dest#"$ROOT"/}"
echo "WORKSPACE ${ws#"$ROOT"/}"
for readme in "$dest/README.md" "$ws/README.md"; do
  [ -f "$readme" ] && echo "BRIEF     ${readme#"$ROOT"/}  ($(wc -w <"$readme") words): $(head -1 "$readme")"
done
if [ -d "$ws/docs/requests" ]; then
  echo "TICKETS   (largest first - the main one is usually the longest):"
  (cd "$ws/docs/requests" && wc -w *.md 2>/dev/null | grep -v ' total$' | sort -rn | head -8 | sed 's/^/          /')
fi
if [ -f "$ws/Makefile" ]; then
  echo "MAKE      $(grep -oE '^[a-z][a-z-]*:' "$ws/Makefile" | tr -d ':' | sort -u | tr '\n' ' ')"
fi
echo
echo "Next: read the brief's Setup line, then run it (usually: cd ${ws#"$ROOT"/} && make setup && make test)"
