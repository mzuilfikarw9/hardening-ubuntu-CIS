# CIS L1 Server Hardening — Canary Report

**Date:** 2026-04-17
**Playbook:** `deliverables/ansible/site-offline.yml` (offline-safe subset)
**Operator:** Zul

## Canary hosts

| IP | OS | Role |
|---|---|---|
| 172.16.102.52 | Ubuntu 22.04.5 LTS | Canary — u22 |
| 172.16.102.51 | Ubuntu 24.04.3 LTS | Canary — u24 |

## Ansible run result

| Host | ok | changed | failed | unreachable | skipped |
|---|---|---|---|---|---|
| 172.16.102.51 (u24) | 46 | 15 | 0 | 0 | 4 |
| 172.16.102.52 (u22) | 43 | 2 | 0 | 0 | 4 |

`.52` shows fewer `changed` because the earlier partial run had already applied most tasks; this final run was mostly idempotent reconciliation. Both hosts finished `failed=0`.

## Why "offline-safe" subset

HKL's outbound apt path is currently blocked by a combination of internal DNS hijacking (172.16.102.254 returns wrong IPs for Ubuntu mirror hostnames) and a path-MTU black hole on the egress route. We confirmed both issues independently. Rather than fight the network layer, we pivoted to a subset of the CIS role that touches only file-system, config-file, and sysctl controls — no package installs, no `apt upgrade`. Everything that ran is deterministic and does not require a working mirror.

## Changes applied (by CIS section)

### 1.1.1 — Kernel module blocklist
Disabled via `/etc/modprobe.d/<mod>.conf` (install false + blacklist) and unloaded if active: `cramfs, freevxfs, hfs, hfsplus, jffs2, overlayfs, squashfs, udf, usb-storage, dccp, tipc, rds, sctp`.

### 1.1.2–1.1.6 — Mount options
Enforced `nosuid,nodev,noexec` on `/tmp`, `/dev/shm`; `nodev,nosuid` on `/home`, `/var`; `nodev,nosuid,noexec` on `/var/tmp`, `/var/log`, `/var/log/audit` where the mount point exists as a separate partition. `tmp.mount` unmasked so systemd mounts `/tmp` at boot.

### 1.5 — Process hardening (sysctl + coredumps)
Dropped `/etc/sysctl.d/60-cis.conf` with ASLR, suid dumpable off, yama ptrace scope 1, full network sysctl set (see 3.3 below). Dropped `/etc/security/limits.d/99-cis-nocore.conf` (`* hard core 0`) and `/etc/systemd/coredump.conf.d/99-cis.conf` (`Storage=none, ProcessSizeMax=0`). GRUB config forced to `0600`.

### 1.7 — Warning banners
Deployed authorized-use banner to `/etc/issue`, `/etc/issue.net`, `/etc/motd`.

### 3.3 — Network sysctl parameters
Applied via the same `60-cis.conf`:
`send_redirects=0, ip_forward=0, ipv6 forwarding=0, accept_source_route=0, accept_redirects=0, secure_redirects=0, log_martians=1, icmp_echo_ignore_broadcasts=1, icmp_ignore_bogus_error_responses=1, rp_filter=1, tcp_syncookies=1, ipv6 accept_ra=0`.

### 5.1 — SSH server hardening
Dropped `/etc/ssh/sshd_config.d/99-cis.conf` (validated with `sshd -t` before replacing):
`Protocol 2, LogLevel VERBOSE, X11Forwarding no, MaxAuthTries 4, IgnoreRhosts yes, HostbasedAuthentication no, PermitRootLogin no, PermitEmptyPasswords no, PermitUserEnvironment no, PasswordAuthentication no, KbdInteractiveAuthentication no`, hardened Ciphers/MACs/KexAlgorithms, `ClientAliveInterval 300 / CountMax 2, LoginGraceTime 60, Banner /etc/issue.net, UsePAM yes, AllowTcpForwarding no, MaxStartups 10:30:60, MaxSessions 4`. Locked `sshd_config` to `0600`; host keys to `0600` private / `0644` public. sshd reloaded successfully — SSH connectivity verified on both hosts post-change.

### 5.2 — Sudo defaults
`/etc/sudoers.d/99-cis` (validated with `visudo -c`):
`Defaults use_pty, Defaults logfile="/var/log/sudo.log", Defaults !visiblepw, Defaults timestamp_timeout=15`.

### 5.4 / 5.5 — User environment
`/etc/profile.d/99-cis.sh` sets `TMOUT=900` (readonly) and `umask 027`. System accounts (UID<1000, excluding root/ubuntu/nologin) set to `/usr/sbin/nologin`. Home dirs of regular users forced to `0750`.

### 7.1 — File permissions
`/etc/passwd{,-}`, `/etc/group{,-}` → `root:root 0644`. `/etc/shadow{,-}`, `/etc/gshadow{,-}` → `root:shadow 0640`. `/etc/security/opasswd` → `root:root 0600`. `/var/log` directories `g-w,o-rwx`; files `g-wx,o-rwx`.

## Intentionally skipped (offline mode)

| CIS | Control | Reason |
|---|---|---|
| 1.2.x | Package updates (`apt upgrade`) | Broken mirror path |
| 1.3.x | AIDE install | Requires apt |
| 2.2.x | chrony install and config | Requires apt |
| 3.5.x | ufw/nftables install + rules | Requires apt (if not pre-installed) |
| 5.3.x | PAM pwquality / faillock | Requires `libpam-pwquality` |
| 6.x | auditd rules + log shipping | Requires `auditd` package |

These will be applied once a working apt path (internal mirror or fixed DNS/PMTU) is in place.

## Verification — quick spot checks

```bash
# sysctl applied
ssh ubuntu@172.16.102.52 "sudo sysctl -a 2>/dev/null | grep -E 'randomize_va_space|suid_dumpable|ptrace_scope|rp_filter'"

# SSH CIS drop-in in effect
ssh ubuntu@172.16.102.52 "sudo sshd -T | grep -E 'permitrootlogin|maxauthtries|passwordauthentication|x11forwarding'"

# File perms
ssh ubuntu@172.16.102.52 "stat -c '%n %a %U:%G' /etc/shadow /etc/passwd /etc/ssh/sshd_config"

# Banners
ssh ubuntu@172.16.102.52 "head -1 /etc/issue /etc/issue.net /etc/motd"
```

## Next steps

1. **Reboot both canaries** to activate mount options and any sysctl that didn't hot-apply: `ansible -i inventories/canary.ini all -b -m reboot`.
2. **Run a scan post-reboot** — either the consultant's re-scan (authoritative against the 166 baseline) or a diagnostic SCAP scan once Docker is available on the Mac.
3. **Compare pass count** — target is +35 (166 → 201). If we hit or exceed it, proceed to fleet rollout.
4. **Fleet rollout** — apply the same `site-offline.yml` to the remaining 34 hosts in `serial: "25%"` batches with a rollback plan. Pair with a follow-up task to restore apt network so the full CIS set can be applied later.
