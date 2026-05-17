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
haproxy (.10/.11), k3s_masters (.20/.21/.22), k3s_workers (.23–.27), mysql (.30/.31/.32), proxysql (.33/.34), mongo_rabbit (.36/.37/.38).

**Prod — 172.16.102.0/24 (22 hosts in `[prod:children]`, in scope for the upcoming window):**
monitoring (.13), haproxy (.10/.11), k3s_masters (.20/.21/.22), k3s_workers (.23/.24/.25), mysql (.30/.31/.32), proxysql (.33/.34), mongo_rabbit (.36/.37/.38), minio ×4, lisabackend_prod ×1.

`[dc:children]` additionally includes staging (×3) and dev (×1) but those are out of scope for the current window.

## 3. The Apr 20 incident (most important to understand)

Applied `cis_hardening` role to DR. Role wrote `/etc/sysctl.d/60-cis.conf` with `net.ipv4.ip_forward=0` (CIS L1 default). After reboot, runtime came up with `ip_forward=0`. Pod-to-pod networking broke. ArgoCD NodePort unreachable.

**Why:** Kubernetes (any flavor) **requires** `ip_forward=1` for cross-node pod traffic. CIS 3.3.1 says it should be 0. The two are fundamentally incompatible on k3s tier.

**Fix:** `/etc/sysctl.d/99-k3s-overrides.conf` (higher lex order, wins over 60-cis.conf):

```
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
```

Deployed via `apply-k3s-overrides.yml` on all k3s nodes (DR + prod). The role's `cis_sysctl_overrides` mechanism in `group_vars/k3s_*.yml` was supposed to handle this but doesn't apply correctly (task #24, root cause unresolved). The 99-file workaround is what's actually keeping the cluster working.

**Status:** All 6 prod k3s nodes have the override file (deployed Apr 30 10:13, verified intact May 13). DR k3s nodes have the same.

## 4. Safety mechanisms in place

| Layer | What it does | Status |
|---|---|---|
| `99-k3s-overrides.conf` | Wins lex order over 60-cis.conf, keeps ip_forward=1 on k3s tier | Deployed ✓ |
| `preflight-check.yml` | Cluster-wide health gate before reboot (k3s, MySQL GR, Mongo rs0, Rabbit, ProxySQL, HAProxy) | Tested ✓ |
| `preflight-ip-forward.yml` | Per-host verification that effective persisted ip_forward = expected. Reads all `/etc/sysctl.d/*.conf` with last-lex-wins resolution | Validated on DR (18/18 GREEN) ✓ |
| `confirm_reboot=YES` | Required `-e` flag prevents accidental runs | Built-in ✓ |
| Safety-gate localhost play | Sets `reboot_run_start_epoch` for tripwire | Requires localhost in `--limit` ⚠️ |
| Tripwire (T+40 min) | Per-tier check that halts if cumulative time exceeds limit | Tested ✓ |
| `serial: 1` per tier | One k3s host at a time, quorum waits between | Tested on DR ✓ |
| `post-reboot-k3s-gate.yml` | After each k3s reboot: stat `99-*.conf` + check runtime ip_forward=1. Halts play before uncordon on failure | Validated May 13 via failure-injection on DR ✓ |

## 5. Window history

| Date | Event |
|---|---|
| Apr 17 | Baseline OpenSCAP — ~165/408 rules passing per host |
| Apr 20 | First DR hardening attempt — broke k3s NodePort |
| Apr 22-23 | DR rehearsal — 18 hosts rebooted cleanly in ~90 min. Net OpenSCAP went from ~165 to ~300 (+135 rules/host) |
| Apr 30 | Original prod window — DEFERRED. Hugh's MySQL DC update timing conflict + Zul motorcycle accident in evening. All prep work landed though |
| May 1 | Apology + defer emails sent |
| May 7 | Backup window — didn't happen |
| May 13 (TODAY) | Awaiting hospital approval for tonight 21:00 MYT, fallback May 21 |

## 6. Key file locations

```
deliverables/ansible/
├── ansible.cfg                          # ControlPersist=600s, retries=3, forks=10
├── site.yml                             # Runs cis_hardening role with serial:25%
├── preflight-check.yml                  # Cluster health gate (read-only)
├── preflight-ip-forward.yml             # Pre-reboot ip_forward gate
├── reboot-ha.yml                        # Tier-serial reboot orchestrator
├── apply-k3s-overrides.yml              # Deploys 99-k3s-overrides.conf
├── openscap-scan.yml                    # OpenSCAP scan
├── files/99-k3s-overrides.conf          # The k3s sysctl override file
├── tasks/
│   ├── tripwire.yml                     # T+40 min cumulative stop check
│   ├── check-k3s-pods.yml               # Per-tier pod-health re-check
│   └── post-reboot-k3s-gate.yml         # Per-host post-reboot ip_forward gate
├── inventories/                         # dr.ini, prod.ini, hkl.ini, canary.ini
├── group_vars/                          # all.yml, dr/, k3s_masters.yml, k3s_workers.yml
└── roles/cis_hardening/
    ├── defaults/main.yml                # Tuneable variables
    ├── tasks/                           # 14 task files
    ├── templates/                       # 60-cis.conf.j2, sshd_99_cis.conf.j2
    └── files/cis-audit.rules
```

## 7. Critical environment details

- **SSH key:** `~/Documents/clicque/leet-clicque-key.pem`
- **SSH user:** `ubuntu` (all hosts)
- **Vault password:** `jakarta2026`
- **Time zone:** All windows MYT (UTC+8). Zul is in WIB (UTC+7), so MYT = WIB + 1.
- **NTP source:** `172.16.102.254` (HKL internal gateway)
- **MySQL GR expected members:** 3 per env
- **Mongo rs0:** stretched cluster, 6 expected (3 DR + 3 prod), majority = 4

## 8. NetAssist vs OpenSCAP — the comparison the CTO might ask about

- **NetAssist** (Daniel's tool) checks **251 rules** per host. Point-in-time, xlsx output. Jan 2026 baseline.
- **OpenSCAP with SSG profile** checks **408 rules** per host. Automated, XCCDF/HTML output.

Same control families, different rule granularity. Of Daniel's 85 failed rules, our role remediates ~57 directly, 7 are partial (operator-config dependent), 19 are gaps (post-window backlog), and 1 was a regression we fixed (`ForwardToSyslog=yes` → `no`).

The "+135 rules per host" we report is against the SSG 408-rule baseline, not Daniel's 251-rule baseline.

## 9. Known issues / open items

| # | Item | Severity | Notes |
|---|---|---|---|
| 24 | `cis_sysctl_overrides` from group_vars doesn't apply via role's template | Medium | Workaround: 99-k3s-overrides.conf. Need root-cause investigation |
| 33 | mysql-03 broken mysql-server package state | Low | Doesn't affect service; cleanup later |
| 39 | Re-enable apt-daily timers on prod mysql hosts AFTER window | Mandatory post-window | Currently masked since Apr 30 |
| 40 | Migrate MySQL vendor APT repo to `signed-by=` keyring | Medium | Fleet-wide NO_PUBKEY warning; cosmetic |
| 36 | Round-2 hardening pass — close 19 NetAssist gaps | Medium | New maintenance window in May/June |
| 44 | Port `cis_hardening` to DigitalOcean / idcloudhost | Future | Post-HKL project |

## 10. Tonight's plan (if hospital approves)

```bash
cd ~/Documents/Claude/Projects/CIS\ Benchmark/deliverables/ansible

# === ~19:30 MYT — pre-stage role apply, PER-TIER (workaround for orchestration quirk) ===
rm -f ~/.ssh/master-* ~/.ansible/cp/* 2>/dev/null
for TIER in haproxy k3s_masters k3s_workers mongo_rabbit mysql proxysql monitoring minio lisabackend_prod; do
  ansible-playbook -i inventories/prod.ini site.yml --limit "$TIER" --ask-vault-pass
done

# === 20:30 MYT — preflight cluster health + ip_forward gate ===
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass
ansible-playbook -i inventories/prod.ini preflight-ip-forward.yml -e target_env=prod

# === 21:00 MYT — tier-serial reboot ===
ansible-playbook -i inventories/prod.ini reboot-ha.yml \
  -e confirm_reboot=YES --ask-vault-pass

# === 22:00 MYT — post-reboot validation ===
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass

# === Next day — OpenSCAP scan for compliance evidence ===
ansible-playbook -i inventories/prod.ini openscap-scan.yml
```

**Important:** If running `reboot-ha.yml` against any subset (single tier, single host), include `localhost` in the limit so the safety-gate play matches:

```bash
ansible-playbook -i inventories/prod.ini reboot-ha.yml \
  --limit "prod-k3s-worker-01,localhost" \
  --tags k3s-workers \
  -e confirm_reboot=YES --ask-vault-pass
```

Otherwise the tripwire task fails with `HostVarsVars has no attribute 'reboot_run_start_epoch'`.

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

# Draft CTO sign-off email (model on cto-dr-rehearsal-signoff-2026-04-23.md)
```

## 12. Communication style

Zul prefers emails/messages that read naturally: plain prose, contractions OK, no AI tell-tale phrases ("delve", "leverage", "robust", "I hope this finds you well"). Direct: state decision then reason. Multiple drafts exist in project root — model new emails on the existing tone.

## 13. Key technical decisions

| Decision | Reason |
|---|---|
| Tier-serial reboot (`serial: 1`) rather than parallel | Hugh proposed parallel; not validated, k3s master parallel risks etcd quorum loss |
| `99-k3s-overrides.conf` instead of fixing role's `cis_sysctl_overrides` mechanism | Role mechanism doesn't apply (task #24). 99-file workaround tested and working |
| Option C — pre-stage role apply + reboot-only window | DR took 90 min for 18 hosts; prod's 22 scale to ~100-110 min. 1-hour live window fits reboot phase only. Pre-staging earlier keeps business downtime at 1 hour |
| **Per-tier role apply** (not all-at-once) | Discovered May 13 dry-run: parallel `serial: 25%` run hits include_tasks resolution quirk on 6/22 hosts. Per-tier with `--limit` sidesteps it |
| Mask apt-daily timers on prod mysql before window | Prevents `unattended-upgrades` dpkg lock contention (lesson from dr-mysql-03 40-day wedge) |
| Accept NO_PUBKEY warning on MySQL repo | Fleet-wide cosmetic, `apt-get update` still rc=0. Proper fix is task #40 |

## 14. What's been validated as of May 13

✓ Role applies cleanly on DR (rehearsal Apr 22-23)
✓ Reboot pattern works on DR (rehearsal Apr 22-23)
✓ OpenSCAP scan works (Apr 23, results in `deliverables/openscap/dr/`)
✓ k3s overrides deployed on prod (Apr 30, intact May 13)
✓ apt-daily timers masked on prod mysql (Apr 30, intact May 13)
✓ ip_forward=1 at runtime on prod k3s (May 13 spot-check)
✓ preflight-ip-forward.yml validated on DR (18/18 GREEN, Apr 30)
✓ **post-reboot-k3s-gate validated via failure-injection on DR** (May 13)
✓ Ansible.cfg SSH keepalive holds across role run (21/22 dry-run Apr 30)
✓ Per-tier `site.yml` invocation works cleanly (verified May 13)

## 15. Three rules anyone working on this MUST follow

1. **Never remove `99-k3s-overrides.conf`** from any k3s node. It's the fix for the Apr 20 ip_forward break.
2. **Always include `localhost` in `--limit`** when running `reboot-ha.yml`. Otherwise the safety-gate play skips and the tripwire fails.
3. **Always pass `-e confirm_reboot=YES`** to `reboot-ha.yml`. Required confirmation gate.

---

**End of handover. Good luck.**
