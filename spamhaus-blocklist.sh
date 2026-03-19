#!/bin/bash
# ==============================================================================
# Downloads Spamhaus DROP and EDROP lists and loads them into ipset/iptables
#
# Designed to run via cron (recommended: daily).
#
# Requirements: ipset, iptables, curl (or wget)
#
# Installation:
#   1. Copy to /usr/local/sbin/spamhaus-blocklist.sh
#   2. chmod 700 /usr/local/sbin/spamhaus-blocklist.sh
#   3. Add cron entry with: /usr/local/sbin/spamhaus-blocklist.sh update
#   4. Ensure it restores on reboot with: /usr/local/sbin/spamhaus-blocklist.sh restore
#   5. Run once manually to verify: sudo ./spamhaus-blocklist.sh update
#   6. Check current status with: sudo ./spamhaus-blocklist.sh status
#
# Spamhaus DROP  = "Don't Route Or Peer" -- hijacked/leased netblocks
# Spamhaus EDROP = Extended DROP -- suballocations of DROP-listed ranges
#
# Usage: sudo ./spamhaus-blocklist.sh {update|restore|status|uninstall}
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
DROP_URL="https://www.spamhaus.org/drop/drop.txt"
EDROP_URL="https://www.spamhaus.org/drop/edrop.txt"

IPSET_NAME="spamhaus-blocklist"
IPSET_TMP="${IPSET_NAME}-tmp"
IPTABLES_CHAIN="SPAMHAUS_DROP"

LOG_TAG="spamhaus-blocklist"
STATE_DIR="/var/lib/spamhaus"
CACHE_DIR="${STATE_DIR}/cache"
LOG_FILE="/var/log/spamhaus-blocklist.log"

MAX_LOG_SIZE=$((10 * 1024 * 1024)) # 10 MB log rotation threshold

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------
log() {
  local level="$1"
  shift
  local msg
  msg="$(date '+%Y-%m-%d %H:%M:%S') [${level}] $*"
  echo "$msg" >>"$LOG_FILE"
  logger -t "$LOG_TAG" -p "user.${level,,}" "$*" 2>/dev/null || true
  [[ "$level" == "ERROR" ]] && echo "$msg" >&2 || echo "$msg"
}

rotate_log() {
  if [[ -f "$LOG_FILE" ]] && (($(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null) > MAX_LOG_SIZE)); then
    mv "$LOG_FILE" "${LOG_FILE}.1"
    log "INFO" "Log rotated"
  fi
}

# ------------------------------------------------------------------------------
# Preflight checks
# ------------------------------------------------------------------------------
preflight() {
  if [[ $EUID -ne 0 ]]; then
    log "ERROR" "Must run as root"
    exit 1
  fi

  local missing=()
  for cmd in ipset iptables curl; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if ((${#missing[@]} > 0)); then
    log "ERROR" "Missing required commands: ${missing[*]}"
    exit 1
  fi

  mkdir -p "$STATE_DIR" "$CACHE_DIR"
}

# ------------------------------------------------------------------------------
# Download lists
# ------------------------------------------------------------------------------
download_lists() {
  local drop_file="${CACHE_DIR}/drop.txt"
  local edrop_file="${CACHE_DIR}/edrop.txt"
  local rc=0

  log "INFO" "Downloading Spamhaus DROP list..."
  if ! curl -sS --fail --max-time 60 -o "$drop_file" "$DROP_URL"; then
    log "ERROR" "Failed to download DROP list"
    rc=1
  fi

  log "INFO" "Downloading Spamhaus EDROP list..."
  if ! curl -sS --fail --max-time 60 -o "$edrop_file" "$EDROP_URL"; then
    log "ERROR" "Failed to download EDROP list"
    rc=1
  fi

  if ((rc != 0)); then
    if ipset list "$IPSET_NAME" &>/dev/null; then
      log "WARN" "Download failed but existing blocklist is active -- keeping current rules"
      exit 0
    else
      log "ERROR" "Download failed and no existing blocklist -- exiting"
      exit 1
    fi
  fi
}

# ------------------------------------------------------------------------------
# Parse CIDR ranges from Spamhaus list files
# Spamhaus format: "CIDR ; SBL_ID" with comments starting with ";"
# ------------------------------------------------------------------------------
parse_cidrs() {
  local cidrs=()
  for file in "${CACHE_DIR}/drop.txt" "${CACHE_DIR}/edrop.txt"; do
    [[ -f "$file" ]] || continue
    while IFS= read -r line; do
      # Skip comments and empty lines
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      [[ "$line" =~ ^[[:space:]]*\; ]] && continue
      # Extract CIDR (first field before ";")
      local cidr
      cidr=$(echo "$line" | awk -F';' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}')
      if [[ "$cidr" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        cidrs+=("$cidr")
      fi
    done <"$file"
  done

  if ((${#cidrs[@]} == 0)); then
    log "ERROR" "No valid CIDRs parsed -- aborting to prevent flushing existing rules"
    exit 1
  fi

  log "INFO" "Parsed ${#cidrs[@]} CIDR ranges from DROP + EDROP" >&2
  printf '%s\n' "${cidrs[@]}"
}

# ------------------------------------------------------------------------------
# Build ipset and iptables rules
# Uses atomic swap: build a temp set, then swap with the live one
# ------------------------------------------------------------------------------
apply_blocklist() {
  local cidrs
  mapfile -t cidrs < <(parse_cidrs)

  # Clean up any leftover temp set from a previous failed run
  ipset destroy "$IPSET_TMP" 2>/dev/null || true

  # Create temp ipset (hash:net is optimized for CIDR lookups)
  ipset create "$IPSET_TMP" hash:net maxelem $((${#cidrs[@]} + 1024))
  ipset flush "$IPSET_TMP"

  # Populate temp set
  for cidr in "${cidrs[@]}"; do
    ipset add "$IPSET_TMP" "$cidr" -exist
  done

  # Atomic swap: create live set if it doesn't exist, then swap
  ipset create "$IPSET_NAME" hash:net maxelem $((${#cidrs[@]} + 1024)) -exist
  ipset swap "$IPSET_TMP" "$IPSET_NAME"
  ipset destroy "$IPSET_TMP"

  log "INFO" "ipset '${IPSET_NAME}' updated with ${#cidrs[@]} entries"

  # Ensure iptables chain and rules exist
  setup_iptables

  # Save state for persistence across reboots
  ipset save "$IPSET_NAME" >"${STATE_DIR}/ipset.save"
  log "INFO" "ipset state saved to ${STATE_DIR}/ipset.save"
}

# ------------------------------------------------------------------------------
# Set up iptables chain (idempotent)
# ------------------------------------------------------------------------------
setup_iptables() {
  # Create dedicated chain if missing
  if ! iptables -L "$IPTABLES_CHAIN" -n &>/dev/null; then
    iptables -N "$IPTABLES_CHAIN"
    log "INFO" "Created iptables chain ${IPTABLES_CHAIN}"
  fi

  # Flush and repopulate the chain
  iptables -F "$IPTABLES_CHAIN"

  # Log dropped packets (rate-limited to avoid log flooding)
  iptables -A "$IPTABLES_CHAIN" -m limit --limit 5/min --limit-burst 10 \
    -j LOG --log-prefix "[SPAMHAUS DROP] " --log-level warning

  # Drop the packet
  iptables -A "$IPTABLES_CHAIN" -j DROP

  # Hook into INPUT and FORWARD chains (idempotent)
  for chain in INPUT FORWARD; do
    if ! iptables -L "$chain" -n | grep -q "match-set ${IPSET_NAME} src"; then
      iptables -I "$chain" 1 -m set --match-set "$IPSET_NAME" src -j "$IPTABLES_CHAIN"
      log "INFO" "Added ipset match rule to ${chain} chain"
    fi
  done
}

# ------------------------------------------------------------------------------
# Restore ipset on boot (call from /etc/rc.local or systemd unit)
# ------------------------------------------------------------------------------
restore() {
  if [[ -f "${STATE_DIR}/ipset.save" ]]; then
    ipset restore <"${STATE_DIR}/ipset.save" 2>/dev/null || true
    setup_iptables
    log "INFO" "Restored ipset from saved state"
  else
    log "WARN" "No saved state found -- run a full update first"
    main
  fi
}

# ------------------------------------------------------------------------------
# Status / diagnostics
# ------------------------------------------------------------------------------
status() {
  echo "=== ipset ==="
  if ipset list "$IPSET_NAME" &>/dev/null; then
    local count
    count=$(ipset list "$IPSET_NAME" | grep -c "^[0-9]" || true)
    echo "Set '${IPSET_NAME}': ${count} entries"
    echo ""
    echo "Header:"
    ipset list "$IPSET_NAME" | head -7 || true
  else
    echo "Set '${IPSET_NAME}' does not exist"
  fi

  echo ""
  echo "=== iptables rules ==="
  iptables -L INPUT -n --line-numbers 2>/dev/null | grep -i spamhaus || echo "No rules in INPUT"
  iptables -L FORWARD -n --line-numbers 2>/dev/null | grep -i spamhaus || echo "No rules in FORWARD"

  echo ""
  echo "=== Recent blocks (last 10) ==="
  grep "SPAMHAUS DROP" /var/log/syslog 2>/dev/null | tail -10 ||
    grep "SPAMHAUS DROP" /var/log/kern.log 2>/dev/null | tail -10 ||
    journalctl -k --grep="SPAMHAUS DROP" --no-pager -n 10 2>/dev/null ||
    echo "No recent blocks found in logs"

  echo ""
  echo "=== Last update ==="
  if [[ -f "${CACHE_DIR}/drop.txt" ]]; then
    stat -c "DROP list: %y" "${CACHE_DIR}/drop.txt" 2>/dev/null ||
      stat -f "DROP list: %Sm" "${CACHE_DIR}/drop.txt" 2>/dev/null
  fi
}

# ------------------------------------------------------------------------------
# Cleanup / uninstall
# ------------------------------------------------------------------------------
uninstall() {
  log "INFO" "Removing Spamhaus blocklist rules..."

  for chain in INPUT FORWARD; do
    local rulenum
    while rulenum=$(iptables -L "$chain" -n --line-numbers 2>/dev/null |
      grep "match-set ${IPSET_NAME} src" | awk '{print $1}' | head -1) && [[ -n "$rulenum" ]]; do
      iptables -D "$chain" "$rulenum"
    done
  done

  iptables -F "$IPTABLES_CHAIN" 2>/dev/null || true
  iptables -X "$IPTABLES_CHAIN" 2>/dev/null || true
  ipset destroy "$IPSET_NAME" 2>/dev/null || true

  log "INFO" "Blocklist removed. Files in ${STATE_DIR} retained for reference."
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
  rotate_log
  log "INFO" "=== Starting Spamhaus blocklist update ==="
  preflight
  download_lists
  apply_blocklist
  log "INFO" "=== Update complete ==="
}

# ------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------
case "${1:-}" in
update) main ;;
restore)
  preflight
  restore
  ;;
status) status ;;
uninstall)
  preflight
  uninstall
  ;;
*)
  echo "Usage: $0 {update|restore|status|uninstall}"
  echo " "
  echo "  update     Download lists and apply blocklist"
  echo "  restore    Restore saved ipset rules (for boot)"
  echo "  status     Show current blocklist status and recent blocks"
  echo "  uninstall  Remove all rules, chains, and ipsets"
  exit 1
  ;;
esac
