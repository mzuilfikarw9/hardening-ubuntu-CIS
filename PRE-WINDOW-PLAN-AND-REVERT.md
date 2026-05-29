# Pre-window role apply + revert plan

**Purpose:** Apply the 12 remaining CIS hardening tags to prod 2 hours before the maintenance window, observe for 95 min, then reboot inside the 60-min window.

**Already applied (Path B earlier):** `banners`, `sudo`
**Apply at T-2hr:** the 12 remaining tags below.

---

## The 12 tags — what each does, live impact, revert

### 1. `kernel_modules`
- **Does:** Writes `/etc/modprobe.d/<mod>.conf` with `install <mod> /bin/false` + blacklist for `cramfs freevxfs hfs hfsplus jffs2 overlayfs squashfs udf usb-storage dccp tipc rds sctp`. Then attempts `modprobe -r <mod>` (overlayfs skipped on k3s).
- **Live impact:** Blacklist files only effective on reboot. `modprobe -r` runs live (handled with block/rescue, non-fatal if module in use).
- **Worst case:** Module unloaded that something was using.
- **Revert:** `rm /etc/modprobe.d/{cramfs,freevxfs,hfs,hfsplus,jffs2,overlayfs,squashfs,udf,usb-storage,dccp,tipc,rds,sctp}.conf` (and `modprobe <mod>` if needed)
- **Risk:** Low — standard servers don't use these.

### 2. `mount_options`
- **Does:** REMOUNTS `/tmp`, `/dev/shm`, and (if separate) `/home`, `/var`, `/var/tmp`, `/var/log`, `/var/log/audit` with `nosuid,nodev,noexec`. Unmasks `tmp.mount`.
- **Live impact:** Remounts happen immediately. /dev/shm and /tmp get `noexec`.
- **Worst case:** App that execs from /tmp or /dev/shm breaks.
- **Revert:** `mount -o remount,exec /tmp /dev/shm` and edit `/etc/fstab` to drop CIS options.
- **Risk:** Low-medium. DR ran clean.

### 3. `updates_apparmor`
- **Does:** `apt update` + `apt upgrade: safe` + installs apparmor + edits GRUB cmdline + enables AppArmor + `aa-enforce /etc/apparmor.d/*`.
- **Live impact:** apt upgrade 5-10 min/host (can restart services). `aa-enforce` flips all profiles from complain to enforce **immediately**. GRUB cmdline only effective on reboot.
- **Worst case:** Service restarted mid-upgrade AND/OR AppArmor blocks a misconfigured app.
- **Revert:**
  - `aa-complain /etc/apparmor.d/*` (puts profiles back in observe mode)
  - GRUB: `sed -i 's/apparmor=1 security=apparmor audit=1 audit_backlog_limit=[0-9]*/quiet splash/' /etc/default/grub && update-grub`
  - apt upgrade: **not safely revertable**. Downgrade a specific package with `apt install <pkg>=<old-version>` only if needed.
- **Risk:** Medium. apt upgrade is the biggest unknown.

### 4. `process_hardening`
- **Does:** chmod `/boot/grub/grub.cfg` 0600 + purges `prelink` + writes `/etc/sysctl.d/60-cis.conf` + writes `/etc/security/limits.d/99-cis-nocore.conf` + writes `/etc/systemd/coredump.conf.d/99-cis.conf`.
- **Live impact:** `sysctl --system` handler fires — applies all CIS sysctl values to running kernel immediately. On k3s, `99-k3s-overrides.conf` protects (`ip_forward=1` retained). On non-k3s, `ip_forward=0`, `rp_filter=1`, etc.
- **Worst case:** Multi-homed host that relied on `accept_redirects=1` loses traffic.
- **Revert:** `rm /etc/sysctl.d/60-cis.conf /etc/security/limits.d/99-cis-nocore.conf /etc/systemd/coredump.conf.d/99-cis.conf && sysctl --system`
- **Risk:** Low (k3s protected). Low for standard non-k3s hosts.

### 5. `services`
- **Does:** `apt remove --purge` of legacy packages (`autofs avahi-daemon bind9 cups dnsmasq dovecot-* isc-dhcp-server nfs-kernel-server nis rpcbind rsh-client rsync samba slapd snmpd squid talk telnet tftpd-hpa vsftpd xinetd ypserv prelink ldap-utils ftp`). Installs chrony. Stops timesyncd. Configures chrony with `cis_ntp_servers`. Chmods cron dirs to 0700. Creates `/etc/cron.allow` (empty, root only). Removes `/etc/cron.deny`. Same for `at.allow` / `at.deny`.
- **Live impact:** Package removals are LIVE. If `rsync`, `snmpd`, `bind9` etc. are actually in use, they stop and get purged.
- **Worst case:** **Active production tool gets uninstalled.** `rsync` for backups is the most likely surprise.
- **Revert:**
  - `apt install -y <package>` for whichever ones you need back
  - Restore timesyncd: `systemctl stop chrony && systemctl enable --now systemd-timesyncd`
  - `rm /etc/cron.allow` to restore old behavior
- **Risk:** **HIGH if you don't audit first.** Run pre-check below.

### 6. `network`
- **Does:** Single task — runs `sysctl --system`. Just triggers reload of the sysctl files from `process_hardening`.
- **Live impact:** Same as process_hardening.
- **Worst case:** Same as process_hardening.
- **Revert:** Same as process_hardening.
- **Risk:** Low.

### 7. `firewall`
- **Does:** Installs UFW. Allows SSH. Default-deny incoming, default-allow outgoing. Loopback rules. Allows `cis_extra_allow_ports`. Enables UFW with logging.
- **Live impact:** **UFW immediately blocks every port not in the allow list.** Existing TCP connections survive (established state); new connections to non-allowed ports get dropped.
- **Worst case:** **`cis_extra_allow_ports` doesn't include all ports your apps use.** k3s API (6443), NodePort range (30000-32767), MySQL (3306), Mongo (27017), Rabbit (5672/15672), ProxySQL (6033/6032), HAProxy bindings, monitoring (9100/9090/3000), etc. — if not allowed, blocked.
- **Revert:** `ufw disable` (instantly returns to no-firewall state)
- **Risk:** **HIGHEST of all tags.** Audit `cis_extra_allow_ports` first (pre-check below).

### 8. `ssh`
- **Does:** Writes `/etc/ssh/sshd_config.d/99-cis.conf` (validated with `sshd -t -f %s` before written). Locks down ownership of sshd_config and host keys.
- **Live impact:** sshd reloaded (existing sessions survive). New sessions enforce: `LogLevel VERBOSE`, `PermitRootLogin no`, `MaxAuthTries 4`, `ClientAliveInterval 300`, `MaxSessions 4`, restricted Ciphers/MACs/KexAlgorithms, `AllowTcpForwarding no`.
- **Worst case:** Old SSH client refused (rare). Tunneling/port-forwarding blocked. Root SSH refused.
- **Revert:** `rm /etc/ssh/sshd_config.d/99-cis.conf && systemctl reload ssh`
- **Risk:** Low — modern SSH clients all support these ciphers.

### 9. `pam`
- **Does:** Installs `libpam-pwquality`. Writes `/etc/security/pwquality.conf` + `/etc/security/faillock.conf`. Runs `pam-auth-update --enable pwquality faillock faillock_notify`. Edits `/etc/login.defs` for `PASS_MAX_DAYS 365`, `PASS_MIN_DAYS 1`, `PASS_WARN_AGE 7`, `ENCRYPT_METHOD YESCRYPT`, `UMASK 027`.
- **Live impact:** New login attempts use new PAM stack. Failed logins lock account after 5 attempts.
- **Worst case:** Misconfigured PAM locks users out. DR has been running this for weeks without complaints.
- **Revert:** `pam-auth-update --disable pwquality faillock faillock_notify && rm /etc/security/pwquality.conf /etc/security/faillock.conf`
- **Risk:** Low — but keep a sudo session open as fallback.

### 10. `users`
- **Does:** Writes `/etc/profile.d/99-cis.sh` (`TMOUT=900` readonly, `umask 027`). Disables shells on system accounts (uid<1000 except root/ubuntu). Ensures root has GID 0. Sets home dirs to 0750.
- **Live impact:** New shells get 15-min idle timeout, umask 027. System accounts with login shells get switched to `/usr/sbin/nologin`.
- **Worst case:** Service using system account's shell breaks (e.g., a `git` user running git-shell). Role excludes `ubuntu`.
- **Revert:**
  - `rm /etc/profile.d/99-cis.sh`
  - For affected system accounts: `usermod -s <original-shell> <user>`
- **Risk:** Low-medium. Audit system users first (pre-check below).

### 11. `logging_audit`
- **Does:** Installs rsyslog + auditd. Enables both. Writes `/etc/systemd/journald.conf.d/99-cis.conf` (Storage=persistent, Compress=yes, **ForwardToSyslog=no** — fixed regression). Configures `/etc/audit/auditd.conf`. Deploys `/etc/audit/rules.d/99-cis.rules`. Installs AIDE. Writes `/etc/aide/aide.conf.d/99_cis_exclusions` (k3s volatile path excludes). **Runs `aideinit` async, up to 2 hours.** Schedules daily AIDE check via `/etc/cron.d/aide`.
- **Live impact:** journald restarted. auditd starts logging per CIS rules. **AIDE async init runs 30 min – 2 hours, heavy disk I/O.**
- **Worst case:** AIDE init slows the host (especially DBs) during its run.
- **Revert:**
  - `systemctl stop auditd && systemctl disable auditd && rm /etc/audit/rules.d/99-cis.rules`
  - `rm /etc/systemd/journald.conf.d/99-cis.conf && systemctl restart systemd-journald`
  - `pkill aide` if running
  - `rm /etc/cron.d/aide`
- **Risk:** Medium-high during apply (AIDE load). Apply this LAST so the 2-hour observation period catches any slowness.

### 12. `file_perms`
- **Does:** chmod `/etc/passwd`, `/etc/group` (+ backups) to 0644 root:root. `/etc/shadow`, `/etc/gshadow` (+ backups) to 0640 root:shadow. `/etc/security/opasswd` to 0600. Recursive `chmod g-w,o-rwx` on `/var/log` dirs, `g-wx,o-rwx` on files.
- **Live impact:** Permissions changed immediately.
- **Worst case:** Log-shipping agents (fluentd, filebeat, etc.) running as non-root non-adm-group users lose read access to /var/log.
- **Revert:**
  - `find /var/log -type d -exec chmod g+w,o+rx {} +; find /var/log -type f -exec chmod o+r {} +` (rough restore)
  - Other files: leave them, original Ubuntu perms ≈ what we set.
- **Risk:** Low (DR validated) but most likely silent failure mode.

---

## Pre-apply checklist (run BEFORE T-2hr)

```bash
# 1. Verify cis_extra_allow_ports covers everything listening on prod
for ip in 172.16.102.10 172.16.102.13 172.16.102.20 172.16.102.30; do
  echo "=== $ip ==="
  ssh -i ~/Documents/clicque/leet-clicque-key.pem ubuntu@$ip \
    "sudo ss -tlnp | awk 'NR>1 {print \$4}' | awk -F: '{print \$NF}' | sort -u"
done

# 2. Check for "legacy" packages that services tag will remove
for ip in 172.16.102.10 172.16.102.13 172.16.102.20 172.16.102.30; do
  echo "=== $ip ==="
  ssh -i ~/Documents/clicque/leet-clicque-key.pem ubuntu@$ip \
    "dpkg -l | awk '/^ii/ {print \$2}' | grep -E '^(autofs|avahi-daemon|bind9|cups|dnsmasq|isc-dhcp-server|nfs-kernel-server|nis|rpcbind|rsh-client|rsync|samba|slapd|snmpd|squid|talk|telnet|tftpd-hpa|vsftpd|xinetd|ypserv)$'"
done

# 3. Audit system accounts with login shells
for ip in 172.16.102.13 172.16.102.20 172.16.102.30; do
  echo "=== $ip ==="
  ssh -i ~/Documents/clicque/leet-clicque-key.pem ubuntu@$ip \
    "awk -F: '(\$3<1000)&&(\$1!=\"root\")&&(\$7!=\"/usr/sbin/nologin\")&&(\$7!=\"/bin/false\")&&(\$7!=\"/sbin/nologin\"){print \$1\":\"\$7}' /etc/passwd"
done
```

---

## Recommended tag-application order (NOT alphabetical)

1. `ssh` — small, validated, safe. Confirms pipeline works.
2. `pam` — moderate. Keep sudo session open.
3. `users` — moderate.
4. `process_hardening` + `network` — sysctl applies live (k3s protected).
5. `kernel_modules` — module operations.
6. `mount_options` — remounts.
7. `services` — package removals (after pre-check).
8. `firewall` — UFW enable. After this, traffic should still flow if allow ports are right.
9. `updates_apparmor` — apt upgrade is longest, AppArmor enforces here.
10. `file_perms` — quick chmod sweep.
11. `logging_audit` — last because AIDE async runs 1-2 hours and you want it during observation.

Total: ~30-40 min apply phase.

---

## Execution command (T-2hr)

```bash
cd ~/Documents/clicque/hardening-ubuntu-CIS

TIERS=(haproxy proxysql mongo_rabbit mysql k3s_workers k3s_masters minio lisabackend_prod monitoring)
TAG_ORDER='ssh,pam,users,process_hardening,network,kernel_modules,mount_options,services,firewall,updates_apparmor,file_perms,logging_audit'

for TIER in "${TIERS[@]}"; do
  echo
  echo "============================================================"
  echo " Tier: $TIER  —  Applying 12 tags"
  echo "============================================================"
  ansible-playbook -i inventories/prod.ini site.yml \
    --limit "$TIER" \
    --tags "$TAG_ORDER" \
    --ask-vault-pass 2>&1 | tee /tmp/prewindow-${TIER}.log | tail -15
  echo
  echo "↑ Tier $TIER done. Pausing 30s."
  sleep 30
done

# Fleet-wide health check
ansible -i inventories/prod.ini prod \
  -m shell -a 'systemctl --failed --no-legend' \
  --ask-vault-pass --become
```

---

## Observation period (T-2hr to T-25min, ~95 min)

Check periodically:

```bash
# Failed services across the fleet
ansible -i inventories/prod.ini prod \
  -m shell -a 'systemctl --failed --no-legend' \
  --ask-vault-pass --become

# Recent journal errors
ansible -i inventories/prod.ini prod \
  -m shell -a 'journalctl --since "5 min ago" -p err --no-pager | tail -3' \
  --ask-vault-pass --become

# AIDE init status
ansible -i inventories/prod.ini prod \
  -m shell -a 'pgrep -af aide | head -2' \
  --ask-vault-pass --become
```

Watch your monitoring dashboards (Grafana/Prometheus) and central log collector for anomalies.

---

## T-25 min — go/no-go decision

GO if: all hosts reachable, no NEW failed services, no active incidents reported.
NO-GO if: anything's wrong. Run revert (next section) and reschedule.

---

## REVERT PLAN

See `revert-cis-hardening.yml` in this directory. Run with:

```bash
# Single host (preferred — narrow blast radius)
ansible-playbook -i inventories/prod.ini revert-cis-hardening.yml \
  --limit prod-mysql-01 --ask-vault-pass

# Single tier
ansible-playbook -i inventories/prod.ini revert-cis-hardening.yml \
  --limit mysql --ask-vault-pass

# Entire prod fleet (only if widespread issue)
ansible-playbook -i inventories/prod.ini revert-cis-hardening.yml \
  --limit prod --ask-vault-pass

# Then verify cluster health
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass
```

### What revert DOES NOT undo

- **apt upgrade** packages — to downgrade a specific package: `apt install <pkg>=<previous-version>`
- **AIDE init that's already running** — wait for it to finish, then disable cron.d/aide
- **Already-removed packages** (services tag) — must reinstall manually: `apt install -y rsync` etc.
- **Module unloads** — can re-modprobe if module not in use

Last updated: May 28, 2026.
