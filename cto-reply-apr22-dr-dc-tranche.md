Subject: RE: Hardening Plan — Date Clarification, NetAssist Waiver Item, and DC Window Approach

Hi [CTO name],

Thank you for the questions. Answers to both, plus the updated plan with corrected dates and alignment with Hugh's DC reboot approach.


Date clarification

Apologies for the day labels in my earlier message. Corrected schedule:

- Apr 22 (Wed): DR CIS L1 hardening + reboot dress rehearsal. Full 8-host DR k3s fleet (3 masters + 5 workers). Estimated window ~110 minutes.
- Apr 23 (Thu): Circulate Apr 22 post-exercise report with per-step actual timings and recommendations for DC.
- Apr 30 (Thu): MySQL Assessment improvements and Application Deployment only. DC CIS L1 hardening is deferred to a separate window as per your direction.
- Future DC window (date TBD): Tranche-based DC CIS L1 hardening using the protocol validated on Apr 22.


NetAssist "pass with justification" — specific item

The Apr 20 outage maps to a single NetAssist item ID on the k3s hosts:

- CIS 3.3.1 — "Ensure ip forwarding is disabled" (Ubuntu 24.04 LTS v1.0.0 L1 Server Benchmark, as assessed by NetAssist). This is the control that, when enforced, breaks Kubernetes pod-to-pod and Service routing on any host running k3s.

Proposed justification text for NetAssist:

"Host is a Kubernetes (k3s) node. IP forwarding is required by design for the container network and Service layer to function. Control CIS 3.3.1 is technically incompatible with the workload role of this host. Risk is mitigated by: (a) the host not being a router or gateway for external traffic; (b) iptables/netfilter rules managed by kube-proxy scoping forwarded traffic to cluster-internal Services and Pods; (c) host firewall restricting inbound access to the required Kubernetes ports only; (d) the control being re-enabled on any host repurposed off the Kubernetes role."

This item will be requested as a documented exception on all k3s nodes (DR and DC). All non-k3s hosts in the benchmark remain fully compliant with CIS 3.3.1. A small number of related CIS 3.3.x network controls will be reviewed during the Apr 22 rehearsal to confirm they do not produce the same class of failure; none are expected to require a waiver.

Belt and braces: in parallel with the NetAssist waiver, a pre-staged sysctl override file is applied on every k3s node before hardening runs. This provides the technical safety net so a missing or late waiver decision cannot break the cluster again.


DC window approach — aligned with Hugh's reboot plan

Hugh's proposal to reboot each host tier in parallel during the DC window is accepted, with the following guardrails to prevent a repeat of Apr 20:

- Preflight validation gate: after hardening is applied and before any reboot, the playbook blocks the reboot if any k3s node fails the required kernel-setting checks. Hard fail, no override.
- Proxmox snapshots: taken on all in-scope VMs before the window opens. Rollback is minutes, not hours.
- Masters rebooted in pairs, not all-at-once: for the k3s control plane specifically, reboots run at a minimum batch of 2 (not full parallel) to preserve etcd quorum through the window. Workers and non-k3s tiers can reboot fully in parallel per Hugh's plan.
- Post-reboot smoke test: DNS resolution from a test pod and a LIMS login flow. Regression is detected immediately, not through user reports.

Within the 1-hour DC window the recommendation is still to keep the first tranche to lower-risk hosts (HAProxy, monitoring, backup, jump/bastion, DNS/utility — roughly 8–10 hosts, 35–40% of the fleet). k3s masters and workers, MySQL, RabbitMQ, and LIMS application hosts would be handled in a follow-up window using the full protocol. Happy to defer to Hugh if he wants to widen the scope, provided the preflight gate and NetAssist 3.3.1 waiver are in place for any k3s host included.


Action items on my side

- Before Apr 22: pre-stage k3s compatibility overrides on all DR k3s nodes; finalize preflight validation gate; take Proxmox snapshots; submit CIS 3.3.1 waiver request to NetAssist with the justification text above.
- Apr 22 (Wed): execute DR CIS L1 hardening + reboot dress rehearsal per the breakdown below.
- Apr 23 (Thu): deliver post-exercise report with actual per-step timings and any deviations.
- Before the future DC window: complete inventory audit to confirm whether DC runs any k3s nodes; apply the same pre-stage + preflight protocol to DC k3s hosts (if any); extend the NetAssist waiver to cover those hosts; produce a formal tranche plan with named host lists for your approval.


Apr 22 (Wed) DR dress rehearsal — time breakdown

End-to-end estimate ~110 minutes across the 8-host DR k3s fleet:

- Proxmox snapshot of DR VMs — 15 min
- Pre-stage k3s compatibility overrides — 5 min
- Ansible connectivity + preflight check — 2 min
- Apply CIS hardening in batches of 25% — 20 min
- Post-hardening validation gate — 5 min
- Rolling reboot (masters in pairs, workers parallel) — 20 min
- Post-reboot cluster validation and LIMS smoke test — 15 min
- OpenSCAP compliance audit scan — 15 min
- Contingency buffer — 15 min


Apr 20 blocker — recap and prevention

For completeness: the Apr 20 DR outage was caused by a conflict between CIS Level 1 hardening and Kubernetes (k3s) networking — specifically CIS 3.3.1 (ip forwarding) plus a related bridge-netfilter setting that came along for the ride. With those kernel settings disabled, the cluster Service layer stopped working; application pods (including lisabackend) could no longer resolve the MySQL hostname through Kubernetes DNS, which looks like a database outage from the application side even though MySQL itself was healthy throughout.

Prevention for Apr 22 DR and all future DC windows is the combination of: the NetAssist CIS 3.3.1 waiver for documented compliance, the pre-staged sysctl override file on every k3s node for technical safety, the preflight validation gate that blocks reboot on any failing node, Proxmox snapshots for fast rollback, and a post-reboot smoke test that exercises the Kubernetes Service layer end-to-end. The Apr 22 rehearsal is explicitly designed to validate this full protocol before any DC hardening is attempted.


Happy to discuss by call if useful.

Best regards,
Zul
