#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${1:?Domain is required}"

printf "DNSSEC signing requested for: %s\n" "$DOMAIN"
printf "DNSSEC signing adapter is not implemented\n" >&2
exit 1
