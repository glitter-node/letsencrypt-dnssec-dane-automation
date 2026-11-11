#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
DOMAIN="${CERTBOT_DOMAIN:?CERTBOT_DOMAIN is required}"
VALIDATION="${CERTBOT_VALIDATION:?CERTBOT_VALIDATION is required}"

printf 'DNS-01 authorization requested for: %s\n' "$DOMAIN"
printf 'TXT record: _acme-challenge.%s\n' "$DOMAIN"

if [[ "${DNS01_PROVIDER_ENABLED:-false}" != "true" ]]; then
  printf 'DNS provider integration is not configured\n' >&2
  exit 1
fi

CONFIG="${CONFIG_FILE:-$ROOT/config.example/domains.conf}"
[[ -f "$CONFIG" ]] || { printf "Configuration not found: %s\n" "$CONFIG" >&2; exit 1; }
source "$CONFIG"
ZONE="${DNS_ZONE_MAP[$DOMAIN]:-}"
[[ -n "$ZONE" ]] || { printf "DNS zone mapping not found: %s\n" "$DOMAIN" >&2; exit 1; }
DNSSEC="${DNSSEC_ZONE_ENABLED[$ZONE]:-}"
[[ "$DNSSEC" == "true" || "$DNSSEC" == "false" ]] || { printf "Invalid DNSSEC setting: %s\n" "$ZONE" >&2; exit 1; }

"$ROOT/src/hooks/dns-provider.sh" add "$DOMAIN" "$VALIDATION"

case "$DNSSEC" in
  true) "$ROOT/src/hooks/dnssec-sign.sh" "$ZONE" ;;
  false) ;;
esac

"$ROOT/src/hooks/dns-propagation.sh" "$DOMAIN" "$VALIDATION"
