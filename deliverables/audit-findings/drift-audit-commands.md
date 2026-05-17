# Prod Inventory Drift Audit — Command Sheet

**Goal:** Determine the role of 9 IPs present in legacy `hkl.ini` but
absent from the DevOps service-role table (2026-04-19), before the
Apr 30 prod change window.

**IPs to classify:**
`172.16.102.26, .27, .45, .57, .58, .60, .61, .62, .63`

Highest priority: **.26 and .27** — these may be hidden k3s workers
(mirrors the DR drift we found at 172.16.202.26 / .27).

---

## Step 1 — Confirm k3s cluster membership

Run from your control node or any k3s master. Use the prod kubeconfig.

```bash
# List every node the cluster currently sees, with internal IPs.
kubectl --kubeconfig ~/.kube/prod-config get nodes -o wide

# Compare the INTERNAL-IP column against the service-role table.
# Any node on 172.16.102.26 or .27 is a hidden worker and must be
# added to inventories/prod.ini under [k3s_workers].
```

What to do with the output:

- If `.26` and/or `.27` appear as Ready nodes → they're hidden prod
  k3s workers. Add them to `[k3s_workers]` in `prod.ini` and include
  them in Apr 30 scope (scope becomes 27 or 28 hosts).
- If they don't appear in `kubectl get nodes` → they're not k3s nodes.
  Move on to Step 2.

## Step 2 — Ping sweep the 9 IPs

From your Mac (control node):

```bash
for ip in 26 27 45 57 58 60 61 62 63; do
  printf '172.16.102.%-3s -> ' "$ip"
  ping -c 1 -W 1 172.16.102.$ip >/dev/null 2>&1 \
    && echo 'ALIVE' \
    || echo 'no response'
done
```

## Step 3 — Probe responding hosts via SSH

For each IP that responded ALIVE in Step 2, try SSH with the same key
used for the rest of the fleet:

```bash
for ip in 26 27 45 57 58 60 61 62 63; do
  echo "=== 172.16.102.$ip ==="
  ssh -i ~/Documents/clicque/leet-clicque-key.pem \
      -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=accept-new \
      -o BatchMode=yes \
      ubuntu@172.16.102.$ip \
      'hostname; lsb_release -d; systemctl list-units --type=service --state=running | head -20' \
      2>&1 | sed 's/^/  /'
  echo
done
```

What to look for in the output:

- `hostname` → usually encodes the role (e.g., `prod-k3s-worker-04`, `stg-mongo-01`).
- `lsb_release -d` → Ubuntu version confirms which inventory group to add them to.
- Top running services → hints at role if hostname is generic:
  - `k3s.service` or `k3s-agent.service` → k3s node (already covered by Step 1)
  - `mysqld.service` → MySQL host
  - `mongod.service` → MongoDB
  - `rabbitmq-server.service` → Rabbit
  - `haproxy.service` → HAProxy edge
  - `minio.service` → MinIO

## Step 4 — Port fingerprint for silent hosts

If a host responds to ping but not to SSH (auth failure, or firewalled
SSH), port-fingerprint with nmap:

```bash
# Install nmap if you don't have it:
#   brew install nmap   (on your Mac)
nmap -Pn -p 22,80,443,3306,6443,9100,9200,15672,27017 \
     172.16.102.26,27,45,57,58,60,61,62,63
```

Common signatures:

| Open port | Likely role                         |
|-----------|-------------------------------------|
| 6443      | k3s master (API server)             |
| 10250     | kubelet (any k3s node)              |
| 3306      | MySQL or ProxySQL                   |
| 27017     | MongoDB                             |
| 15672     | RabbitMQ mgmt UI                    |
| 9000/9001 | MinIO                               |
| 9100      | node_exporter (any host)            |
| 80/443    | HAProxy, nginx, or app backend      |

## Step 5 — Decide per host

For each of the 9 IPs, classify into one of:

1. **In scope, role confirmed** → add the host entry to the correct
   group in `inventories/prod.ini` and include in Apr 30 scope.
2. **Decommissioned / dead** → document in the commented-out block at
   the bottom of `prod.ini`. Ask DevOps to confirm they can be removed
   from hkl.ini.
3. **Non-prod environment (QA, staging-2, etc.)** → move to a separate
   inventory file; NOT included in Apr 30 change.

## Step 6 — Report results

When done, paste back:
- The `kubectl get nodes -o wide` output (Step 1)
- The ping sweep results (Step 2)
- Hostnames / OS / top services for each responding IP (Step 3)
- Any nmap output for silent hosts (Step 4)

I'll then update `prod.ini` with the confirmed roles and revise the
Apr 30 host count in the email to Hugh if it changed.

---

**Target completion:** Apr 22 (before DR dress rehearsal), so the
email to Hugh's team goes out with the final locked count.
