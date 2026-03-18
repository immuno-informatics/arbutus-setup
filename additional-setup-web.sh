#!/bin/bash
# ==============================================================================
# Additional configuration for the web server
#
# Usage: ./additional-setup-web.sh <TLS_RENEW_SCRIPT> <TLS_RENEW_LOG>
# ==============================================================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <TLS_RENEW_SCRIPT> <TLS_RENEW_LOG>" >&2
  exit 1
fi

TLS_RENEW_SCRIPT="$1"
TLS_RENEW_LOG="$2"

# --- Set a cron job to refresh TLS certificates (UTC) -------------------------

(
  crontab -l 2>/dev/null || true
  echo "0 10,22 * * * bash \"${TLS_RENEW_SCRIPT}\" >>\"${TLS_RENEW_LOG}\" 2>&1"
) | crontab -

log "TLS renew cron job set up."
