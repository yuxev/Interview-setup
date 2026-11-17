#!/usr/bin/env bash
# Rebuild Docker base image(s) under the SAME tag with this cloud session's
# egress-proxy CA trusted, so `pip install` / `npm ci` / `apk add` work inside
# `docker build` and `docker compose run` without editing a project's Dockerfile.
#
#   scripts/trust-image.sh python:3.12.7-slim [more images...]
#
# No-op outside a Claude cloud session (no /root/.ccr/ca-bundle.crt) and for
# images that are already patched. Safe to run repeatedly.
set -euo pipefail

CA_BUNDLE="${CA_BUNDLE:-/root/.ccr/ca-bundle.crt}"
PROXY_CA="${PROXY_CA:-/root/.ccr/agent-proxy-ca.crt}"
LABEL="interview-setup.ca-trusted"

if [ ! -f "$CA_BUNDLE" ]; then
  echo "trust-image: no $CA_BUNDLE (not a cloud session) - nothing to do"
  exit 0
fi
[ $# -ge 1 ] || { echo "usage: $0 IMAGE [IMAGE...]" >&2; exit 2; }

pull() {  # Docker Hub rate-limits anonymous pulls; fall back to public mirrors.
  local img="$1" ref
  docker image inspect "$img" >/dev/null 2>&1 && return 0
  for attempt in 1 2 3; do
    docker pull -q "$img" >/dev/null 2>&1 && return 0
    sleep $((attempt * 3))
  done
  case "$img" in
    */*) return 1 ;;  # not a Docker Hub "library" image: no mirror to try
  esac
  for mirror in mirror.gcr.io/library public.ecr.aws/docker/library; do
    ref="$mirror/$img"
    if docker pull -q "$ref" >/dev/null 2>&1; then
      docker tag "$ref" "$img"
      return 0
    fi
  done
  return 1
}

for img in "$@"; do
  if ! pull "$img"; then
    echo "trust-image: FAILED to pull $img" >&2
    exit 1
  fi
  if [ "$(docker image inspect -f "{{ index .Config.Labels \"$LABEL\" }}" "$img" 2>/dev/null)" = "1" ]; then
    echo "trust-image: $img already trusted"
    continue
  fi
  user="$(docker image inspect -f '{{ .Config.User }}' "$img")"
  ctx="$(mktemp -d)"
  cp "$CA_BUNDLE" "$ctx/ca-bundle.crt"
  cp "$PROXY_CA" "$ctx/proxy-ca.crt" 2>/dev/null || cp "$CA_BUNDLE" "$ctx/proxy-ca.crt"
  {
    echo "FROM $img"
    echo "COPY ca-bundle.crt /etc/ssl/interview-setup/ca-bundle.crt"
    echo "COPY proxy-ca.crt /etc/ssl/interview-setup/proxy-ca.crt"
    echo "ENV SSL_CERT_FILE=/etc/ssl/interview-setup/ca-bundle.crt \\"
    echo "    PIP_CERT=/etc/ssl/interview-setup/ca-bundle.crt \\"
    echo "    REQUESTS_CA_BUNDLE=/etc/ssl/interview-setup/ca-bundle.crt \\"
    echo "    CURL_CA_BUNDLE=/etc/ssl/interview-setup/ca-bundle.crt \\"
    echo "    NODE_EXTRA_CA_CERTS=/etc/ssl/interview-setup/ca-bundle.crt \\"
    echo "    GIT_SSL_CAINFO=/etc/ssl/interview-setup/ca-bundle.crt"
    echo "LABEL $LABEL=1"
  } > "$ctx/Dockerfile.base"
  # Second variant also appends the CA to the OS trust store (apk, apt over
  # https, curl, wget, go, ...). Needs a shell and root, so it is best-effort.
  {
    cat "$ctx/Dockerfile.base"
    echo "USER root"
    echo 'RUN for f in /etc/ssl/certs/ca-certificates.crt /etc/ssl/cert.pem /etc/pki/tls/certs/ca-bundle.crt; do if [ -f "$f" ] && [ ! -L "$f" ]; then cat /etc/ssl/interview-setup/proxy-ca.crt >> "$f"; fi; done; true'
    [ -n "$user" ] && echo "USER $user"
  } > "$ctx/Dockerfile.full"
  if docker build -q -t "$img" -f "$ctx/Dockerfile.full" "$ctx" >/dev/null 2>&1 \
     || docker build -q -t "$img" -f "$ctx/Dockerfile.base" "$ctx" >/dev/null; then
    echo "trust-image: $img now trusts the session proxy CA"
  else
    echo "trust-image: FAILED to patch $img" >&2
    rm -rf "$ctx"
    exit 1
  fi
  rm -rf "$ctx"
done
