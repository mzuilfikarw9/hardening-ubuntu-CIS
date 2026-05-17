**Subject:** Apr 30 Prod Downtime Window — Plan

Hi Team,

Following up on today's chat about the Apr 30 prod downtime window. Wanted to confirm the plan on paper so we can lock it in.

**Apr 30, 2100-2230 MYT — combined scope:**

- Hugh: MySQL Database Assessment improvements on both DC and DR.
- Me: CIS L1 hardening + reboot across the 26 prod (DC) Ubuntu hosts (22 Ubuntu 24.04 + 4 Ubuntu 22.04 MinIO).
- Sequence: hardening applied to all 26 hosts in parallel up-front; non-stateful tiers rebooted together per-tier; stateful tiers (MySQL, Mongo, Rabbit) rebooted one host at a time; MySQL last, after Hugh's DC MySQL work is done.

Note: dev and stg workloads will also be impacted because they share the same k3s cluster as prod (different namespaces, same physical nodes) — please let those app owners know.

**Before Apr 30:**

- No hardening on prod before the window — confirmed.
- I'll run the full reboot runbook against our 16 DR hosts as internal validation, on a weekday before Apr 30 (target Apr 22, will confirm the day with the team). Zero prod impact. I'll share the output so we have evidence the playbook is safe before touching prod.
- Our DR rehearsal will complete before Hugh touches DR MySQL on Apr 30, so no sequencing conflict.

**Why the reboot is tier-aware (not just `reboot` everything at once):**

During a declared maintenance window, non-stateful hosts (HAProxy, ProxySQL, k3s, MinIO, monitoring, stg/dev edges) can safely reboot all-at-once within their tier — they recover cleanly. But the distributed databases (MySQL Group Replication, MongoDB stretched replica set, RabbitMQ cluster) have a real failure mode where rebooting all nodes simultaneously causes the cluster to fail to reform cleanly on boot, needing manual recovery that can take hours. For those three tiers we reboot one host at a time with a quorum check between each — cheap insurance against a long incident.

**Timing estimate — ~90 min total:**

- Hugh: MySQL improvements on DC + DR — 30-40 min if run in parallel across the two environments, 60-80 min if serial. Please confirm which.
- Phase 1 — Hardening apply (parallel across all 26 hosts, no reboot yet): ~15 min
- Phase 2 — Non-stateful reboot tiers, all-hosts-per-tier in parallel (HAProxy, ProxySQL, k3s workers, k3s masters, monitoring, MinIO, stg, dev, lisabackend), with tier-level health check between tiers: ~25 min
- Phase 3 — Stateful tiers, serial:1 per host with quorum waits (Mongo + Rabbit ~20 min, MySQL ~30 min). MySQL can only start after Hugh's DC MySQL work is done: ~50 min

Realistic total: ~90 min, fits inside 2100-2230.

**Sequence inside the window:**

- T+0: Hugh starts MySQL improvements on DC + DR. In parallel I start Phase 1 (hardening apply across all 26 prod hosts, no reboots yet).
- T+15: Phase 1 complete. Phase 2 starts — non-stateful reboot tiers running through.
- T+40: Phase 2 complete. Hugh's DC MySQL work complete (if parallel). Phase 3 starts — Mongo + Rabbit serial:1.
- T+60: Mongo + Rabbit done. MySQL tier starts — serial:1 reboot of 3 GR members, each waits for full GR quorum before next.
- T+90: Done. 30 min handback buffer to 2300.

**Safety brakes already in the playbook:**

- Preflight health check T-30 min. Any cluster red = abort, defer to next weekly window.
- T+40 reboot-progress tripwire: if behind schedule, Phase 3 defers rather than compressing per-host quorum waits.

**My questions:**

1. Is 2100-2230 MYT (1.5 hr) ok? If you need the buffer, 2100-2300 gives us 30 extra min.
2. Your MySQL work on Apr 30 — DC + DR in parallel (one 30-40 min block) or serial (60-80 min)? Affects my sequencing.
3. Anything else you want added to the preflight checks before Apr 30?

Happy to walk through the runbook on a short call if easier.

Thanks,
Zul
