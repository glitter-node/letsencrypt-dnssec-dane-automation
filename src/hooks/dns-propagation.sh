#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${1:?Domain is required}"
VALIDATION="${2:?Validation is required}"

printf "DNS-01 propagation check requested for: %s\n" "$DOMAIN"
printf "DNS propagation verification is not implemented\n" >&2
exit 1
