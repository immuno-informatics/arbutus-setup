#!/bin/bash
# ==============================================================================
# First-time node setup software installation
#
# Run once on the server.
#
# Usage: sudo ./install-apps.sh
# ==============================================================================

set -euo pipefail

# Must run as root
if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

apt update

# --- Docker installation ------------------------------------------------------

# Add Docker's official GPG key:
apt -y install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update

apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Docker post-install
groupadd --force docker
usermod -aG docker "$USER"
usermod -aG docker ubuntu

# Docker daemon: log rotation
# This caps each container's log at 10MB with 3 rotated files (30MB total max).
mkdir -p /etc/docker
tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl enable docker
systemctl restart docker

# --- Done ---------------------------------------------------------------------

echo " "
echo "Setup complete."
echo " "
echo "Log out and go back in (for docker group to take effect)."
