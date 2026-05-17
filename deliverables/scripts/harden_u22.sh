#!/usr/bin/env bash
# harden_u22.sh
# Ubuntu 22.04 LTS specific wrapper around harden_common.sh.
# Applies CIS L1 Server remediation appropriate for U22 (CIS v3.0.0).
#
# Usage:  sudo bash harden_u22.sh

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=./harden_common.sh
source "${SCRIPT_DIR}/harden_common.sh"

ver=$(. /etc/os-release; echo "$VERSION_ID")
[[ "$ver" == "22.04" ]] || die "This host is $ver, expected 22.04. Use harden_u24.sh instead."

run_common

############################################
# Ubuntu 22.04 specific tweaks
############################################

u22_sshd_allow_users() {
    # 5.2.x: CIS requires an AllowUsers/AllowGroups directive.
    # We add a comment by default. Uncomment and edit as needed.
    local f=/etc/ssh/sshd_config.d/99-cis.conf
    grep -q '^#?AllowGroups' "$f" || {
        printf '\n# AllowGroups ssh-users\n' >> "$f"
    }
}

u22_journal_upload() {
    # 6.2.1.2.x on U22 expects systemd-journal-upload to be configured.
    # Install the package but leave URL unset \u2014 operator must set it in
    # /etc/systemd/journal-upload.conf (see runbook).
    pkg_install systemd-journal-remote
    systemctl enable --now systemd-journal-upload 2>/dev/null || true
}

u22_sshd_allow_users
u22_journal_upload

log "U22 hardening complete."
