#!/usr/bin/env bash
# harden_u24.sh
# Ubuntu 24.04 LTS specific wrapper around harden_common.sh.
# Applies CIS L1 Server remediation appropriate for U24 (CIS v1.0.0).
#
# Usage:  sudo bash harden_u24.sh

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck source=./harden_common.sh
source "${SCRIPT_DIR}/harden_common.sh"

ver=$(. /etc/os-release; echo "$VERSION_ID")
[[ "$ver" == "24.04" ]] || die "This host is $ver, expected 24.04. Use harden_u22.sh instead."

run_common

############################################
# Ubuntu 24.04 specific tweaks
############################################

u24_nftables() {
    # On U24, CIS v1.0.0 keeps UFW as the default L1 choice.  The common
    # script already configures UFW.  We just make sure nftables is not
    # left in an unmanaged state.
    if systemctl list-unit-files | grep -q '^nftables.service'; then
        systemctl is-active --quiet nftables || systemctl disable --now nftables 2>/dev/null || true
    fi
}

u24_unattended_upgrades() {
    log "24.04: enabling unattended-upgrades for security updates"
    pkg_install unattended-upgrades apt-listchanges
    # 50unattended-upgrades allowlist for security origin is already set on U24
    backup_once /etc/apt/apt.conf.d/20auto-upgrades
    cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
    systemctl enable --now unattended-upgrades 2>/dev/null || true
}

u24_yescrypt_default() {
    # 24.04 ships yescrypt by default but verify.
    grep -q '^ENCRYPT_METHOD YESCRYPT' /etc/login.defs || kv_set /etc/login.defs ENCRYPT_METHOD YESCRYPT " "
}

u24_nftables
u24_unattended_upgrades
u24_yescrypt_default

log "U24 hardening complete."
