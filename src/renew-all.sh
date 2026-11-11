#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG_FILE:-$ROOT/config/domains.conf}"
STATE_DIR="${STATE_DIR:-$ROOT/state}"
CERTBOT="${CERTBOT:-certbot}"

if [[ ! -f "$CONFIG" ]]; then
  printf 'Configuration not found: %s\n' "$CONFIG" >&2
  exit 1
fi

command -v flock >/dev/null
command -v sha256sum >/dev/null
command -v "$CERTBOT" >/dev/null

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/renew.lock"
flock -n 9 || {
  printf 'Another renewal process is running\n' >&2
  exit 1
}

source "$CONFIG"

if ! declare -p CERT_NAMES 2>/dev/null | grep -q 'declare -a'; then
  printf 'CERT_NAMES must be an indexed array\n' >&2
  exit 1
fi

FAILED=0
CHANGED=0

for name in "${CERT_NAMES[@]}"; do
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || {
    printf 'Invalid certificate identifier: %s\n' "$name" >&2
    FAILED=$((FAILED + 1))
    continue
  }

  cert="$CERT_CONFIG_DIR/live/$name/cert.pem"
  before=""

  if [[ -f "$cert" ]]; then
    before="$(sha256sum "$cert" | awk '{print $1}')"
  fi

  printf 'Renewing: %s\n' "$name"

  if ! "$CERTBOT" renew \
    --cert-name "$name" \
    --config-dir "$CERT_CONFIG_DIR" \
    --work-dir "$CERT_WORK_DIR" \
    --logs-dir "$CERT_LOG_DIR"; then
    printf 'Renewal failed: %s\n' "$name" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  if [[ ! -f "$cert" ]]; then
    printf 'Certificate missing: %s\n' "$name" >&2
    FAILED=$((FAILED + 1))
    continue
  fi

  after="$(sha256sum "$cert" | awk '{print $1}')"

  if [[ "$before" != "$after" ]]; then
    CHANGED=$((CHANGED + 1))
    printf 'Certificate changed: %s\n' "$name"
  else
    printf 'Certificate unchanged: %s\n' "$name"
  fi
done

printf 'Changed: %s, Failed: %s\n' "$CHANGED" "$FAILED"
(( FAILED == 0 ))
