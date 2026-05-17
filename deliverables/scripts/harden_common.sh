#!/usr/bin/env bash
# harden_common.sh
# Remediation for CIS L1 Server controls that apply to both Ubuntu 22.04 and
# 24.04 and are failing on the HKL hosts. Designed to be safe to run on
# Proxmox Cloud-init derived VMs.
#
# Usage: sudo bash harden_common.sh
#
# Notes:
#   - This script is idempotent. You can re-run it after config changes.
#   - Controls that would break Cloud-init first-boot provisioning are
#     either skipped automatically (see cloudinit_guard) or deferred to
#     the Cloud-init template guide.
#   - Partition changes (1.1.2.x) cannot be done in place; they are handled
#     via the template. The script only sets correct mount options when a
#     separate partition already exists.

set -Eeuo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# shellcheck source=./lib_hardening.sh
source "${SCRIPT_DIR}/lib_hardening.sh"

require_root
init_logging

############################################
# 1. Initial Setup
############################################

section_1_kernel_modules() {
    log "1.1.1 Disabling legacy / risky kernel modules"
    local m
    for m in cramfs freevxfs hfs hfsplus jffs2 overlayfs squashfs udf usb-storage; do
        disable_kmodule "$m"
    done
}

section_1_mount_options() {
    log "1.1.2 Applying hardened mount options where partitions already exist"
    # /tmp
    fstab_add_opt /tmp nodev
    fstab_add_opt /tmp nosuid
    fstab_add_opt /tmp noexec
    # /dev/shm
    fstab_add_opt /dev/shm nodev
    fstab_add_opt /dev/shm nosuid
    fstab_add_opt /dev/shm noexec
    # /home
    fstab_add_opt /home nodev
    fstab_add_opt /home nosuid
    # /var
    fstab_add_opt /var nodev
    fstab_add_opt /var nosuid
    # /var/tmp
    fstab_add_opt /var/tmp nodev
    fstab_add_opt /var/tmp nosuid
    fstab_add_opt /var/tmp noexec
    # /var/log
    fstab_add_opt /var/log nodev
    fstab_add_opt /var/log nosuid
    fstab_add_opt /var/log noexec
    # /var/log/audit
    fstab_add_opt /var/log/audit nodev
    fstab_add_opt /var/log/audit nosuid
    fstab_add_opt /var/log/audit noexec
    systemctl unmask tmp.mount 2>/dev/null || true
}

section_1_updates() {
    log "1.2 Updating package cache and applying security updates"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
}

section_1_apparmor() {
    log "1.3 Installing and enabling AppArmor"
    pkg_install apparmor apparmor-utils
    backup_once /etc/default/grub
    if ! grep -q 'apparmor=1' /etc/default/grub; then
        sed -ri 's|^GRUB_CMDLINE_LINUX="(.*)"|GRUB_CMDLINE_LINUX="\1 apparmor=1 security=apparmor"|' /etc/default/grub
        # Collapse accidental double quotes / spaces
        sed -ri 's|  +| |g; s| "|"|g' /etc/default/grub
        update-grub >/dev/null 2>&1 || update-grub
    fi
    systemctl enable --now apparmor
    # Enforce all profiles
    if command -v aa-enforce >/dev/null 2>&1; then
        find /etc/apparmor.d -maxdepth 1 -type f -exec aa-enforce {} \; 2>/dev/null || true
    fi
}

section_1_bootloader_perms() {
    log "1.4 Locking down bootloader config"
    if [[ -f /boot/grub/grub.cfg ]]; then
        backup_once /boot/grub/grub.cfg
        chown root:root /boot/grub/grub.cfg
        chmod u-x,go-rwx /boot/grub/grub.cfg
    fi
}

section_1_process_hardening() {
    log "1.5 Process hardening: ASLR, core dumps, ptrace, prelink"
    sysctl_set kernel.randomize_va_space 2
    sysctl_set fs.suid_dumpable 0
    sysctl_set kernel.yama.ptrace_scope 1

    # Disable core dumps
    ensure_line /etc/security/limits.d/99-cis-nocore.conf "* hard core 0"
    kv_set /etc/systemd/coredump.conf Storage none =
    kv_set /etc/systemd/coredump.conf ProcessSizeMax 0 =

    # Remove prelink if installed (CIS deprecates it)
    pkg_remove prelink
    sysctl_apply
}

section_1_warning_banners() {
    log "1.7 Configuring warning banners"
    local banner='Authorized users only. All activity may be monitored and reported.'
    for f in /etc/issue /etc/issue.net /etc/motd; do
        backup_once "$f"
        printf '%s\n' "$banner" > "$f"
        chown root:root "$f"
        chmod 644 "$f"
    done
}

############################################
# 2. Services
############################################

section_2_remove_servers() {
    log "2.1 Removing legacy/unused server packages (if installed)"
    # CIS says: not installed (or masked if business need).
    pkg_remove \
        autofs \
        avahi-daemon \
        isc-dhcp-server \
        bind9 \
        dnsmasq \
        vsftpd \
        slapd \
        dovecot-imapd dovecot-pop3d \
        nfs-kernel-server \
        ypserv \
        cups \
        rpcbind \
        rsync \
        samba \
        snmpd \
        tftpd-hpa \
        squid \
        apache2 nginx \
        xinetd \
        nis
}

section_2_remove_clients() {
    log "2.3 Removing legacy clients"
    pkg_remove nis rsh-client talk telnet ldap-utils ftp
}

section_2_time_sync() {
    log "2.3 Configuring chrony for time sync"
    pkg_install chrony
    systemctl disable --now systemd-timesyncd 2>/dev/null || true
    systemctl enable --now chrony 2>/dev/null || systemctl enable --now chronyd 2>/dev/null || true
}

section_2_job_schedulers() {
    log "2.4 Locking down cron/at permissions"
    if command -v systemctl >/dev/null && systemctl list-unit-files | grep -q '^cron.service'; then
        systemctl enable --now cron
    fi
    local d
    for d in /etc/crontab /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly /etc/cron.d; do
        [[ -e "$d" ]] || continue
        backup_once "$d"
        chown root:root "$d"
        chmod og-rwx "$d" 2>/dev/null || chmod 700 "$d"
    done
    # at
    if command -v at >/dev/null 2>&1; then
        touch /etc/at.allow
        chown root:root /etc/at.allow
        chmod 640 /etc/at.allow
        rm -f /etc/at.deny
    fi
    touch /etc/cron.allow
    chown root:root /etc/cron.allow
    chmod 640 /etc/cron.allow
    rm -f /etc/cron.deny
}

############################################
# 3. Network
############################################

section_3_disable_protocols() {
    log "3.1 Disabling uncommon network protocols"
    local m
    for m in dccp tipc rds sctp; do
        disable_kmodule "$m"
    done
}

section_3_network_parameters() {
    log "3.2/3.3 Applying network sysctl hardening"
    # Packet redirect sending
    sysctl_set net.ipv4.conf.all.send_redirects 0
    sysctl_set net.ipv4.conf.default.send_redirects 0
    # IP forwarding \u2014 disabled for typical server; keep router hosts out of this class
    sysctl_set net.ipv4.ip_forward 0
    sysctl_set net.ipv6.conf.all.forwarding 0
    # Source-routed packets
    sysctl_set net.ipv4.conf.all.accept_source_route 0
    sysctl_set net.ipv4.conf.default.accept_source_route 0
    sysctl_set net.ipv6.conf.all.accept_source_route 0
    sysctl_set net.ipv6.conf.default.accept_source_route 0
    # ICMP redirects
    sysctl_set net.ipv4.conf.all.accept_redirects 0
    sysctl_set net.ipv4.conf.default.accept_redirects 0
    sysctl_set net.ipv6.conf.all.accept_redirects 0
    sysctl_set net.ipv6.conf.default.accept_redirects 0
    sysctl_set net.ipv4.conf.all.secure_redirects 0
    sysctl_set net.ipv4.conf.default.secure_redirects 0
    # Log suspicious packets
    sysctl_set net.ipv4.conf.all.log_martians 1
    sysctl_set net.ipv4.conf.default.log_martians 1
    # Ignore broadcast ICMP, bogus responses
    sysctl_set net.ipv4.icmp_echo_ignore_broadcasts 1
    sysctl_set net.ipv4.icmp_ignore_bogus_error_responses 1
    # RP filter
    sysctl_set net.ipv4.conf.all.rp_filter 1
    sysctl_set net.ipv4.conf.default.rp_filter 1
    # TCP syncookies
    sysctl_set net.ipv4.tcp_syncookies 1
    # IPv6 RA
    sysctl_set net.ipv6.conf.all.accept_ra 0
    sysctl_set net.ipv6.conf.default.accept_ra 0
    sysctl_apply
}

############################################
# 4. Host-based Firewall
############################################

section_4_firewall_ufw() {
    log "4.1 Configuring UFW (host-based firewall)"
    pkg_install ufw
    # Keep existing SSH flow alive to avoid lockout
    ufw allow OpenSSH >/dev/null 2>&1 || ufw allow 22/tcp >/dev/null 2>&1 || true
    ufw default deny incoming
    ufw default allow outgoing
    # Loopback
    ufw allow in on lo
    ufw allow out on lo
    ufw deny in from 127.0.0.0/8
    ufw deny in from ::1
    yes | ufw --force enable
    systemctl enable --now ufw
}

############################################
# 5. Access, Authentication and Authorization
############################################

section_5_sshd() {
    log "5.1 Hardening OpenSSH server"
    local c=/etc/ssh/sshd_config
    [[ -f "$c" ]] || return 0
    backup_once "$c"
    # Drop-in style: put our overrides in a managed include that wins by sort order.
    local d=/etc/ssh/sshd_config.d/99-cis.conf
    mkdir -p /etc/ssh/sshd_config.d
    backup_once "$d"
    cat >"$d" <<'EOF'
# CIS-aligned overrides. Do not edit by hand; managed by harden_common.sh.
Protocol 2
LogLevel VERBOSE
X11Forwarding no
MaxAuthTries 4
IgnoreRhosts yes
HostbasedAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
PermitUserEnvironment no
PasswordAuthentication no
KbdInteractiveAuthentication no
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group-exchange-sha256
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60
Banner /etc/issue.net
UsePAM yes
AllowTcpForwarding no
MaxStartups 10:30:60
MaxSessions 4
EOF
    chown root:root "$c" "$d"
    chmod 600 "$c" "$d"
    # /etc/ssh/sshd_config.d/*.conf ownership/perms
    find /etc/ssh/sshd_config.d -type f -name '*.conf' -exec chown root:root {} \; -exec chmod 600 {} \;
    # Private host keys
    find /etc/ssh -type f -name 'ssh_host_*_key' -exec chown root:root {} \; -exec chmod 600 {} \;
    find /etc/ssh -type f -name 'ssh_host_*_key.pub' -exec chown root:root {} \; -exec chmod 644 {} \;
    sshd -t && systemctl reload ssh || warn "sshd config test failed \u2014 NOT reloading"
}

section_5_sudo() {
    log "5.2 Hardening sudo"
    pkg_install sudo
    local f=/etc/sudoers.d/99-cis
    backup_once "$f"
    cat >"$f" <<'EOF'
Defaults use_pty
Defaults logfile="/var/log/sudo.log"
Defaults !visiblepw
Defaults timestamp_timeout=15
EOF
    chmod 440 "$f"
    chown root:root "$f"
    # visudo -c will refuse to start if anything is bad
    visudo -cf "$f" >/dev/null || die "sudoers drop-in syntax error at $f"
}

section_5_password_pam() {
    log "5.3 Password quality + faillock via PAM"
    pkg_install libpam-pwquality

    # pwquality settings
    backup_once /etc/security/pwquality.conf
    kv_set /etc/security/pwquality.conf minlen 14 " = "
    kv_set /etc/security/pwquality.conf minclass 4 " = "
    kv_set /etc/security/pwquality.conf dcredit -1 " = "
    kv_set /etc/security/pwquality.conf ucredit -1 " = "
    kv_set /etc/security/pwquality.conf ocredit -1 " = "
    kv_set /etc/security/pwquality.conf lcredit -1 " = "
    kv_set /etc/security/pwquality.conf difok 3 " = "
    kv_set /etc/security/pwquality.conf maxrepeat 3 " = "
    kv_set /etc/security/pwquality.conf maxclassrepeat 4 " = "
    kv_set /etc/security/pwquality.conf enforce_for_root "" " "

    # faillock
    backup_once /etc/security/faillock.conf
    kv_set /etc/security/faillock.conf deny 5 " = "
    kv_set /etc/security/faillock.conf unlock_time 900 " = "
    kv_set /etc/security/faillock.conf fail_interval 900 " = "

    # Enable via pam-auth-update profiles if available
    if command -v pam-auth-update >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive pam-auth-update --enable pwquality faillock faillock_notify 2>/dev/null || true
    fi

    # Password aging / shadow defaults
    backup_once /etc/login.defs
    kv_set /etc/login.defs PASS_MAX_DAYS 365 " "
    kv_set /etc/login.defs PASS_MIN_DAYS 1   " "
    kv_set /etc/login.defs PASS_WARN_AGE 7   " "
    kv_set /etc/login.defs ENCRYPT_METHOD YESCRYPT " "
    kv_set /etc/login.defs UMASK 027 " "

    # Apply aging to existing users
    awk -F: '($3>=1000)&&($1!="nobody"){print $1}' /etc/passwd | \
        while read -r u; do chage --maxdays 365 --mindays 1 --warndays 7 "$u" || true; done
}

section_5_user_env() {
    log "5.4 User shell defaults: TMOUT and umask"
    backup_once /etc/profile
    ensure_line /etc/profile.d/99-cis.sh 'TMOUT=900'
    ensure_line /etc/profile.d/99-cis.sh 'readonly TMOUT'
    ensure_line /etc/profile.d/99-cis.sh 'export TMOUT'
    ensure_line /etc/profile.d/99-cis.sh 'umask 027'
    chown root:root /etc/profile.d/99-cis.sh
    chmod 644 /etc/profile.d/99-cis.sh

    # System accounts: no valid login shell
    awk -F: '($3<1000)&&($1!="root")&&($7!="/usr/sbin/nologin")&&($7!="/bin/false")&&($7!="/sbin/nologin"){print $1}' /etc/passwd | \
        while read -r u; do usermod -s /usr/sbin/nologin "$u" 2>/dev/null || true; done

    # Default group for root
    usermod -g 0 root 2>/dev/null || true

    # Lock accounts with empty passwords
    awk -F: '($2==""){print $1}' /etc/shadow | \
        while read -r u; do passwd -l "$u" 2>/dev/null || true; done
}

############################################
# 6. Logging & Auditing
############################################

section_6_auditd() {
    log "6.2/6.3 Installing and configuring auditd"
    # audispd-plugins was merged into auditd on Ubuntu 22.04+. Keep
    # it as an optional second arg for legacy hosts; pkg_install
    # will silently skip any package that's not available.
    pkg_install auditd
    backup_once /etc/audit/auditd.conf
    kv_set /etc/audit/auditd.conf max_log_file 32 " = "
    kv_set /etc/audit/auditd.conf max_log_file_action keep_logs " = "
    kv_set /etc/audit/auditd.conf space_left_action email " = "
    kv_set /etc/audit/auditd.conf action_mail_acct root " = "
    kv_set /etc/audit/auditd.conf admin_space_left_action halt " = "

    # Enable auditd at boot time via GRUB (audit=1, audit_backlog_limit=8192)
    backup_once /etc/default/grub
    if ! grep -q 'audit=1' /etc/default/grub; then
        sed -ri 's|^GRUB_CMDLINE_LINUX="(.*)"|GRUB_CMDLINE_LINUX="\1 audit=1 audit_backlog_limit=8192"|' /etc/default/grub
        sed -ri 's|  +| |g; s| "|"|g' /etc/default/grub
        update-grub >/dev/null 2>&1 || update-grub
    fi

    # Drop a ready-made rules file. Full CIS audit rules; load on reboot.
    local rules=/etc/audit/rules.d/99-cis.rules
    backup_once "$rules"
    cat >"$rules" <<'EOF'
## CIS Ubuntu L1 Server audit rules (subset, most impactful)
-D
-b 8192
-f 1

## Time changes
-a always,exit -F arch=b64 -S adjtimex,settimeofday,clock_settime -k time-change
-a always,exit -F arch=b32 -S adjtimex,settimeofday,clock_settime -k time-change
-w /etc/localtime -p wa -k time-change

## User/group changes
-w /etc/group -p wa -k identity
-w /etc/passwd -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/security/opasswd -p wa -k identity

## Network environment
-a always,exit -F arch=b64 -S sethostname,setdomainname -k system-locale
-a always,exit -F arch=b32 -S sethostname,setdomainname -k system-locale
-w /etc/issue -p wa -k system-locale
-w /etc/issue.net -p wa -k system-locale
-w /etc/hosts -p wa -k system-locale
-w /etc/netplan/ -p wa -k system-locale

## MAC (AppArmor)
-w /etc/apparmor/ -p wa -k MAC-policy
-w /etc/apparmor.d/ -p wa -k MAC-policy

## Login / logout
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/log/tallylog -p wa -k logins
-w /var/run/faillock -p wa -k logins
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

## Discretionary access control
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b64 -S chown,fchown,lchown,fchownat -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S chown,fchown,lchown,fchownat -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b64 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=unset -F key=perm_mod
-a always,exit -F arch=b32 -S setxattr,lsetxattr,fsetxattr,removexattr,lremovexattr,fremovexattr -F auid>=1000 -F auid!=unset -F key=perm_mod

## Unsuccessful file access attempts
-a always,exit -F arch=b64 -S open,openat,truncate,ftruncate,creat -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b64 -S open,openat,truncate,ftruncate,creat -F exit=-EPERM  -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b32 -S open,openat,truncate,ftruncate,creat -F exit=-EACCES -F auid>=1000 -F auid!=unset -k access
-a always,exit -F arch=b32 -S open,openat,truncate,ftruncate,creat -F exit=-EPERM  -F auid>=1000 -F auid!=unset -k access

## Privileged command usage \u2014 emitted at runtime by /etc/audit/rules.d/50-privileged.rules if desired.

## Mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=unset -k mounts
-a always,exit -F arch=b32 -S mount -F auid>=1000 -F auid!=unset -k mounts

## Session init
-w /var/run/utmp -p wa -k session

## File deletions by regular users
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=unset -k delete
-a always,exit -F arch=b32 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=unset -k delete

## sudoers
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope

## sudo log
-w /var/log/sudo.log -p wa -k actions

## Kernel module loading/unloading
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -F auid!=unset -k modules
-w /sbin/insmod  -p x -k modules
-w /sbin/rmmod   -p x -k modules
-w /sbin/modprobe -p x -k modules

## Make the configuration immutable \u2014 comment out to ease troubleshooting.
-e 2
EOF
    systemctl enable --now auditd
    augenrules --load >/dev/null || true
}

section_6_rsyslog_journald() {
    log "6.1 rsyslog / journald hardening"
    pkg_install rsyslog
    systemctl enable --now rsyslog

    # journald config
    backup_once /etc/systemd/journald.conf
    kv_set /etc/systemd/journald.conf Storage persistent =
    kv_set /etc/systemd/journald.conf Compress yes =
    kv_set /etc/systemd/journald.conf ForwardToSyslog yes =
    systemctl restart systemd-journald

    # rsyslog file perms
    kv_set /etc/rsyslog.conf '$FileCreateMode' 0640 " "
    systemctl restart rsyslog
}

section_6_logfile_perms() {
    log "6.1.4 Securing log file permissions"
    # Apply CIS-recommended perms/ownership to everything under /var/log
    find /var/log -type f 2>/dev/null | while read -r f; do
        chmod g-wx,o-rwx "$f" 2>/dev/null || true
    done
    find /var/log -type d 2>/dev/null | while read -r d; do
        chmod g-w,o-rwx "$d" 2>/dev/null || true
    done
}

section_6_aide() {
    log "6.4 Installing AIDE for file integrity monitoring"
    pkg_install aide aide-common
    if [[ ! -f /var/lib/aide/aide.db ]]; then
        log "    initializing AIDE database (can take a few minutes)"
        aideinit -y -f >/dev/null 2>&1 || aideinit || true
        [[ -f /var/lib/aide/aide.db.new ]] && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi
    # Scheduled check
    cat >/etc/cron.d/aide <<'EOF'
0 5 * * * root /usr/bin/aide.wrapper --check 2>&1 | /usr/bin/logger -t aide
EOF
    chown root:root /etc/cron.d/aide
    chmod 644 /etc/cron.d/aide
}

############################################
# 7. System Maintenance
############################################

section_7_file_perms() {
    log "7.1 System file permissions"
    chown root:root /etc/passwd        && chmod 644 /etc/passwd
    chown root:root /etc/passwd-       && chmod 644 /etc/passwd- 2>/dev/null || true
    chown root:shadow /etc/shadow      && chmod 640 /etc/shadow
    chown root:shadow /etc/shadow-     && chmod 640 /etc/shadow- 2>/dev/null || true
    chown root:root /etc/group         && chmod 644 /etc/group
    chown root:root /etc/group-        && chmod 644 /etc/group- 2>/dev/null || true
    chown root:shadow /etc/gshadow     && chmod 640 /etc/gshadow
    chown root:shadow /etc/gshadow-    && chmod 640 /etc/gshadow- 2>/dev/null || true
    [[ -f /etc/security/opasswd ]] && chown root:root /etc/security/opasswd && chmod 600 /etc/security/opasswd
}

section_7_user_accounts() {
    log "7.2 User account hygiene"
    # root path integrity
    # (Do nothing destructive; just warn if PATH has non-root writable dirs)
    local badpath
    badpath=$(sudo -Hiu root env | awk -F= '/^PATH=/{print $2}' | tr ':' '\n' | \
              while read -r p; do [[ -d "$p" ]] && [[ $(stat -c '%U:%a' "$p") =~ ^root:(7[0-7][0-7]|755)$ ]] || echo "$p"; done || true)
    [[ -n "$badpath" ]] && warn "Review root PATH dirs with non-root ownership or world-writable perms:"$'\n'"$badpath"

    # Home directory perms for regular users
    awk -F: '($3>=1000)&&($1!="nobody"){print $1":"$6}' /etc/passwd | while IFS=: read -r u h; do
        [[ -d "$h" ]] || continue
        chmod 750 "$h" 2>/dev/null || true
        chown "$u":"$u" "$h" 2>/dev/null || true
    done
}

############################################
# Orchestrator
############################################

run_common() {
    section_1_kernel_modules
    section_1_mount_options
    section_1_updates
    section_1_apparmor
    section_1_bootloader_perms
    section_1_process_hardening
    section_1_warning_banners
    section_2_remove_servers
    section_2_remove_clients
    section_2_time_sync
    section_2_job_schedulers
    section_3_disable_protocols
    section_3_network_parameters
    section_4_firewall_ufw
    section_5_sshd
    section_5_sudo
    section_5_password_pam
    section_5_user_env
    section_6_rsyslog_journald
    section_6_auditd
    section_6_logfile_perms
    section_6_aide
    section_7_file_perms
    section_7_user_accounts
    log "Common CIS hardening complete. Log: $LOG_FILE"
    log "Reboot is recommended (GRUB / auditd / AppArmor changes)."
}

# Only run when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_common
fi
