#!/usr/bin/env bash
# ==============================================================================
# UFW configuration for the web server
#
# Allows SSH from anywhere, HTTP/HTTPS from anywhere.
# All outbound traffic is allowed (S3, DB, apt, Docker pulls).
#
# Run once on the server.
#
# Usage: sudo ./firewall-setup-web.sh
# ==============================================================================

set -euo pipefail

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

# --- Reset UFW to clean state -------------------------------------------------

ufw --force reset

# --- Default policies ---------------------------------------------------------

# Deny all incoming, allow all outgoing (the server needs to
# reach the internet for apt updates, Docker pulls, etc.)

ufw default deny incoming
ufw default allow outgoing

# --- Enabled connections ------------------------------------------------------

# SSH (port 22)

ufw allow 22/tcp comment "SSH"

# HTTP / HTTPS (ports 80, 443)

ufw allow 80/tcp comment "HTTP"
ufw allow 443/tcp comment "HTTPS"

# --- Enable -------------------------------------------------------------------

ufw --force enable

# --- Summary ------------------------------------------------------------------

echo " "
echo "Firewall configured. Current rules:"
echo " "
ufw status verbose
