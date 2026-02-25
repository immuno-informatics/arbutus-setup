# arbutus-setup

Order of init node setup:

1. `sudo bash install-apps.sh`&mdash;installs everything
2. `sudo bash harden.sh`&mdash;locks down SSH and sudo
3. `sudo bash firewall-setup-<type>.sh [ARGS]`&mdash;locks down network access
4. `sudo bash create-project-dir.sh <path>`&mdash;creates and configures a common project directory
