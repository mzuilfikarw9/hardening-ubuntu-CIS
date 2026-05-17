**Subject:** Production Security Hardening — Apr 30, 2100-2300 MYT

Hi team,

Following up on our earlier chat, I'd like to confirm the plan for applying CIS Level 1 security hardening across our production environment.

**When:** Wednesday, 30 April 2026, 2100-2300 MYT (2-hour maintenance window)

**What:** Apply CIS Level 1 hardening and reboot 26 Ubuntu servers that make up the DC / production environment (HAProxy, k3s cluster, MySQL, ProxySQL, MongoDB, RabbitMQ, MinIO, lisabackend, plus stg and dev edge hosts that share the same k3s cluster).

**Impact:** Production applications will be unavailable for the full window. Dev and stg workloads will also be affected because they share the k3s cluster with prod (different namespaces, same nodes).

**What we need from you:**

- Clinical ops: notify users about the downtime window.
- HIS app team: on standby for smoke tests as each tier comes back.
- DB DevOps (Hugh): Proxmox snapshots for all 26 hosts taken immediately before the window; MySQL GR and MongoDB replica-set health confirmed green pre-window.
- Everyone: change ticket approved before Apr 29.

The approach is already proven — same playbook was run across the full DR fleet earlier this week without incident. A dress rehearsal is scheduled for Apr 22 as a final check.

Happy to answer any questions.

Thanks,
Zul
