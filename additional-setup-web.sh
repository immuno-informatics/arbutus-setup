#!/bin/bash
# ==============================================================================
# Additional configuration for the web server
#
# Usage: sudo ./additional-setup-web.sh <TLS_RENEW_SCRIPT> <TLS_RENEW_LOG>
# ==============================================================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <TLS_RENEW_SCRIPT> <TLS_RENEW_LOG>" >&2
  exit 1
fi

TLS_RENEW_SCRIPT="$1"
TLS_RENEW_LOG="$2"

# --- Set a cron job to refresh TLS certificates (UTC) -------------------------

# shellcheck disable=SC2035
0 10,22 * * * bash "${TLS_RENEW_SCRIPT}" >>"${TLS_RENEW_LOG}" 2>&1

log "TLS renew cron job set up."
