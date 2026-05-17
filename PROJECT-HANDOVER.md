# HKL CIS Benchmark Hardening Project — Handover Summary

**Project:** Apply CIS Ubuntu 24.04 L1 Server Benchmark to Hospital Kuala Lumpur (HKL) fleet.
**Status as of May 13, 2026:** All prep work complete. Awaiting hospital approval for prod execution window tonight 21:00 MYT (fallback: Thu May 21).
**Repository:** Project files live at `/Users/mohamadzulfikar/Documents/Claude/Projects/CIS Benchmark/`. Ansible deliverables at `deliverables/ansible/`.

---

## 1. Context

- **Customer:** Hospital Kuala Lumpur (HKL), Malaysia. Internal subnet `172.16.x.x`.
- **You (Zul):** Engineer running the rollout. Based in Jakarta (WIB / UTC+7). Working with team incl. Hugh (DB/MySQL specialist) and the HKL CTO.
- **Original baseline:** A NetAssist (Daniel) Host Assessment scan in Jan 2026 flagged 85 failed rules on prod host `172.16.102.10` against CIS Ubuntu 24.04 L1 Server v1.0.0.
- **Goal:** Apply CIS L1 hardening across the entire HKL fleet (DR + prod), validate via OpenSCAP, hand back evidence to the CTO and customer.

## 2. Fleet topology

**DR — 172.16.202.0/24 (18 hosts, already hardened + rebooted Apr 22-23):**

| Tier | Count | IPs | Group name |
|---|---|---|---|
| haproxy | 2 | .10, .11 | `haproxy` |
| k3s_masters | 3 | .20, .21, .22 | `k3s_masters` |
| k3s_workers | 5 | .23, .24, .25, .26, .27 | `k3s_workers` |
| mysql | 3 | .30, .31, .32 | `mysql` |
| proxysql | 2 | .33, .34 | `proxysql` |
| mongo_rabbit | 3 | .36, .37, .38 | `mongo_rabbit` |

**Prod — 172.16.102.0/24 (22 hosts, in scope for the upcoming window):**

| Tier | Count | IPs | Group name |
|---|---|---|---|
| monitoring | 1 | .13 | `monitoring` |
| haproxy | 2 | .10, .11 | `haproxy` |
| k3s_masters | 3 | .20, .21, .22 | `k3s_masters` |
| k3s_workers | 3 | .23, .24, .25 | `k3s_workers` |
| mysql | 3 | .30, .31, .32 | `mysql` |
| proxysql | 2 | .33, .34 | `proxysql` |
| mongo_rabbit | 3 | .36, .37, .38 | `mongo_rabbit` |
| minio | 4 | (in prod.ini) | `minio` |
| lisabackend_prod | 1 | (in prod.ini) | `lisabackend_prod` |

`[prod:children]` group aggregates the above. `[dc:children]` additionally includes `staging` and `dev` (3 + 1 hosts).

Prod cluster: k3s `v1.33.6+k3s1` on masters and 2 workers; `v1.34.3+k3s1` on prod-k3s-worker-01 (minor drift, not blocking).

## 3. Key files in the project

```
deliverables/ansible/
├── ansible.cfg                          # ControlPersist=600s, retries=3, forks=10
├── site.yml                             # Runs cis_hardening role with serial:25%
├── site-offline.yml                     # Offline-mode variant
├── preflight-check.yml                  # Cluster health gate (read-only)
├── preflight-ip-forward.yml             # Pre-reboot ip_forward validation gate
├── reboot-ha.yml                        # Tier-serial reboot orchestrator
├── apply-k3s-overrides.yml              # Deploys 99-k3s-overrides.conf to k3s tier
├── persist-sysctl-k3s.yml               # Re-applies role's sysctl template to k3s
├── openscap-scan.yml                    # Runs OpenSCAP scan against fleet
├── test-ip-forward-gate.sh              # DR validation wrapper for preflight-ip-forward
├── files/
│   └── 99-k3s-overrides.conf            # The k3s sysctl override file
├── tasks/
│   ├── tripwire.yml                     # T+40 min cumulative stop check
│   ├── check-k3s-pods.yml               # Per-tier pod-health re-check
│   └── post-reboot-k3s-gate.yml         # Per-host post-reboot ip_forward gate
├── inventories/
│   ├── dr.ini                           # DR inventory (18 hosts)
│   ├── prod.ini                         # Prod inventory (22 hosts in [prod:children])
│   ├── hkl.ini                          # Legacy combined inventory (deprecated)
│   ├── canary.ini, canary-u24.ini       # Single-host test inventories
├── group_vars/
│   ├── all.yml                          # reboot_tripwire_minutes=40, etc.
│   ├── dr/main.yml                      # DR-specific (mongo_rs_expected=6, etc.)
│   ├── k3s_masters.yml                  # cis_sysctl_overrides (ip_forward=1) + skip_unload[overlayfs]
│   └── k3s_workers.yml                  # Same overrides as masters
└── roles/cis_hardening/
    ├── defaults/main.yml                # All tuneable variables
    ├── tasks/
    │   ├── main.yml                     # Role orchestrator with section-tagged includes
    │   ├── kernel_modules.yml           # modprobe blacklist + unload (skips overlayfs on k3s)
    │   ├── mount_options.yml            # Enforces nosuid/nodev/noexec on /tmp /dev/shm etc.
    │   ├── updates_apparmor.yml         # apt upgrade + AppArmor enable + enforce profiles
    │   ├── process_hardening.yml        # GRUB perms, prelink purge, sysctl drop-in, coredump
    │   ├── banners.yml                  # /etc/issue, /etc/issue.net, /etc/motd
    │   ├── services.yml                 # Remove legacy pkgs, chrony, secure cron
    │   ├── network.yml                  # Triggers sysctl --system
    │   ├── firewall.yml                 # UFW default-deny + loopback + allow rules
    │   ├── ssh.yml                      # sshd_config drop-in (99-cis.conf)
    │   ├── sudo.yml                     # Validated sudoers drop-in
    │   ├── pam.yml                      # pwquality, faillock, login.defs
    │   ├── users.yml                    # TMOUT, umask, system-user shells
    │   ├── logging_audit.yml            # rsyslog, auditd, AIDE (async init)
    │   └── file_perms.yml               # /etc/passwd, /etc/shadow, /var/log perms
    ├── templates/
    │   ├── 60-cis.conf.j2               # sysctl drop-in (base | combine(overrides))
    │   └── sshd_99_cis.conf.j2          # sshd_config drop-in
    ├── files/
    │   └── cis-audit.rules              # Auditd ruleset
    └── handlers/main.yml
```

## 4. The Apr 20 incident (most important to understand)

**What broke:** Applied `cis_hardening` role to DR. Role wrote `/etc/sysctl.d/60-cis.conf` with `net.ipv4.ip_forward=0` (CIS L1 default). After reboot, runtime came up with `ip_forward=0`. Pod-to-pod networking broke immediately. ArgoCD NodePort became unreachable cluster-wide.

**Why:** Kubernetes (any flavor — k3s/EKS/k8s) **requires** `ip_forward=1` for cross-node pod traffic. CIS 3.3.1 says it should be 0. The two are fundamentally incompatible on k3s tier.

**Fix:** A file at higher lex order than 60-cis.conf overrides it. Created `/etc/sysctl.d/99-k3s-overrides.conf` containing:

```
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
```

This file is deployed via `apply-k3s-overrides.yml`. The role's `cis_sysctl_overrides` mechanism in `group_vars/k3s_*.yml` was *supposed* to handle this, but does NOT apply correctly via the role (task #24 — root cause still unresolved). The `99-*.conf` workaround is what's actually keeping the cluster working.

**Status today:** All 6 prod k3s nodes (3 masters + 3 workers) have the override file in place (deployed Apr 30 10:13, verified intact May 13). DR k3s nodes have the same.

## 5. Safety mechanisms in place

Tier-serial reboot with multiple defense layers:

| Layer | What it does | Status |
|---|---|---|
| `99-k3s-overrides.conf` | Wins lex order over 60-cis.conf, keeps ip_forward=1 on k3s tier | Deployed ✓ |
| `preflight-check.yml` | Cluster-wide health gate (k3s, MySQL GR, Mongo rs0, Rabbit, ProxySQL, HAProxy) before reboot | Tested ✓ |
| `preflight-ip-forward.yml` | Per-host verification that effective persisted ip_forward = expected (1 on k3s, 0 elsewhere). Reads ALL `/etc/sysctl.d/*.conf` with last-lex-wins resolution | Validated on DR (18/18 GREEN) ✓ |
| `confirm_reboot=YES` | Required `-e` flag prevents accidental runs | Built-in ✓ |
| Safety-gate localhost play | Sets `reboot_run_start_epoch` for tripwire | Requires localhost in `--limit` ⚠️ |
| Tripwire (T+40 min) | Per-tier check that halts if cumulative time exceeds limit | Tested ✓ |
| `serial: 1` per tier | One k3s host at a time, quorum waits between | Tested on DR ✓ |
| **`post-reboot-k3s-gate.yml`** | After each k3s reboot: stat `99-*.conf` + check runtime ip_forward=1. Halts play before uncordon if either fails | **Validated May 13 via failure-injection on DR ✓** |

## 6. Window history

| Date | Event |
|---|---|
| Apr 17 | Baseline OpenSCAP scan on DR — ~165 rules passing per host out of 408 (SSG Ubuntu 24.04 profile) |
| Apr 20 | First DR hardening attempt — broke k3s NodePort (the incident above) |
| Apr 22-23 | DR rehearsal — 18 hosts rebooted cleanly in ~90 min. Net OpenSCAP rules-passing went from ~165 to ~300 per host (+135) |
| Apr 30 | Original prod window — **DEFERRED**. Conflict with Hugh's MySQL DC update timing + Zul motorcycle accident on evening. All prep work landed though |
| May 1 | Apologies-and-defer emails sent |
| May 7 | Backup window — didn't happen (validation work didn't get done in time) |
| May 13 (TODAY) | Awaiting hospital approval for tonight 21:00 MYT, fallback May 21 |

## 7. NetAssist vs OpenSCAP — the comparison the CTO might ask about

Both tools sit on the same upstream (CIS Ubuntu 24.04 L1 Server v1.0.0) but use different rule sets:

- **NetAssist** (Daniel's tool) checks **251 rules** per host. Single point-in-time, semi-manual, xlsx output. Used for the initial Jan 2026 assessment.
- **OpenSCAP with SSG profile** checks **408 rules** per host. Automated, repeatable, XCCDF/HTML/ARF output. What we use for ongoing compliance.

Same control families, different rule granularity. Of Daniel's 85 specific failed rules, our role remediates **~57 directly**, **7 are partial** (operator-config dependent), **19 are gaps** (post-Apr-30 backlog — task #36), and **1 was a regression** we fixed (`ForwardToSyslog=yes` → `no` in `logging_audit.yml`).

The "+135 rules per host" we report is against the SSG 408-rule baseline, not Daniel's 251-rule baseline. Apples-to-different-tree.

## 8. Critical environment details

- **SSH key:** `~/Documents/clicque/leet-clicque-key.pem`
- **SSH user:** `ubuntu` (all hosts)
- **Vault password:** `jakarta2026` (for `--ask-vault-pass` prompts)
- **MySQL GR expected members:** 3 per env (in `group_vars/{dr,prod}/main.yml`)
- **Mongo rs0:** stretched cluster, 6 expected members (3 DR + 3 prod), majority = 4
- **Time zone:** All windows are in **MYT (UTC+8)**. Zul is in WIB (UTC+7), so MYT = WIB + 1.
- **NTP source:** `172.16.102.254` (HKL internal gateway) — works from both DR and prod subnets.

## 9. Known issues / open items

| # | Item | Severity | Notes |
|---|---|---|---|
| 24 | `cis_sysctl_overrides` from group_vars doesn't apply via role's template | Medium | Workaround: 99-k3s-overrides.conf. Need root-cause investigation post-window |
| 33 | mysql-03 has a broken mysql-server package state | Low | Surfaced during DR rehearsal; doesn't affect MySQL service. Cleanup later |
| 39 | Re-enable apt-daily timers on prod mysql hosts AFTER window | Mandatory post-window | Currently masked on .30/.31/.32 since Apr 30 |
| 40 | Migrate MySQL vendor APT repo to `signed-by=` keyring | Medium | Fleet-wide NO_PUBKEY B7B3B788A8D3785C warning; cosmetic but should fix |
| 25 | Update DR rehearsal runbook with Apr 20-23 lessons | Low | Backlog |
| 17 | DR architecture reference document + diagram | Low | Backlog |
| 36 | Round-2 hardening pass — close the 19 NetAssist gaps | Medium | New maintenance window in May/June |
| 44 | Port `cis_hardening` to DigitalOcean droplets and idcloudhost VMs | Future | Post-HKL project, separate work |

## 10. Tonight's plan (if hospital approves)

Run sequence on prod, all from `deliverables/ansible/`:

```bash
cd ~/Documents/Claude/Projects/CIS\ Benchmark/deliverables/ansible

# === ~19:30 MYT — pre-stage role apply (no reboot, config-write only) ===
rm -f ~/.ssh/master-* ~/.ansible/cp/* 2>/dev/null   # clear stale ssh sockets
ansible-playbook -i inventories/prod.ini site.yml --ask-vault-pass

# === 20:30 MYT — preflight cluster health + ip_forward gate ===
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass
ansible-playbook -i inventories/prod.ini preflight-ip-forward.yml -e target_env=prod

# === 21:00 MYT — tier-serial reboot ===
ansible-playbook -i inventories/prod.ini reboot-ha.yml \
  -e confirm_reboot=YES \
  --ask-vault-pass

# === 22:00 MYT — post-reboot validation ===
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass

# === Next day — OpenSCAP scan for compliance evidence ===
ansible-playbook -i inventories/prod.ini openscap-scan.yml
```

**Note on `--limit`:** if running a single tier or single host, include `localhost` in the limit so the safety-gate play matches:

```bash
ansible-playbook -i inventories/prod.ini reboot-ha.yml \
  --limit "prod-k3s-worker-01,localhost" \
  --tags k3s-workers \
  -e confirm_reboot=YES \
  --ask-vault-pass
```

Otherwise the tripwire task fails with `HostVarsVars has no attribute 'reboot_run_start_epoch'` (lesson learned May 13).

## 11. Post-window required actions

**The morning after the prod window:**

```bash
# Re-enable apt-daily timers on prod mysql hosts (task #39)
for ip in 172.16.102.30 172.16.102.31 172.16.102.32; do
  ssh -i ~/Documents/clicque/leet-clicque-key.pem ubuntu@$ip \
    "sudo systemctl unmask apt-daily.timer apt-daily-upgrade.timer && \
     sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer && \
     systemctl is-active apt-daily.timer"
done

# Run OpenSCAP scan for compliance evidence
ansible-playbook -i inventories/prod.ini openscap-scan.yml

# Send CTO sign-off email (model on cto-dr-rehearsal-signoff-2026-04-23.md
# which is in the project root)
```

## 12. Communication style preferences

Zul prefers emails / messages that read naturally:

- Plain prose, not bullet-heavy
- Contractions OK (we're, it's)
- No AI tell-tale phrases ("delve", "leverage", "robust", "I hope this finds you well")
- Direct: state the decision, then the reason
- Email tone for the CTO is the same level you'd use peer-to-peer, slightly more formal than chat

Multiple email/announcement drafts exist in the project root as `.md` files:
- `cto-dr-rehearsal-signoff-2026-04-23.md` and `.docx`
- `apr30-defer-emails.md`
- `may01-postpone-emails.md`
- `may21-pre-stage-approach-email.md`
- `team-announcement-2026-04-30.md`
- `weekly-sync-results-summary-2026-04-24.md`
- `sync-script-2026-04-24.md`

Reuse the structure and tone of these for any new comms.

## 13. Key technical decisions and why

| Decision | Reason |
|---|---|
| Tier-serial reboot (`serial: 1`) rather than parallel | Hugh proposed parallel-per-tier for speed; not validated, k3s master parallel risks etcd quorum loss. Serial is the tested pattern from DR rehearsal |
| `99-k3s-overrides.conf` instead of fixing the role's `cis_sysctl_overrides` mechanism | The role's group_vars mechanism doesn't apply (task #24, root cause unknown). The 99-file workaround has been holding DR together for a week. Don't introduce a new pattern under time pressure |
| Option C — pre-stage role apply + reboot-only window | DR took 90 min for 18 hosts; prod's 22 hosts scale to ~100-110 min. 1-hour live window only fits the reboot phase. Pre-staging the role apply keeps business downtime at 1 hour |
| Mask apt-daily timers on prod mysql before window | Prevents `unattended-upgrades` from grabbing dpkg lock during role's apt operations (lesson from `dr-mysql-03` 40-day wedge). Re-enable post-window |
| Accept NO_PUBKEY warning on MySQL repo | Fleet-wide cosmetic warning, `apt-get update` still rc=0, doesn't block role. Proper fix in task #40 post-window |
| Run only k3s nodes when validating gate | The post-reboot k3s gate only runs for `k3s_workers` and `k3s_masters` tiers. Non-k3s tiers don't use it (they don't have an override file) |

## 14. What's been validated as of May 13

✅ Role applies cleanly on DR (rehearsal Apr 22-23)
✅ Reboot pattern works on DR (rehearsal Apr 22-23)
✅ OpenSCAP scan works (Apr 23 results in `deliverables/openscap/dr/`)
✅ k3s overrides deployed on prod (Apr 30, intact May 13)
✅ apt-daily timers masked on prod mysql (Apr 30, intact May 13)
✅ ip_forward preflight gate works (DR 18/18 GREEN, Apr 30)
✅ Post-reboot k3s gate works (DR failure-injection test, May 13)
✅ Ansible.cfg SSH keepalive holds across full role run (21/22 on dry-run Apr 30)

⏳ Final clean prod `--check --diff` dry-run with all 22 hosts (need to run today before tonight)

## 15. If you're a new AI picking this up

**Top three things to know:**

1. **The Apr 20 break was caused by ip_forward=0 on k3s. The fix is `99-k3s-overrides.conf` and it's already in place on prod. Don't undo it. Don't remove it. The post-reboot k3s gate will catch you if you accidentally do.**

2. **`--limit` with `reboot-ha.yml` must include `localhost`** — otherwise the safety-gate play skips and the tripwire task fails. Always: `--limit "<host>,localhost"`.

3. **Always pass `-e confirm_reboot=YES`** to `reboot-ha.yml`. There's an explicit confirmation gate at the top of the play that requires it.

**Style:** Match the tone of the existing email drafts in the project root. Zul will tell you if you're using too many AI words ("delve", "leverage", etc.). Be direct, decisive, and honest about uncertainty.

**On hardware:** Zul is on a personal MacBook, Documents folder. SSH key at `~/Documents/clicque/leet-clicque-key.pem`. Wifi from Indonesia, but the servers are in Malaysia. Some network blips during long SSH sessions are normal — ansible.cfg has been tuned to handle them (ControlPersist=600s).

**On schedule:** Zul is in Jakarta (WIB). MYT = WIB + 1. Hospital approvals can land same-day with short notice. Be ready to pivot the day's plan if approval doesn't come through.

---

**End of handover. Good luck.**
