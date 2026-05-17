# Apr 30 Prod Downtime — Revised Scope Confirmation

**To:** Hugh (DB DevOps), Platform DevOps, HIS App Team, Clinical Ops
**From:** Zul (Security / Hardening)
**Date:** 2026-04-19
**Subject:** Apr 30 DC hardening + reboot — revised host count (26) and run-of-show

---

Hi team,

Following up on our chat about the Apr 30 prod downtime window. I owe you a correction on the host count and a few notes before we lock the window.

## 1. Corrected scope: 26 hosts (not 20)

After reconciling the vendor scan list against the DevOps service-role
document (verified 2026-04-19), the DC / production scope is **26 Ubuntu
hosts**, not 20. Breakdown:

| Tier              | Count | OS       | IPs (172.16.102.x) |
|-------------------|-------|----------|--------------------|
| Monitoring        | 1     | Ubuntu 24| .13                |
| HAProxy (edge)    | 2     | Ubuntu 24| .10, .11           |
| k3s masters       | 3     | Ubuntu 24| .20-.22            |
| k3s workers       | 3 (*) | Ubuntu 24| .23-.25            |
| MySQL (GR)        | 3     | Ubuntu 24| .30-.32            |
| ProxySQL          | 2     | Ubuntu 24| .33-.34            |
| Mongo + Rabbit    | 3     | Ubuntu 24| .36-.38            |
| MinIO             | 4     | **Ubuntu 22** | .40-.42, .44  |
| lisabackend (prod)| 1     | Ubuntu 24| .67                |
| stg-haproxy       | 2     | Ubuntu 24| .54, .55           |
| stg-lisabackend   | 1     | Ubuntu 24| .66                |
| dev-haproxy       | 1     | Ubuntu 24| .64                |
| **Total**         |**26** |          |                    |

(*) Pending drift audit this week — see §3.

VIP .35 (prod-proxysql-VIP) is a floating keepalived address, not a real
SSH host, so it's not in the count.

## 2. Why stg + dev are in the same window as prod

DevOps confirmed that **dev, stg, and prod share the same k3s cluster —
they differ only by namespace**. When we reboot prod-k3s-master/worker
nodes, dev and stg workloads on those nodes go down too. Splitting prod
vs stg/dev into different windows would be fiction.

The stg-haprox / dev-haproxy / lisabackend VMs are separate edge hosts
fronting that shared cluster, so we include them in the same change to
avoid a second outage later.

**Practical impact for comms:** please also notify dev and stg app
owners about the window — their workloads will be unavailable for the
same duration.

## 3. Drift audit in flight — possible +2 hosts

Legacy inventory (hkl.ini) lists 9 IPs that are NOT in the DevOps
service-role doc: `.26, .27, .45, .57, .58, .60, .61, .62, .63`.

Two of these (`.26`, `.27`) match the pattern we hit in DR, where k3s
workers 04 and 05 were hiding at the same octets on the 202.x subnet.
I'm running `kubectl get nodes -o wide` + ping sweep this week (target:
Apr 22) to confirm. If `.26` / `.27` turn out to be hidden prod k3s
workers, scope becomes **28 hosts**.

The other 7 IPs (.45, .57-.63) are most likely decommissioned, but I'll
confirm with DevOps before Apr 30.

## 4. Timing ask — 2-hour window

Based on the DR dress rehearsal runtime (full fleet hardened +
rebooted in rolling waves, tier-by-tier validation) I'm asking for a
**2-hour maintenance window** for the 26-host Apr 30 change:

- 0:00-0:15  Preflight snapshots + HAProxy confirmation + VIP check
- 0:15-0:45  Inner tiers (monitoring → k3s workers → k3s masters)
- 0:45-1:15  Data tiers (mongo/rabbit → proxysql → mysql → minio)
- 1:15-1:40  Edge + non-prod (haproxy → stg/dev)
- 1:40-2:00  Post-validation, smoke tests, handback

If the hard limit is 1h30m, I'd propose deferring the 4 Ubuntu 22 MinIO
hosts to a follow-up change (object storage is tolerant of rolling
reboots on a different day) — that brings the window down to 22 hosts
and fits comfortably in 90 minutes. Happy to discuss trade-offs.

## 5. Preconditions before the window opens

- [ ] DR dress rehearsal completed cleanly (target: Apr 21 or 22)
- [ ] Drift audit closed (target: Apr 22)
- [ ] Proxmox snapshots for all 26 hosts immediately prior
- [ ] HIS application team on standby for per-tier smoke tests
- [ ] MongoDB stretched-RS majority confirmed healthy (3 DR + 3 prod quorum)
- [ ] Change ticket approved

## 6. One open question for Hugh

For the MySQL Group Replication tier: do you want me to coordinate
`group_replication_set_as_primary` handoff during the rolling reboot,
or is your team driving that independently? Either is fine — just
want to avoid two people touching GR state at once.

Thanks,
Zul
