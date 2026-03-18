# arbutus-setup

Scripts for setting up cloud instances.

Order of init node setup:

1. `sudo bash install-apps.sh`&mdash;installs everything
2. `sudo bash harden.sh`&mdash;locks down SSH and sudo
3. `sudo bash firewall-setup-<TYPE>.sh [ARGS]`&mdash;locks down network access
4. `sudo bash create-project-dir.sh <PATH>`&mdash;creates and configures a common project directory
5. `bash additional-setup-web.sh <TLS_RENEW_SCRIPT> <TLS_RENEW_LOG>`&mdash;additional setup steps
