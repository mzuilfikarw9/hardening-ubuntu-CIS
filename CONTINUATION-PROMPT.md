# Continuation prompt — paste this into a new AI chat

Copy everything between the `===` lines below and paste as the first message in a new chat session (Claude, GPT, Sonnet, whatever). The new AI will have full context to continue.

===

I'm continuing a CIS Ubuntu 24.04 L1 Server hardening project for Hospital Kuala Lumpur (HKL) — Malaysia. This message is the project state. Please read all of it before responding.

## My setup
- I'm Zul (Mohamad Zulfikar), engineer running this rollout
- Based in Jakarta (WIB, UTC+7). All maintenance windows are in MYT (UTC+8). MYT = WIB + 1
- Working with Hugh (DB/MySQL specialist) and the HKL CTO
- My laptop has the project at `/Users/mohamadzulfikar/Documents/Claude/Projects/CIS Benchmark/`
- SSH key: `~/Documents/clicque/leet-clicque-key.pem`, user: `ubuntu`
- Ansible vault password: `jakarta2026`
- GitHub repo: (will share URL once pushed)

## Project scope
Apply CIS Ubuntu 24.04 L1 Server Benchmark v1.0.0 to two environments:
- **DR (172.16.202.0/24, 18 hosts):** DONE, hardened + rebooted Apr 22-23, 2026
- **PROD (172.16.102.0/24, 22 hosts):** PENDING, awaiting maintenance window

Prod tiers: haproxy×2, k3s_masters×3, k3s_workers×3, mysql×3, proxysql×2, mongo_rabbit×3, monitoring×1, minio×4, lisabackend_prod×1.

## The Apr 20 incident — context for why all the safety gates exist
The `cis_hardening` role's default sysctl drop-in (`/etc/sysctl.d/60-cis.conf`) sets `net.ipv4.ip_forward=0` per CIS 3.3.1. But Kubernetes needs `ip_forward=1` or pod-to-pod traffic breaks. On Apr 20 we applied the role to DR, rebooted, and k3s NodePort + ArgoCD became unreachable cluster-wide.

The fix: `/etc/sysctl.d/99-k3s-overrides.conf` at higher lex order, contents:
```
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
```

This file is deployed to all 6 prod k3s nodes (Apr 30, verified intact May 13) and to all DR k3s nodes.

## Three rules — never break these
1. **Never remove `/etc/sysctl.d/99-k3s-overrides.conf`** from any k3s node.
2. **Always include `localhost` in `--limit`** when running `reboot-ha.yml`. Otherwise the safety-gate play skips and the tripwire task fails with `HostVarsVars has no attribute 'reboot_run_start_epoch'`.
3. **Always pass `-e confirm_reboot=YES`** to `reboot-ha.yml`. There's a confirmation gate at the top of the playbook.

## Safety mechanisms in place
- `99-k3s-overrides.conf` — k3s sysctl override (deployed)
- `preflight-check.yml` — cluster health gate (k3s, MySQL GR, Mongo rs0, Rabbit, ProxySQL, HAProxy)
- `preflight-ip-forward.yml` — per-host ip_forward verification, last-lex-wins resolution across all `/etc/sysctl.d/*.conf`. Validated on DR 18/18 GREEN
- `tasks/post-reboot-k3s-gate.yml` — fires after every k3s reboot, halts play before uncordon if `99-*.conf` missing OR runtime `ip_forward != 1`. Failure-injection tested on DR May 13, gate fired correctly
- T+40 min tripwire (defers remaining tiers if cumulative time exceeds limit)
- `serial: 1` per tier in reboot-ha.yml (one host at a time, with quorum waits)
- `confirm_reboot=YES` required
- ansible.cfg has `ControlPersist=600s` for SSH multiplex stability across long runs

## Key files (all under `deliverables/ansible/`)
```
ansible.cfg                   # tuned: ControlPersist=600s, forks=10, retries=3
site.yml                      # applies cis_hardening role, serial:25%
preflight-check.yml           # cluster health (read-only)
preflight-ip-forward.yml      # ip_forward gate (read-only)
reboot-ha.yml                 # tier-serial reboot orchestrator
apply-k3s-overrides.yml       # deploys 99-k3s-overrides.conf
openscap-scan.yml             # OpenSCAP compliance scan
files/99-k3s-overrides.conf   # the override file
tasks/tripwire.yml            # T+40 stop logic
tasks/post-reboot-k3s-gate.yml  # post-reboot safety gate
inventories/                  # dr.ini, prod.ini, hkl.ini
group_vars/                   # all.yml, dr/, k3s_masters.yml, k3s_workers.yml
roles/cis_hardening/          # the role (14 task files)
```

## Important orchestration lesson (May 13 dry-run)
Running `site.yml --limit prod` (all 22 hosts at once, `serial:25%`) hit a non-deterministic include_tasks resolution quirk: 6/22 hosts failed with "Could not find mount_options.yml at playbook path" even though the file exists in the role's tasks directory. The same hosts succeed when run isolated with `--limit <hostname>`.

**Workaround:** apply the role per-tier instead of all-at-once:
```bash
for TIER in haproxy k3s_masters k3s_workers mongo_rabbit mysql proxysql monitoring minio lisabackend_prod; do
  ansible-playbook -i inventories/prod.ini site.yml --limit "$TIER" --ask-vault-pass
done
```

This is the planned approach for the live prod window.

## Tonight's execution plan (if hospital approves; fallback Thu May 21)
```bash
cd ~/Documents/Claude/Projects/CIS\ Benchmark/deliverables/ansible

# Pre-window verification (5 min)
# 1. Override file still on all 6 prod k3s nodes
for ip in 172.16.102.20 172.16.102.21 172.16.102.22 172.16.102.23 172.16.102.24 172.16.102.25; do
  ssh -i ~/Documents/clicque/leet-clicque-key.pem ubuntu@$ip \
    "ls /etc/sysctl.d/99-k3s-overrides.conf && cat /proc/sys/net/ipv4/ip_forward"
done

# 19:30 MYT — pre-stage role apply (per-tier loop)
rm -f ~/.ssh/master-* ~/.ansible/cp/* 2>/dev/null
for TIER in haproxy k3s_masters k3s_workers mongo_rabbit mysql proxysql monitoring minio lisabackend_prod; do
  ansible-playbook -i inventories/prod.ini site.yml --limit "$TIER" --ask-vault-pass
done

# 20:30 MYT — preflight gates
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass
ansible-playbook -i inventories/prod.ini preflight-ip-forward.yml -e target_env=prod

# 21:00 MYT — tier-serial reboot (live, 60-70 min, T+40 tripwire)
ansible-playbook -i inventories/prod.ini reboot-ha.yml \
  -e confirm_reboot=YES --ask-vault-pass

# 22:00 MYT — post-reboot validation
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass
```

## Post-window required actions (the morning after)
```bash
# Re-enable apt-daily timers on prod mysql hosts (currently masked since Apr 30)
for ip in 172.16.102.30 172.16.102.31 172.16.102.32; do
  ssh -i ~/Documents/clicque/leet-clicque-key.pem ubuntu@$ip \
    "sudo systemctl unmask apt-daily.timer apt-daily-upgrade.timer && \
     sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer"
done

# OpenSCAP compliance scan for evidence
ansible-playbook -i inventories/prod.ini openscap-scan.yml

# Draft CTO sign-off email (model on existing email drafts in project root)
```

## Window history
- Apr 17: baseline OpenSCAP scan (~165/408 rules passing per DR host)
- Apr 20: first DR hardening — broke k3s NodePort. Fix: 99-k3s-overrides.conf
- Apr 22-23: DR rehearsal — 18 hosts rebooted clean, ~90 min, +135 rules passing per host
- Apr 30: original prod window DEFERRED (Hugh's MySQL DC update conflict + my motorcycle accident in evening)
- May 1: apology/defer emails sent
- May 7: backup window — didn't happen
- May 13 (TODAY): post-reboot k3s gate failure-injection test PASSED on DR. Awaiting hospital approval for tonight 21:00 MYT, fallback May 21

## NetAssist vs OpenSCAP — for if the CTO asks
- NetAssist (Daniel's tool, Jan 2026 baseline) = 251 rules, 85 failed on prod
- OpenSCAP SSG profile (what we use) = 408 rules
- Of Daniel's 85 failed rules: ~57 directly remediated by our role, 7 partial, 19 gaps (post-window backlog), 1 regression fixed (`ForwardToSyslog=yes` → `no`)
- "+135 rules per host" we report is against the SSG 408-rule baseline, NOT Daniel's 251-rule baseline. Apples-to-different-tree.

## Open / pending items
- Task #24: cis_sysctl_overrides from group_vars doesn't apply via role's template (root cause unresolved, 99-file workaround in place)
- Task #36: Round-2 hardening pass — close 19 NetAssist gaps (post-prod)
- Task #39: re-enable apt-daily timers on prod mysql AFTER window (mandatory)
- Task #40: Migrate MySQL APT repo to signed-by keyring (cosmetic NO_PUBKEY warning)
- Task #44: Port cis_hardening to DigitalOcean + idcloudhost (future, post-HKL)

## Communication style I prefer
Plain prose, contractions OK, no AI tell-tale phrases ("delve", "leverage", "robust", "I hope this finds you well"). Direct: state decision then reason. Multiple email drafts already exist in the project root (`cto-dr-rehearsal-signoff-2026-04-23.md`, `apr30-defer-emails.md`, `may01-postpone-emails.md`, etc.) — model new emails on those.

## What I need from you now
Help me [DESCRIBE WHAT YOU NEED]. Examples:
- "Walk me through executing tonight's window."
- "Hospital didn't approve — draft a defer email to the team for May 21."
- "Help me write the CTO sign-off after tonight's run."
- "We hit an issue with X — help me troubleshoot."
- "I want to port this to DigitalOcean — let's plan."

===

End of paste-able prompt. Replace the last line with your actual ask before sending.
