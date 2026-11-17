#!/usr/bin/env bash
# Dry-run `make setup` + `make test` on every software-engineer example from
# Ostorlab/interview-project-examples, to prove this session can run their
# kind of project (and to warm the Docker layer cache). Stacks are torn down
# afterwards; pass KEEP=1 to leave the last one running.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="$ROOT/examples/02-interview_projects/software-engineer"
[ -d "$BASE" ] || { echo "run scripts/bootstrap.sh first (no examples/ clone)"; exit 1; }
only="${1:-}"
summary=()
for dir in "$BASE"/*/; do
  name="$(basename "$dir")"
  [ -n "$only" ] && [[ "$name" != *"$only"* ]] && continue
  ws="$dir/workspace"
  echo "=================== $name"
  export COMPOSE_PROJECT_NAME="verify-${name%%-*}"
  start=$SECONDS
  if [ -f "$ws/Dockerfile" ]; then
    "$ROOT/scripts/trust-image.sh" $(awk 'toupper($1)=="FROM"{print $2}' "$ws/Dockerfile" | sort -u)
    grep -hoE 'image: *[^ ]+' "$ws/docker-compose.yml" | awk '{print $2}' | grep -v ':dev$' | sort -u \
      | xargs -r "$ROOT/scripts/trust-image.sh"
  fi
  if (cd "$ws" && make setup >"/tmp/verify-$name-setup.log" 2>&1); then s=ok; else s=FAIL; fi
  t_setup=$((SECONDS - start)); start=$SECONDS
  if (cd "$ws" && make test >"/tmp/verify-$name-test.log" 2>&1); then t=ok; else t=FAIL; fi
  t_test=$((SECONDS - start))
  tail -1 "/tmp/verify-$name-test.log"
  summary+=("$(printf '%-34s setup=%-4s (%3ss)  test=%-4s (%3ss)  %s' "$name" "$s" "$t_setup" "$t" "$t_test" "$(tail -1 "/tmp/verify-$name-test.log" | cut -c1-40)")")
  if [ -z "${KEEP:-}" ] && [ -f "$ws/docker-compose.yml" ]; then
    (cd "$ws" && make clean >/dev/null 2>&1)
  fi
  (cd "$ws" && git clean -fdxq . 2>/dev/null)   # drop var/, caches the dry run created
done
echo; echo "SUMMARY"; printf '%s\n' "${summary[@]}"
printf '%s\n' "${summary[@]}" | grep -q FAIL && exit 1 || exit 0
