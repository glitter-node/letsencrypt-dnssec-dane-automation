#!/usr/bin/env bash
set -Eeuo pipefail

ACTION="${1:?Action is required}"
DOMAIN="${2:?Domain is required}"
VALIDATION="${3:?Validation is required}"

case "$ACTION" in
  add|remove)
    printf "DNS provider adapter not implemented: %s for %s\n" "$ACTION" "$DOMAIN" >&2
    exit 1
    ;;
  *)
    printf "Unsupported DNS action: %s\n" "$ACTION" >&2
    exit 2
    ;;
esac
