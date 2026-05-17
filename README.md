# HKL CIS Benchmark Hardening

Ansible-based CIS Ubuntu 24.04 L1 Server hardening for Hospital Kuala Lumpur (HKL) fleet — DR and production, with HA reboot orchestration and verification gates.

## What this repo does

- Applies CIS L1 Server hardening (~408 SSG rules) across an HA Ubuntu fleet.
- Tier-serial reboot orchestration that preserves cluster quorum (etcd, MySQL Group Replication, MongoDB rs0, RabbitMQ).
- Pre- and post-reboot verification gates that fail-closed on the Apr 20 ip_forward failure mode.
- OpenSCAP scan playbook for compliance evidence.

## Status

- **DR (18 hosts):** hardened + rebooted Apr 22-23, 2026. ~165 → ~300 rules passing per host (+135). Stable.
- **Production (22 hosts):** pending. All prep work in place. Awaiting maintenance window.
- **Round-2 hardening:** 19 NetAssist-flagged rules deferred for a future window.

## Quick start (resuming work / new contributor / new AI chat)

**Read [`PROJECT-HANDOVER.md`](./PROJECT-HANDOVER.md) first.** It contains the full context: fleet topology, incident history, all technical decisions, current state, and execution plans. Don't skip it.

If you're an AI assistant picking this up in a new chat, paste the contents of `PROJECT-HANDOVER.md` as your starting context.

## Repository structure

```
deliverables/ansible/
├── site.yml                     # Top-level: apply cis_hardening role
├── preflight-check.yml          # Cluster health gate
├── preflight-ip-forward.yml     # Per-host ip_forward validation gate
├── reboot-ha.yml                # Tier-serial reboot with quorum waits
├── apply-k3s-overrides.yml      # Deploys 99-k3s-overrides.conf on k3s tier
├── openscap-scan.yml            # Compliance scan
├── inventories/                 # dr.ini, prod.ini, hkl.ini, canary.ini
├── group_vars/                  # all.yml, dr/, k3s_masters.yml, k3s_workers.yml
├── tasks/                       # tripwire.yml, check-k3s-pods.yml, post-reboot-k3s-gate.yml
└── roles/cis_hardening/         # 14 task files, defaults, templates, audit rules

# Top-level deliverables: email drafts, sync scripts, sample reports
```

## Tonight's execution sequence (if hospital approval lands)

```bash
cd deliverables/ansible

# Pre-window — verify prep state is intact (5 min)
for ip in 172.16.102.20 .21 .22 .23 .24 .25; do
  ssh ubuntu@172.16.102.${ip##*.} \
    "ls /etc/sysctl.d/99-k3s-overrides.conf && cat /proc/sys/net/ipv4/ip_forward"
done

# 19:30 MYT — pre-stage role apply, per-tier (workaround for orchestration quirk)
for TIER in haproxy k3s_masters k3s_workers mongo_rabbit mysql proxysql monitoring minio lisabackend_prod; do
  ansible-playbook -i inventories/prod.ini site.yml --limit "$TIER" --ask-vault-pass
done

# 20:30 MYT — preflight gates
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass
ansible-playbook -i inventories/prod.ini preflight-ip-forward.yml -e target_env=prod

# 21:00 MYT — tier-serial reboot (T+40 tripwire enforced)
ansible-playbook -i inventories/prod.ini reboot-ha.yml \
  -e confirm_reboot=YES --ask-vault-pass

# 22:00 MYT — post-reboot validation
ansible-playbook -i inventories/prod.ini preflight-check.yml --ask-vault-pass

# Morning after — OpenSCAP compliance scan + re-enable apt-daily on mysql
ansible-playbook -i inventories/prod.ini openscap-scan.yml
for ip in 172.16.102.30 172.16.102.31 172.16.102.32; do
  ssh ubuntu@$ip "sudo systemctl unmask apt-daily.timer apt-daily-upgrade.timer && \
    sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer"
done
```

**Required for any reboot run:** include `localhost` in `--limit` and pass `-e confirm_reboot=YES`.

## The Apr 20 incident and why these gates exist

Applying the role wrote `ip_forward=0` on k3s nodes, breaking pod-to-pod networking. Cluster reported nodes Ready but ArgoCD NodePort went unreachable. Fix:

1. `/etc/sysctl.d/99-k3s-overrides.conf` sets `ip_forward=1` at higher lex priority than 60-cis.conf.
2. `preflight-ip-forward.yml` verifies the persisted state before reboot.
3. `tasks/post-reboot-k3s-gate.yml` verifies runtime ip_forward=1 after each k3s reboot, halts before uncordon on failure. Failure-injection tested May 13.

Without all three layers, the next role apply could repeat Apr 20. With them, the failure mode is contained to one host and explicitly surfaced.

## Reusability

The `cis_hardening` role is fully portable to other Ubuntu environments. To reuse on DigitalOcean / AWS EC2 / idcloudhost / bare metal:

1. Copy `roles/cis_hardening/` to your new project.
2. Update `cis_ntp_servers`, `cis_extra_allow_ports`, and inventory.
3. Skip the HA-specific files (`reboot-ha.yml`, `preflight-check.yml`) if you don't have an HA topology — use `ansible -m reboot -b` instead.

See section 9 of `PROJECT-HANDOVER.md` for the porting checklist.

## License

Internal HKL project. Not for redistribution.

## Maintainer

Mohamad Zulfikar
