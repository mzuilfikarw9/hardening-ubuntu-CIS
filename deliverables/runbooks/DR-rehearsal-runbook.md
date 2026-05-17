# DR Reboot Dress Rehearsal — Runbook

**Target date:** Apr 21 or Apr 22, 2026 (weekday, outside peak DR-observer hours)
**Duration budget:** 75 min rehearsal window + 30 min buffer = 105 min total
**Scope:** 16 DR hosts on 172.16.202.0/24
**Purpose:** Validate the full hardening + HA-safe reboot pipeline end-to-end before the Apr 30 prod cutover. Capture real per-tier timings to replace estimates. Prove preflight, quorum waits, and per-tier health checks behave as designed.

---

## 1. Pre-rehearsal checklist

### T-24h (day before)

- [ ] Change ticket filed for the DR rehearsal window (even though prod isn't touched, a ticket creates the audit trail).
- [ ] Notify DevOps + DB team of the rehearsal date/time. No user-facing announcement needed — DR has no users.
- [ ] Confirm Proxmox snapshots ENABLED for all 16 DR hosts (see host list §2).
- [ ] Confirm Hugh isn't running any DR MySQL work during the rehearsal window.
- [ ] `git pull` on the Ansible repo, confirm you're on the commit that will run against prod on Apr 30.
- [ ] Run `ansible-playbook -i inventories/dr.ini site.yml --check --diff` (dry-run). Zero unexpected changes expected.

### T-1h

- [ ] SSH connectivity check:
      `ansible -i inventories/dr.ini dr -m ping`
      All 16 must return `pong`. Any host that fails → resolve BEFORE starting.
- [ ] Time-sync check:
      `ansible -i inventories/dr.ini dr -m shell -a "timedatectl status | grep 'System clock synchronized'"`
      Expect `yes` on all 16.
- [ ] Proxmox snapshot taken for all 16 hosts, named `pre-dr-rehearsal-20260421` (adjust date). Record snapshot IDs in §9.
- [ ] `kubectl --kubeconfig ~/.kube/dr-config get nodes -o wide` — all 5 DR k3s nodes (masters + workers) Ready.
- [ ] MySQL GR health check — all 3 DR members ONLINE:
      ```sql
      SELECT MEMBER_ID, MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE
      FROM performance_schema.replication_group_members;
      ```
- [ ] MongoDB stretched RS health — expect 6 members, 1 PRIMARY, 5 SECONDARY, 0 STARTUP/RECOVERING:
      `mongosh --eval 'rs.status()' | grep -E "name|stateStr"`
- [ ] RabbitMQ cluster health — all 3 DR nodes running, no partitions:
      `ansible -i inventories/dr.ini mongo_rabbit -m shell -a "rabbitmqctl cluster_status"`

### T-15min

- [ ] Open `tmux` / `screen` on control node — rehearsal runs for 75+ min, don't rely on a flaky SSH session.
- [ ] Start wall-clock log: `script -q dr-rehearsal-$(date +%Y%m%d-%H%M).log`
- [ ] Open timing capture sheet (§9) — ready to record start/end per tier.
- [ ] Confirm no one else is SSH'd into any DR host:
      `ansible -i inventories/dr.ini dr -m shell -a "who"`
- [ ] Final go/no-go read-through of §5 abort criteria.

---

## 2. Host list (16 DR hosts)

| Tier            | Hosts                                    | IPs                    | Phase |
|-----------------|------------------------------------------|------------------------|-------|
| haproxy         | dr-haprox-01, dr-haprox-02               | .10, .11               | 2     |
| k3s_masters     | dr-k3s-master-01/02/03                   | .20, .21, .22          | 2     |
| k3s_workers     | dr-k3s-worker-01/02/03/04/05             | .23, .24, .25, .26, .27| 2     |
| mysql           | dr-mysql-01/02/03                        | .30, .31, .32          | 3     |
| proxysql        | dr-proxysql-01, dr-proxysql-02           | .33, .34               | 2     |
| mongo_rabbit    | dr-mongo-rabbit-01/02/03                 | .36, .37, .38          | 3     |

VIPs (not in scope, but monitor during rehearsal):
- `.12` — haproxy keepalived VIP
- `.35` — proxysql keepalived VIP

---

## 3. Phase 1 — Hardening apply (parallel, all 16 hosts)

**Budget: 15 min**

### Run

```bash
cd ~/Documents/Claude/Projects/CIS\ Benchmark/deliverables/ansible
ansible-playbook -i inventories/dr.ini site.yml \
    --tags hardening \
    --diff \
    2>&1 | ts '[%H:%M:%S]' | tee -a dr-rehearsal-phase1.log
```

### Success criteria

- PLAY RECAP shows `unreachable=0 failed=0` for all 16 hosts.
- No more than 2 hosts with `changed=0` (means already hardened from previous run — fine).
- Expected `changed` count per fresh host: 80-110 tasks.
- Total wall-clock time: record in §9.

### Abort if

- Any host becomes `unreachable` and doesn't recover within 2 min.
- More than 3 hosts show `failed > 0` — indicates systemic role issue, not drift.
- Phase exceeds 25 min (167% of budget) → stop, investigate what's slow before proceeding to Phase 2.

---

## 4. Phase 2 — Non-stateful reboot tiers (parallel within tier)

**Budget: 25 min**

Tier order: monitoring (n/a in DR) → k3s_workers → k3s_masters → proxysql → haproxy.

In DR we skip monitoring (DR has no dedicated monitoring host — prod observer watches DR).

### 4.1 k3s workers — 5 hosts in parallel

```bash
START=$(date +%s)
ansible-playbook -i inventories/dr.ini reboot-ha.yml \
    --limit k3s_workers \
    -e reboot_strategy=tier_parallel \
    2>&1 | ts '[%H:%M:%S]' | tee -a dr-rehearsal-phase2-k3sworkers.log
echo "k3s_workers elapsed: $(($(date +%s) - START))s"
```

**Validation (run ON a k3s master, not from control node):**

```bash
ssh ubuntu@172.16.202.20 "kubectl get nodes -o wide"
```

Expected: all 5 workers `STATUS=Ready`, `VERSION` unchanged, `OS-IMAGE` unchanged. Age column resets to `<5m` for the rebooted nodes.

**Pod rescheduling check:**

```bash
ssh ubuntu@172.16.202.20 "kubectl get pods -A -o wide | grep -v Running | grep -v Completed"
```

Expected output: empty (or only `Terminating` pods that will clear within 60s).

### 4.2 k3s masters — 3 hosts in parallel

```bash
START=$(date +%s)
ansible-playbook -i inventories/dr.ini reboot-ha.yml \
    --limit k3s_masters \
    -e reboot_strategy=tier_parallel \
    2>&1 | ts '[%H:%M:%S]' | tee -a dr-rehearsal-phase2-k3smasters.log
echo "k3s_masters elapsed: $(($(date +%s) - START))s"
```

**Validation:**

```bash
# From your Mac:
ssh ubuntu@172.16.202.20 "kubectl get nodes"
ssh ubuntu@172.16.202.20 "kubectl get componentstatuses"   # scheduler + controller-manager healthy
ssh ubuntu@172.16.202.20 "sudo k3s etcd-snapshot ls | head -5"  # etcd responsive
```

Expected: all 3 masters Ready, scheduler/controller-manager Healthy, etcd responds.

### 4.3 ProxySQL — 2 hosts in parallel

```bash
START=$(date +%s)
ansible-playbook -i inventories/dr.ini reboot-ha.yml \
    --limit proxysql \
    -e reboot_strategy=tier_parallel \
    2>&1 | ts '[%H:%M:%S]' | tee -a dr-rehearsal-phase2-proxysql.log
echo "proxysql elapsed: $(($(date +%s) - START))s"
```

**Validation:**

```bash
# Verify both proxysql processes responding:
ansible -i inventories/dr.ini proxysql -m shell -a "systemctl is-active proxysql"

# Verify VIP .35 is held by exactly one node:
ansible -i inventories/dr.ini proxysql -m shell -a "ip -4 addr | grep -c 172.16.202.35"
# Expected: 1 host returns "1", 1 host returns "0" (total should be exactly 1).

# Verify backend MySQL hosts still visible from proxysql:
ssh ubuntu@172.16.202.33 "mysql -h 127.0.0.1 -P 6032 -u admin -p\$PROXYSQL_ADMIN_PASS \
    -e 'SELECT hostgroup_id, hostname, status FROM runtime_mysql_servers;'"
```

Expected: both proxysql `active`, VIP held by exactly one node, all 3 MySQL backends `ONLINE`.

### 4.4 HAProxy — 2 hosts in parallel

```bash
START=$(date +%s)
ansible-playbook -i inventories/dr.ini reboot-ha.yml \
    --limit haproxy \
    -e reboot_strategy=tier_parallel \
    2>&1 | ts '[%H:%M:%S]' | tee -a dr-rehearsal-phase2-haproxy.log
echo "haproxy elapsed: $(($(date +%s) - START))s"
```

**Validation:**

```bash
# VIP .12 should be held by exactly one node:
ansible -i inventories/dr.ini haproxy -m shell -a "ip -4 addr | grep -c 172.16.202.12"
# Expected sum = 1 across both hosts.

# HAProxy stats socket responds:
ansible -i inventories/dr.ini haproxy -m shell -a \
    "echo 'show info' | sudo socat - /run/haproxy/admin.sock | head -5"

# Backend pools healthy:
ansible -i inventories/dr.ini haproxy -m shell -a \
    "echo 'show stat' | sudo socat - /run/haproxy/admin.sock | awk -F, '\$2==\"BACKEND\" {print \$1, \$18}'"
# Expected: every BACKEND line ends with UP.
```

### Phase 2 overall abort criteria

- Any tier exceeds 200% of its individual budget.
- Any tier leaves a host in NotReady / failed / VIP-orphaned state for more than 3 min post-reboot.
- `kubectl get nodes` shows more than 1 NotReady at the end of Phase 2 (cluster shouldn't be degraded after workers + masters rebooted).

---

## 5. Phase 3 — Stateful reboot tiers (serial:1, quorum-gated)

**Budget: 35 min (10 min RabbitMQ + 10 min MongoDB + 15 min MySQL GR)**

### 5.1 RabbitMQ + MongoDB — serial:1 on mongo_rabbit tier

These hosts co-locate Mongo + Rabbit. Playbook reboots one host, waits for BOTH Mongo and Rabbit to rejoin cluster before next host.

```bash
START=$(date +%s)
ansible-playbook -i inventories/dr.ini reboot-ha.yml \
    --limit mongo_rabbit \
    -e reboot_strategy=serial_one \
    2>&1 | ts '[%H:%M:%S]' | tee -a dr-rehearsal-phase3-mongorabbit.log
echo "mongo_rabbit elapsed: $(($(date +%s) - START))s"
```

**Validation after each host (playbook does this internally — spot-check too):**

MongoDB RS:
```bash
ssh ubuntu@172.16.202.36 'mongosh --quiet --eval "
  rs.status().members.map(m => ({name: m.name, state: m.stateStr, health: m.health}))
"'
```
Expected: 6 members total (3 DC + 3 DR), exactly 1 PRIMARY, 5 SECONDARY, health=1 for all.

**ABORT condition:** any member stuck in STARTUP2 / RECOVERING / ROLLBACK for > 2 min.

RabbitMQ:
```bash
ssh ubuntu@172.16.202.36 "sudo rabbitmqctl cluster_status --formatter json" \
  | jq '{running: .running_nodes, partitions: .partitions}'
```
Expected: 3 running_nodes, empty partitions array.

**ABORT condition:** partitions array is non-empty → Rabbit split-brain. Stop, do not reboot next host.

### 5.2 MySQL GR — serial:1 with full-quorum wait

```bash
START=$(date +%s)
ansible-playbook -i inventories/dr.ini reboot-ha.yml \
    --limit mysql \
    -e reboot_strategy=serial_one \
    -e mysql_wait_for_online=true \
    2>&1 | ts '[%H:%M:%S]' | tee -a dr-rehearsal-phase3-mysql.log
echo "mysql elapsed: $(($(date +%s) - START))s"
```

**Validation after each host:**

```bash
ssh ubuntu@172.16.202.30 'mysql -u root -p$MYSQL_ROOT_PASS -e "
  SELECT MEMBER_HOST, MEMBER_STATE, MEMBER_ROLE
  FROM performance_schema.replication_group_members
  ORDER BY MEMBER_ROLE DESC, MEMBER_HOST;
"'
```

Expected after rejoin of each member:
```
+---------------+--------------+-------------+
| MEMBER_HOST   | MEMBER_STATE | MEMBER_ROLE |
+---------------+--------------+-------------+
| dr-mysql-01   | ONLINE       | PRIMARY     |  <-- or SECONDARY
| dr-mysql-02   | ONLINE       | SECONDARY   |
| dr-mysql-03   | ONLINE       | SECONDARY   |
+---------------+--------------+-------------+
```

All 3 members ONLINE. Exactly 1 PRIMARY. No RECOVERING, no OFFLINE, no ERROR.

**ABORT conditions:**

- Any member stays RECOVERING > 3 min after reboot.
- Any member reports MEMBER_STATE=ERROR.
- PRIMARY election fails (all members SECONDARY) — shouldn't happen with single-primary mode, but check.

---

## 6. Post-rehearsal validation (all 16 hosts, final check)

**Budget: 10 min**

Runs AFTER all three phases complete. Proves the cluster came back to a healthy steady state.

```bash
# All hosts reachable:
ansible -i inventories/dr.ini dr -m ping

# All hosts show recent reboot:
ansible -i inventories/dr.ini dr -m shell -a "uptime"

# Hardening applied correctly (spot checks):
ansible -i inventories/dr.ini dr -m shell -a "grep -c 'PermitRootLogin no' /etc/ssh/sshd_config"
ansible -i inventories/dr.ini dr -m shell -a "systemctl is-active auditd"
ansible -i inventories/dr.ini dr -m shell -a "aide --version >/dev/null && echo OK || echo MISSING"

# k3s cluster fully green:
ssh ubuntu@172.16.202.20 "kubectl get nodes && kubectl get pods -A | grep -vE 'Running|Completed' | wc -l"
# Expected: 5 Ready nodes, zero non-Running pods.

# MySQL GR all ONLINE:
ssh ubuntu@172.16.202.30 'mysql -u root -p$MYSQL_ROOT_PASS -e "SELECT MEMBER_STATE FROM performance_schema.replication_group_members;"' | sort | uniq -c
# Expected: 3 ONLINE

# MongoDB stretched RS healthy:
ssh ubuntu@172.16.202.36 'mongosh --quiet --eval "rs.status().members.length"'
# Expected: 6

# RabbitMQ cluster 3 nodes no partitions:
ssh ubuntu@172.16.202.36 "sudo rabbitmqctl cluster_status --formatter json | jq '.running_nodes | length'"
# Expected: 3

# Both VIPs held by exactly one host:
ansible -i inventories/dr.ini haproxy -m shell -a "ip -4 addr | grep -c 172.16.202.12"
ansible -i inventories/dr.ini proxysql -m shell -a "ip -4 addr | grep -c 172.16.202.35"
# Expected: each VIP sum = 1
```

---

## 7. Global abort criteria (stop rehearsal, consider rollback)

If ANY of these happen at ANY point, halt the playbook with `Ctrl-C`, do not restart, gather state with §6 commands, and decide rollback:

1. MySQL GR loses quorum (2+ members unreachable at the same time).
2. MongoDB RS falls below majority (fewer than 4 of 6 members healthy).
3. RabbitMQ `partitions` array is non-empty after 3 min.
4. `kubectl get nodes` shows 3+ NotReady simultaneously.
5. Any host fails to come back from reboot within 10 min (Proxmox console check needed).
6. Cumulative rehearsal elapsed time exceeds 150 min (vs. 105 min budget).

**Rollback option:** restore from Proxmox snapshot. Snapshot IDs recorded in §9. Do not proceed to prod planning until rehearsal can complete cleanly.

---

## 8. Timing capture sheet

Record actual wall-clock values. Compare to estimate in the email to Hugh.

| Phase                  | Tier         | Hosts | Estimate | Actual Start | Actual End | Elapsed | Δ vs est. |
|------------------------|--------------|-------|----------|--------------|------------|---------|-----------|
| 1. Hardening apply     | all          | 16    | 15 min   |              |            |         |           |
| 2a. k3s workers        | k3s_workers  | 5     | 8 min    |              |            |         |           |
| 2b. k3s masters        | k3s_masters  | 3     | 6 min    |              |            |         |           |
| 2c. ProxySQL           | proxysql     | 2     | 4 min    |              |            |         |           |
| 2d. HAProxy            | haproxy      | 2     | 4 min    |              |            |         |           |
| 3a. Mongo+Rabbit       | mongo_rabbit | 3     | 20 min   |              |            |         |           |
| 3b. MySQL GR           | mysql        | 3     | 15 min   |              |            |         |           |
| Post-validation        | all          | 16    | 10 min   |              |            |         |           |
| **TOTAL**              |              | 16    | **82**   |              |            |         |           |

---

## 9. Snapshot + rollback reference

| Host                   | IP             | Proxmox VM ID | Snapshot name                 |
|------------------------|----------------|---------------|-------------------------------|
| dr-haprox-01           | 172.16.202.10  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-haprox-02           | 172.16.202.11  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-k3s-master-01       | 172.16.202.20  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-k3s-master-02       | 172.16.202.21  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-k3s-master-03       | 172.16.202.22  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-k3s-worker-01       | 172.16.202.23  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-k3s-worker-02       | 172.16.202.24  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-k3s-worker-03       | 172.16.202.25  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-k3s-worker-04       | 172.16.202.26  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-k3s-worker-05       | 172.16.202.27  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-mysql-01            | 172.16.202.30  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-mysql-02            | 172.16.202.31  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-mysql-03            | 172.16.202.32  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-proxysql-01         | 172.16.202.33  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-proxysql-02         | 172.16.202.34  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-mongo-rabbit-01     | 172.16.202.36  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-mongo-rabbit-02     | 172.16.202.37  |               | pre-dr-rehearsal-YYYYMMDD     |
| dr-mongo-rabbit-03     | 172.16.202.38  |               | pre-dr-rehearsal-YYYYMMDD     |

Fill Proxmox VM IDs before rehearsal. Keep snapshots for 7 days post-rehearsal; delete after successful Apr 30 prod cutover.

---

## 10. Post-rehearsal report (fill out within 24h)

### Rehearsal summary

- **Date/time run:**
- **Operator:**
- **Overall outcome:** [PASS / PASS-WITH-NOTES / PARTIAL / ABORTED]
- **Total elapsed:**
- **Variance vs 82-min estimate:**

### Per-tier findings

- **Phase 1 (hardening apply):** (timing, any unexpected changed count, any warnings)
- **Phase 2a (k3s workers):**
- **Phase 2b (k3s masters):**
- **Phase 2c (ProxySQL):**
- **Phase 2d (HAProxy):**
- **Phase 3a (Mongo + Rabbit):**
- **Phase 3b (MySQL GR):**

### Issues encountered

For each: what happened, how it was resolved, whether it's fixed in the playbook or still a risk for prod.

### Apr 30 plan adjustments needed

Based on actuals, adjust:
- Timing budget sent to Hugh (update email if total ≥ 10% over estimate)
- Any per-tier sequencing changes
- Any additional preflight checks added
- Any hosts flagged for extra attention on prod

### Go / No-go decision for Apr 30 prod cutover

- [ ] GO — rehearsal passed, Apr 30 plan stands.
- [ ] GO WITH ADJUSTMENTS — rehearsal passed, plan updated (see above).
- [ ] NO-GO — rehearsal surfaced blockers, reschedule prod cutover. List blockers below.

---

*Last updated: 2026-04-19*
