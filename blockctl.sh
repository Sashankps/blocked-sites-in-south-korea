#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLOCKLIST="$ROOT/reviewed/porn-blocklist.txt"
HOSTS_FILE="/etc/hosts"
MARKER_BEGIN="# BEGIN porn-site-guard"
MARKER_END="# END porn-site-guard"
STATE_DIR="/Library/Application Support/porn-site-guard"
DNS_STATE_FILE="$STATE_DIR/dns-state.tsv"
STRICT_DNS_SERVERS=(
  185.228.168.168
  185.228.169.168
  2a0d:2a00:1::
  2a0d:2a00:2::
)

usage() {
  cat <<'USAGE'
Usage:
  ./blockctl.sh build      Normalize/review list.txt + kr.list
  sudo ./blockctl.sh enable    Enable system-wide hosts blocking
  sudo ./blockctl.sh disable   Kill switch: remove blocking entries
  sudo ./blockctl.sh strict-enable
                          Enable hosts blocking + CleanBrowsing Family DNS
  sudo ./blockctl.sh strict-disable
                          Kill switch: remove hosts block + restore DNS
  ./blockctl.sh status     Show whether the block is installed
  ./blockctl.sh check DOMAIN
                          Check whether a domain is reviewed and live-blocked

Notes:
  - enable/disable require sudo because they edit /etc/hosts.
  - strict-enable/strict-disable also change macOS network DNS settings.
  - This does not open, search, or fetch any listed site.
USAGE
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "This command must be run with sudo." >&2
    exit 1
  fi
}

build() {
  python3 "$ROOT/tools/review_blocklist.py"
}

strip_existing_block() {
  local input="$1"
  local output="$2"
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 == begin {skip = 1; next}
    $0 == end {skip = 0; next}
    skip != 1 {print}
  ' "$input" > "$output"
}

flush_dns() {
  dscacheutil -flushcache 2>/dev/null || true
  killall -HUP mDNSResponder 2>/dev/null || true
}

list_network_services() {
  local output
  if ! output="$(networksetup -listallnetworkservices 2>&1)"; then
    echo "$output" >&2
    return 1
  fi
  printf '%s\n' "$output" | sed '1d; s/^\*//'
}

require_networksetup() {
  if ! command -v networksetup >/dev/null 2>&1; then
    echo "strict mode requires macOS networksetup." >&2
    exit 1
  fi
}

save_dns_state() {
  mkdir -p "$STATE_DIR"
  if [[ -f "$DNS_STATE_FILE" ]]; then
    return
  fi

  local services
  services="$(list_network_services)"
  if [[ -z "$services" ]]; then
    echo "No macOS network services found." >&2
    exit 1
  fi

  while IFS= read -r service; do
    [[ -z "$service" ]] && continue
    local dns
    dns="$(networksetup -getdnsservers "$service" 2>/dev/null || true)"
    if [[ -z "$dns" || "$dns" == There\ aren\'t\ any\ DNS\ Servers* ]]; then
      dns="Empty"
    else
      dns="$(printf '%s\n' "$dns" | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    fi
    printf '%s\t%s\n' "$service" "$dns"
  done <<< "$services" > "$DNS_STATE_FILE"
}

set_strict_dns() {
  local services
  services="$(list_network_services)"
  if [[ -z "$services" ]]; then
    echo "No macOS network services found." >&2
    exit 1
  fi

  local applied=0
  local failed=0
  while IFS= read -r service; do
    [[ -z "$service" ]] && continue
    if networksetup -setdnsservers "$service" "${STRICT_DNS_SERVERS[@]}" 2>/dev/null; then
      applied=$((applied + 1))
    else
      failed=$((failed + 1))
      echo "Warning: failed to set DNS for network service: $service" >&2
    fi
  done <<< "$services"

  if [[ "$applied" -eq 0 ]]; then
    echo "Failed to set strict DNS on any network service." >&2
    exit 1
  fi
  if [[ "$failed" -gt 0 ]]; then
    echo "Strict DNS applied to $applied service(s), with $failed failure(s)." >&2
  fi
}

restore_dns_state() {
  if [[ ! -f "$DNS_STATE_FILE" ]]; then
    echo "No saved DNS state found; leaving DNS settings unchanged." >&2
    return
  fi

  while IFS=$'\t' read -r service dns; do
    [[ -z "$service" ]] && continue
    if [[ "$dns" == "Empty" || -z "$dns" ]]; then
      networksetup -setdnsservers "$service" Empty 2>/dev/null || echo "Warning: failed to restore DNS for network service: $service" >&2
    else
      local -a servers
      read -r -a servers <<< "$dns"
      networksetup -setdnsservers "$service" "${servers[@]}" 2>/dev/null || echo "Warning: failed to restore DNS for network service: $service" >&2
    fi
  done < "$DNS_STATE_FILE"

  rm -f "$DNS_STATE_FILE"
}

normalize_domain_arg() {
  printf '%s\n' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#^[a-z][a-z0-9+.-]*://##; s#/.*$##; s/:.*$//; s/^\.+//; s/\.+$//; s/^www\.//'
}

enable() {
  require_root
  if [[ ! -f "$BLOCKLIST" ]]; then
    build
  fi

  local tmp
  tmp="$(mktemp)"
  local backup="$HOSTS_FILE.porn-site-guard.$(date +%Y%m%d%H%M%S).bak"

  cp "$HOSTS_FILE" "$backup"
  strip_existing_block "$HOSTS_FILE" "$tmp"

  {
    cat "$tmp"
    echo ""
    echo "$MARKER_BEGIN"
    echo "# Generated from $BLOCKLIST"
    while IFS= read -r domain; do
      [[ -z "$domain" || "$domain" == \#* ]] && continue
      echo "0.0.0.0 $domain"
      echo "0.0.0.0 www.$domain"
      echo "0.0.0.0 m.$domain"
      echo "::1 $domain"
      echo "::1 www.$domain"
      echo "::1 m.$domain"
    done < "$BLOCKLIST"
    echo "$MARKER_END"
  } > "$tmp.new"

  cat "$tmp.new" > "$HOSTS_FILE"
  rm -f "$tmp" "$tmp.new"
  flush_dns
  echo "Enabled porn-site-guard. Backup: $backup"
}

disable() {
  require_root
  local tmp
  tmp="$(mktemp)"
  strip_existing_block "$HOSTS_FILE" "$tmp"
  cat "$tmp" > "$HOSTS_FILE"
  rm -f "$tmp"
  flush_dns
  echo "Disabled porn-site-guard."
}

strict_enable() {
  require_root
  require_networksetup
  enable
  save_dns_state
  set_strict_dns
  flush_dns
  echo "Enabled strict mode with CleanBrowsing Family DNS."
}

strict_disable() {
  require_root
  require_networksetup
  disable
  restore_dns_state
  flush_dns
  echo "Disabled strict mode and restored saved DNS settings."
}

status() {
  if grep -qxF "$MARKER_BEGIN" "$HOSTS_FILE" 2>/dev/null; then
    local count
    count="$(awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
      $0 == begin {inside = 1; next}
      $0 == end {inside = 0}
      inside == 1 && $1 ~ /^(0\.0\.0\.0|::1)$/ {count++}
      END {print count + 0}
    ' "$HOSTS_FILE")"
    local expected="unknown"
    if [[ -f "$BLOCKLIST" ]]; then
      local domains
      domains="$(grep -Evc '^[[:space:]]*($|#)' "$BLOCKLIST" || true)"
      expected="$((domains * 6))"
    fi
    if [[ "$expected" != "unknown" && "$count" -ne "$expected" ]]; then
      echo "enabled but stale ($count hosts entries, expected $expected); run: sudo ./blockctl.sh enable"
    else
      echo "enabled ($count hosts entries)"
    fi
  else
    echo "disabled"
  fi

  if [[ -f "$DNS_STATE_FILE" ]]; then
    echo "strict DNS: enabled or previously enabled (saved DNS state exists)"
  else
    echo "strict DNS: disabled"
  fi
}

check_domain() {
  local raw="${1:-}"
  if [[ -z "$raw" ]]; then
    echo "Usage: ./blockctl.sh check DOMAIN" >&2
    exit 2
  fi

  local domain
  domain="$(normalize_domain_arg "$raw")"
  echo "domain: $domain"

  if [[ -f "$BLOCKLIST" ]] && grep -qxF "$domain" "$BLOCKLIST"; then
    echo "reviewed blocklist: yes"
  else
    echo "reviewed blocklist: no"
  fi

  if awk -v domain="$domain" -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 == begin {inside = 1; next}
    $0 == end {inside = 0}
    inside == 1 && ($1 == "0.0.0.0" || $1 == "::1") && $2 == domain {found = 1}
    END {exit found ? 0 : 1}
  ' "$HOSTS_FILE" 2>/dev/null; then
    echo "live hosts block: yes"
  else
    echo "live hosts block: no"
  fi
}

case "${1:-}" in
  build) build ;;
  enable) enable ;;
  disable) disable ;;
  strict-enable|enable-strict) strict_enable ;;
  strict-disable|disable-strict) strict_disable ;;
  status) status ;;
  check) check_domain "${2:-}" ;;
  -h|--help|help|"") usage ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 2
    ;;
esac
