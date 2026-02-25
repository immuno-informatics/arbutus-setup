#!/bin/bash
# ==============================================================================
# Server hardening configuration
#
# - Hardens SSH (key-only, no root)
# - Preserves passwordless sudo for 'ubuntu' user
# - Removes passwordless sudo for everyone else
#
# Usage: sudo ./harden.sh
# ==============================================================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo." >&2
    exit 1
fi

# --- SSH hardening ------------------------------------------------------------

log "Hardening SSH..."

tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AuthenticationMethods publickey

MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30

X11Forwarding no
AllowTcpForwarding yes
AllowAgentForwarding no
PermitTunnel no

AllowUsers ubuntu
EOF

# Clean up main sshd_config so it doesn't conflict
sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

if systemctl is-active --quiet ssh; then
    systemctl reload ssh
elif systemctl is-active --quiet ssh.socket; then
    systemctl restart ssh.socket
else
    log "WARNING: Could not detect SSH service. Verify manually."
fi

log "SSH hardened."

# --- Preserve ubuntu passwordless sudo, clean up everything else --------------

log "Configuring sudo..."

# Replace cloud-init file with an explicit ubuntu-only NOPASSWD rule
rm -f /etc/sudoers.d/90-cloud-init-users

tee /etc/sudoers.d/90-ubuntu > /dev/null <<'EOF'
ubuntu ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 440 /etc/sudoers.d/90-ubuntu
visudo -cf /etc/sudoers.d/90-ubuntu

# Remove any other NOPASSWD rules in sudoers.d (but not for 'ubuntu')
for f in /etc/sudoers.d/*; do
    [ -f "$f" ] || continue
    [[ "$(basename "$f")" == "90-ubuntu" ]] && continue
    if grep -q 'NOPASSWD' "$f"; then
        log "  Removing NOPASSWD file: $f"
        rm -f "$f"
    fi
done

log "ubuntu: passwordless sudo preserved. All other NOPASSWD rules removed."

# --- Done ---------------------------------------------------------------------

echo ""
echo "Hardening complete"
