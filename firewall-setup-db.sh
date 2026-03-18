#!/usr/bin/env bash
# ==============================================================================
# UFW configuration for the database server
#
# Allows SSH and database port ONLY from known internal nodes.
# All other inbound traffic is denied.
#
# Run once on the server.
#
# Usage: sudo ./firewall-setup-db.sh <INTERNAL_IP_SPEC> <DB_PORT>
# ==============================================================================

set -euo pipefail

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <INTERNAL_IP_SPEC> <DB_PORT>" >&2
  exit 1
fi

DB_NAME="PostgreSQL"

INTERNAL_IP_SPEC="$1"
DB_PORT="$2"

# --- Reset UFW to clean state -------------------------------------------------

ufw --force reset

# --- Default policies ---------------------------------------------------------

# Deny all incoming, allow all outgoing (the server needs to
# reach the internet for apt updates, Docker pulls, etc.)

ufw default deny incoming
ufw default allow outgoing

# --- Enabled connections ------------------------------------------------------

# SSH (port 22)

ufw allow from "$INTERNAL_IP_SPEC" to any port 22 proto tcp comment "SSH"

# Database access (port DB_PORT)

ufw allow from "$INTERNAL_IP_SPEC" to any port "$DB_PORT" proto tcp comment "$DB_NAME"

# --- Enable -------------------------------------------------------------------

ufw --force enable

# --- Summary ------------------------------------------------------------------

echo " "
echo "Firewall configured. Current rules:"
echo " "
ufw status verbose
