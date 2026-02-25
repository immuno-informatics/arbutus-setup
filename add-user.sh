#!/bin/bash
# ==============================================================================
# Add user script
#
# Creates a user with:
#   - SSH key authentication
#   - Password-protected sudo access
#   - Added to AllowUsers in SSH config
#   - Added to docker group
#
# Usage: sudo ./add-user.sh <username> <ssh-pubkey> <sudo-password>
# ==============================================================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo." >&2
    exit 1
fi

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <username> <ssh-pubkey> <sudo-password>" >&2
    exit 1
fi

USERNAME="$1"
SSH_PUBKEY="$2"
SUDO_PASSWORD="$3"

# --- Validate inputs ----------------------------------------------------------

if [[ "$USERNAME" == "ubuntu" ]]; then
    echo "Cannot modify the 'ubuntu' admin account with this script." >&2
    exit 1
fi

if ! [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    echo "Invalid username. Use lowercase letters, numbers, hyphens, underscores." >&2
    exit 1
fi

if ! [[ "$SSH_PUBKEY" =~ ^ssh- ]]; then
    echo "SSH public key should start with 'ssh-'. Did you pass the public key?" >&2
    exit 1
fi

# --- Create user --------------------------------------------------------------

if id "${USERNAME}" &>/dev/null; then
    log "User '${USERNAME}' already exists. Updating SSH key and password."
else
    adduser --disabled-password --gecos "" "${USERNAME}"
    log "Created user '${USERNAME}'."
fi

# Set password (needed for sudo authentication)
echo "${USERNAME}:${SUDO_PASSWORD}" | chpasswd
log "Password set for '${USERNAME}'."

# --- Set up SSH key -----------------------------------------------------------

SSH_DIR="/home/${USERNAME}/.ssh"
mkdir -p "${SSH_DIR}"
echo "${SSH_PUBKEY}" > "${SSH_DIR}/authorized_keys"
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/authorized_keys"
chown -R "${USERNAME}:${USERNAME}" "${SSH_DIR}"
log "SSH key installed."

# --- Grant password-protected sudo --------------------------------------------

tee "/etc/sudoers.d/user-${USERNAME}" > /dev/null <<EOF
${USERNAME} ALL=(ALL:ALL) ALL
EOF
chmod 440 "/etc/sudoers.d/user-${USERNAME}"
visudo -cf "/etc/sudoers.d/user-${USERNAME}"
log "Sudo access granted (password required)."

# --- Add to SSH AllowUsers ----------------------------------------------------

HARDENING_CONF="/etc/ssh/sshd_config.d/99-hardening.conf"

if [ -f "${HARDENING_CONF}" ]; then
    if grep -q "^AllowUsers" "${HARDENING_CONF}"; then
        # Append to existing AllowUsers line (if not already listed)
        if ! grep -q "AllowUsers.*\b${USERNAME}\b" "${HARDENING_CONF}"; then
            sed -i "s/^AllowUsers.*/& ${USERNAME}/" "${HARDENING_CONF}"
            log "Added '${USERNAME}' to AllowUsers."
        else
            log "'${USERNAME}' already in AllowUsers."
        fi
    else
        echo "AllowUsers ${USERNAME}" >> "${HARDENING_CONF}"
        log "Created AllowUsers with '${USERNAME}'."
    fi

    # Reload SSH to pick up the new AllowUsers
    if systemctl is-active --quiet ssh; then
        systemctl reload ssh
    elif systemctl is-active --quiet ssh.socket; then
        systemctl restart ssh.socket
    fi
else
    log "WARNING: ${HARDENING_CONF} not found. Run harden.sh first."
fi

# --- Add to docker group ------------------------------------------------------

GROUP_NAME="docker"

if getent group "$GROUP_NAME" > /dev/null 2>&1; then
    usermod -aG "$GROUP_NAME" "$USERNAME"
    log "Added ${USERNAME} to ${GROUP_NAME} group."
else
    log "WARNING: ${GROUP_NAME} group not found. Run install-apps.sh first."
fi

# --- Done ---------------------------------------------------------------------

echo ""
echo "User '${USERNAME}' is ready."
