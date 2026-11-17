#!/usr/bin/env bash
# Make a fresh Claude cloud session ready for an Ostorlab-style interview
# project. Idempotent: run it at the start of every session (takes ~1 minute
# on a fresh container, a few seconds afterwards).
#
#   scripts/bootstrap.sh
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLES_URL="https://github.com/Ostorlab/interview-project-examples"
# Base images used by every Docker-based example in the Ostorlab repo.
BASE_IMAGES=(python:3.12.7-slim postgres:16.4-alpine redis:7.4-alpine)
fail=0

echo "== 1/4 Docker daemon"
if ! docker info >/dev/null 2>&1; then
  if command -v dockerd >/dev/null 2>&1; then
    nohup dockerd >/var/log/dockerd.log 2>&1 &
    for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
  fi
fi
if docker info >/dev/null 2>&1; then
  echo "   ok: $(docker version -f '{{.Server.Version}}'), $(docker compose version --short 2>/dev/null | sed 's/^/compose /')"
else
  echo "   FAILED: docker daemon not reachable (see /var/log/dockerd.log)"; fail=1
fi

echo "== 2/4 Base images (pulled + session proxy CA trusted)"
if docker info >/dev/null 2>&1; then
  "$ROOT/scripts/trust-image.sh" "${BASE_IMAGES[@]}" | sed 's/^/   /' || fail=1
fi

echo "== 3/4 Ostorlab example projects"
if [ -d "$ROOT/examples/.git" ]; then
  echo "   ok: examples/ present ($(git -C "$ROOT/examples" log -1 --format=%h))"
elif GIT_LFS_SKIP_SMUDGE=1 git clone -q --depth 1 "$EXAMPLES_URL" "$ROOT/examples"; then
  echo "   ok: cloned into examples/"
else
  echo "   WARN: could not clone $EXAMPLES_URL (not needed for the interview itself)"
fi

echo "== 4/4 Toolchain"
if ! command -v sqlite3 >/dev/null 2>&1; then   # CLI for SQLite-based projects
  { apt-get update -q && apt-get install -y -q sqlite3; } >/dev/null 2>&1 || true
fi
for tool in python3 python3.12 python3.11 make git docker psql redis-cli sqlite3 jq rg ruff pytest node; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '   %-11s %s\n' "$tool" "$("$tool" --version 2>&1 | head -1 | cut -c1-60)"
  else
    printf '   %-11s MISSING\n' "$tool"
  fi
done
for tool in zip unzip curl; do
  command -v "$tool" >/dev/null 2>&1 && printf '   %-11s ok\n' "$tool" || printf '   %-11s MISSING\n' "$tool"
done
mkdir -p "$ROOT/work"

echo
if [ "$fail" = 0 ]; then
  echo "READY. Next: scripts/start-project.sh <zip | folder | git-url>"
else
  echo "NOT READY - fix the FAILED lines above."
fi
exit "$fail"
