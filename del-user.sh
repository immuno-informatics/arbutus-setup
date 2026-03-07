#!/bin/bash
# ==============================================================================
# Delete user script
#
# Removes the user, their home directory, sudo config, and SSH AllowUsers entry.
#
# Usage: sudo ./del-user.sh <username>
# ==============================================================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <username>" >&2
  exit 1
fi

USERNAME="$1"

# --- Validate inputs ----------------------------------------------------------

# Safety: don't delete root, ubuntu, or the current sudo user

if [[ "$USERNAME" == "root" ]]; then
  echo "Cannot delete root." >&2
  exit 1
fi

if [[ "$USERNAME" == "ubuntu" ]]; then
  echo "Cannot delete the 'ubuntu' admin account." >&2
  exit 1
fi

if [[ "$USERNAME" == "$(logname 2>/dev/null || echo "$SUDO_USER")" ]]; then
  echo "Cannot delete the user you're currently logged in as." >&2
  exit 1
fi

# --- Kill any running processes -----------------------------------------------

if id "${USERNAME}" &>/dev/null; then
  pkill -u "${USERNAME}" 2>/dev/null || true
  sleep 1
fi

# --- Remove user and home directory -------------------------------------------

if id "${USERNAME}" &>/dev/null; then
  deluser --remove-home "${USERNAME}" 2>/dev/null || userdel -r "${USERNAME}"
  log "Removed user '${USERNAME}' and home directory."
else
  log "User '${USERNAME}' does not exist."
fi

# --- Remove sudoers file ------------------------------------------------------

SUDOERS_FILE="/etc/sudoers.d/user-${USERNAME}"
if [ -f "${SUDOERS_FILE}" ]; then
  rm -f "${SUDOERS_FILE}"
  log "Removed sudoers file."
fi

# --- Remove from SSH AllowUsers -----------------------------------------------

HARDENING_CONF="/etc/ssh/sshd_config.d/99-hardening.conf"

if [ -f "${HARDENING_CONF}" ] && grep -q "AllowUsers" "${HARDENING_CONF}"; then
  # Remove the username from the AllowUsers line
  sed -i "s/\bAllowUsers\(.*\) ${USERNAME}\b/AllowUsers\1/" "${HARDENING_CONF}"
  # Clean up double spaces
  sed -i 's/AllowUsers  */AllowUsers /' "${HARDENING_CONF}"

  if systemctl is-active --quiet ssh; then
    systemctl reload ssh
  elif systemctl is-active --quiet ssh.socket; then
    systemctl restart ssh.socket
  fi
  log "Removed '${USERNAME}' from AllowUsers."
fi

# --- Done ---------------------------------------------------------------------

echo " "
echo "User '${USERNAME}' fully removed."
