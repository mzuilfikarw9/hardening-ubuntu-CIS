#!/usr/bin/env bash
# lib_hardening.sh
# Shared helpers for CIS hardening scripts on Ubuntu 22/24.
# Source this file from harden_u22.sh / harden_u24.sh.
#
# Conventions:
#   - All functions are idempotent.
#   - Writes go through backup_once() before first edit per file per run.
#   - Cloud-init-sensitive settings are protected via cloudinit_guard().

set -o pipefail

# -------- logging --------
LOG_DIR="${LOG_DIR:-/var/log/cis-hardening}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/run-$(date +%Y%m%d-%H%M%S).log}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/cis-hardening/$(date +%Y%m%d-%H%M%S)}"

init_logging() {
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "[*] CIS hardening run started: $(date -Is)"
    echo "[*] Log:     $LOG_FILE"
    echo "[*] Backups: $BACKUP_DIR"
}

log()  { echo "[+] $*"; }
warn() { echo "[!] $*" >&2; }
die()  { echo "[X] $*" >&2; exit 1; }

require_root() {
    [[ "$(id -u)" -eq 0 ]] || die "Must run as root."
}

# -------- backup --------
declare -A _BACKED_UP
backup_once() {
    local f="$1"
    [[ -e "$f" ]] || return 0
    if [[ -z "${_BACKED_UP[$f]:-}" ]]; then
        local dest="$BACKUP_DIR${f}"
        mkdir -p "$(dirname "$dest")"
        cp -a "$f" "$dest"
        _BACKED_UP[$f]=1
    fi
}

# -------- cloud-init awareness --------
# Return 0 if cloud-init is installed and active on this system.
cloudinit_active() {
    command -v cloud-init >/dev/null 2>&1 && \
    systemctl list-unit-files 2>/dev/null | grep -q '^cloud-init'
}

# Guard: print a warning and skip when Cloud-init is active and the
# change would conflict with first-boot provisioning.
cloudinit_guard() {
    local what="$1"
    if cloudinit_active; then
        warn "Cloud-init is active \u2014 skipping: $what"
        return 1
    fi
    return 0
}

# -------- kv helpers --------
# Replace or append key/value in a shell-style config file.
# Usage: kv_set <file> <key> <value> [separator]
kv_set() {
    local file="$1" key="$2" value="$3" sep="${4:- }"
    backup_once "$file"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    if grep -Eq "^\s*#?\s*${key}\b" "$file"; then
        sed -ri "s|^\s*#?\s*${key}\b.*|${key}${sep}${value}|" "$file"
    else
        printf '%s%s%s\n' "$key" "$sep" "$value" >> "$file"
    fi
}

# Ensure a literal line exists in a file (comment-free, exact match).
ensure_line() {
    local file="$1" line="$2"
    backup_once "$file"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    grep -qxF "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

# -------- package helpers --------
pkg_install() {
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

pkg_remove() {
    DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@" || true
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -y || true
}

svc_disable_mask() {
    local s
    for s in "$@"; do
        systemctl disable --now "$s" 2>/dev/null || true
        systemctl mask "$s" 2>/dev/null || true
    done
}

svc_enable() {
    local s
    for s in "$@"; do
        systemctl enable --now "$s" 2>/dev/null || true
    done
}

# -------- kernel module disablement --------
# Disable a kernel module in CIS style (install false + blacklist + unload).
disable_kmodule() {
    local mod="$1"
    local conf="/etc/modprobe.d/${mod}.conf"
    backup_once "$conf"
    {
        echo "install ${mod} /bin/false"
        echo "blacklist ${mod}"
    } > "$conf"
    modprobe -r "$mod" 2>/dev/null || true
}

# -------- mount option helpers --------
# Ensure the given mount option is present for an already-mounted path in /etc/fstab.
# Usage: fstab_add_opt <mount_point> <option>
fstab_add_opt() {
    local mp="$1" opt="$2"
    [[ -f /etc/fstab ]] || return 0
    # Only act if the mount point has a line in /etc/fstab
    awk -v mp="$mp" '$2==mp {print}' /etc/fstab | grep -q . || {
        warn "No /etc/fstab entry for $mp \u2014 skipping option $opt (is it a separate partition?)"
        return 0
    }
    backup_once /etc/fstab
    awk -v mp="$mp" -v opt="$opt" '
        BEGIN{OFS="\t"}
        $2==mp && $1 !~ /^#/ {
            n=split($4,a,","); has=0;
            for (i=1;i<=n;i++) if (a[i]==opt) has=1;
            if (!has) { $4 = $4 "," opt }
        }
        {print}
    ' /etc/fstab > /etc/fstab.new && mv /etc/fstab.new /etc/fstab
    mount -o remount "$mp" 2>/dev/null || true
}

# -------- sysctl helpers --------
sysctl_set() {
    local key="$1" val="$2"
    local file="/etc/sysctl.d/60-cis.conf"
    backup_once "$file"
    if grep -Eq "^\s*#?\s*${key}\s*=" "$file" 2>/dev/null; then
        sed -ri "s|^\s*#?\s*${key}\s*=.*|${key} = ${val}|" "$file"
    else
        printf '%s = %s\n' "$key" "$val" >> "$file"
    fi
}

sysctl_apply() { sysctl --system >/dev/null; }
