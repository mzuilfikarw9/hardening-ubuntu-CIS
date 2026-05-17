# Finding: DR HAProxy HA pair is actually a single VM

**Date identified:** 2026-04-19
**Environment:** DR (HKLDR datacenter)
**Severity:** Informational — outside CIS L1 hardening scope
**Status:** Recorded for HKL infrastructure review

## Summary

The Ansible inventory lists two DR HAProxy nodes — `dr-haprox-01`
(172.16.202.11) and `dr-haprox-02` (172.16.202.12). Investigation
confirms these are **two IPs bound to the same physical VM**, not an
HA pair. DR has no real HAProxy failover.

## Evidence

Running the same commands against both IPs produced identical output:

| Check | Expected if distinct hosts | Observed |
|---|---|---|
| `/etc/machine-id` | Different UUIDs | `2de6c17023914f1c9fa986b1886bde77` on both |
| `hostname` / `/etc/hostname` | `dr-haprox-01` vs `dr-haprox-02` | `dr-haproxy-02` on both |
| Process PIDs for haproxy/keepalived | Different PIDs per box | Identical (1046723, 1046754, 1046765, 1046766) |
| `ip -4 addr show` | One IP per interface | Both report `eth0=172.16.202.11` **and** `eth0:1=172.16.202.12 (secondary)` |

The single VM has:

- Primary IP `172.16.202.11/24` on `eth0`
- Secondary alias IP `172.16.202.12/24` on label `eth0:1`

Both IPs answer SSH, so inventory-based tooling believes it's talking
to two distinct hosts.

## Keepalived configuration

`/etc/keepalived/keepalived.conf` on the VM (identical content whether
accessed via .11 or .12):

```
vrrp_instance VI_1 {
  interface eth0
  state BACKUP
  priority 100
  virtual_router_id 23
  nopreempt
  virtual_ipaddress {
    172.16.202.12/24 dev eth0 label eth0:1
  }
  track_script { chk_haproxy }
}
```

Two problems with this:

1. `virtual_ipaddress` is set to `172.16.202.12`, which is **already a
   static secondary IP on eth0:1**. Keepalived boots, sees the IP is
   present, reports MASTER, and takes no further action. Journal
   confirms no state changes in 48+ hours.
2. There is no peer node, so VRRP has nothing to negotiate with. The
   `state BACKUP` / `priority 100` / `nopreempt` pattern suggests this
   config was intended as one half of a pair.

There is **no floating VIP on 172.16.202.35** anywhere on DR. That
address was assumed during preflight development but does not exist on
the network.

## Impact

- **No HAProxy failover on DR.** If this VM fails, DR's HAProxy layer
  goes with it.
- **No functional impact on current DR operations** — DR is a standby
  site, users are on DC (prod), and the DR MongoDB/MySQL/RabbitMQ stack
  is reachable direct-to-backend from DR apps without needing the
  HAProxy path.
- **Dress rehearsal implication:** rebooting both inventory entries
  `dr-haprox-01` and `dr-haprox-02` will reboot the same physical VM
  twice in sequence. Idempotent but wasteful. Does not exercise real
  failover because there is no failover to exercise.

## Out of scope for CIS L1 audit

Fixing the DR HA topology (separating into two real VMs, fixing
keepalived config, or removing the duplicate inventory entry) is an
**infrastructure change**, not a CIS Level 1 hardening control.
Recording here as an observation for HKL's infrastructure team.

## Preflight handling

`preflight-check.yml` now treats the VIP check as **advisory by
default** (`enforce_vip_check: false`). The playbook will log a warning
if the VIP count is not exactly 1, but will not fail the preflight
run. To enforce the check (e.g. when running against prod, which may
have a real HA pair), pass `-e enforce_vip_check=true` on the command
line.

## Recommendation for Apr 30 prod window

Before the prod reboot, run the same verification against prod haproxy
hosts:

```bash
for host in <prod-haproxy-01-ip> <prod-haproxy-02-ip>; do
  ssh ubuntu@$host "cat /etc/machine-id"
done
```

If prod machine-ids also match, prod has the same single-VM-pretending-
to-be-two drift and Apr 30 reboot plan should be adjusted accordingly
(one reboot instead of serial:1 on two entries).

If prod machine-ids differ, prod has a real HA pair and
`-e enforce_vip_check=true` is appropriate for the prod preflight.
