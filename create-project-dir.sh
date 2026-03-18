#!/bin/bash
# ==============================================================================
# Create the main project directory with proper permissions
#
# Usage: sudo ./create-project-dir.sh <PATH>
# ==============================================================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <PATH>" >&2
  exit 1
fi

PROJECT_PATH="$1"

GROUP_NAME="docker"

if getent group "$GROUP_NAME" >/dev/null 2>&1; then
  mkdir -p "$PROJECT_PATH"

  chown -R root:$GROUP_NAME "$PROJECT_PATH"
  chmod -R 770 "$PROJECT_PATH"
  chmod g+s "$PROJECT_PATH"

  echo " "
  log "Directory '${PROJECT_PATH}' created."
else
  echo " "
  log "WARNING: ${GROUP_NAME} group not found. Run install-apps.sh first."
fi
