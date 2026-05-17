**Subject:** DR reboot rehearsal — done, prod Apr 30 still on

Hi [CTO],

Quick update on last night's DR dress rehearsal before it slips off my desk.

We took all 18 DR hosts through the tiered reboot playbook between 2200 and 0010 MYT. All six tiers — proxysql, haproxy, k3s workers, k3s masters, mongo/rabbit, mysql — came back clean. No Sev-1 during the window, no failed pod drains, no quorum loss on etcd / MySQL Group Replication / Mongo rs0. ArgoCD NodePort was serving 200 on all five workers once the masters were back. The T+40 min tripwire held comfortably — we finished the live reboot phase in about 90 minutes end-to-end.

Two small hiccups worth flagging, both on post-reboot scanning rather than the reboot itself:

- `dr-mysql-03` had a 40-day stuck `apt-get` process holding the dpkg lock. Root cause: the MySQL vendor GPG key had rotated back in mid-March and nobody had re-trusted it, so the daily unattended-upgrades had been wedged ever since. Cleared the stuck process, re-fetched, scan passed.
- `dr-proxysql-02` had two dpkg `rc`-state kernel packages that were making the OpenSCAP scanner segfault on its package probe (known `libopenscap8` bug on rc-state entries). Purged them, re-ran, scan passed.

Both are on the pre-Apr-30 prod prep list:
- Refresh the MySQL vendor apt signing key on all three prod mysql hosts before the window.
- Check the three prod mysql + two prod proxysql hosts for the same rc-state kernel remnants and purge ahead of time.

**Scan numbers** — OpenSCAP against the SSG Ubuntu 24.04 profile (408 rules):
- Pre-hardening baseline (Apr 17): ~160–170 rules passing per host.
- Post-hardening + reboot (Apr 23): ~295–305 rules passing per host.
- Net: ~135 rules newly passing per host across the DR fleet.

I've attached a representative HTML report from `dr-k3s-master-01` so you can see the shape of the output. It's one host out of 18 — I didn't want to blow up your inbox with 18 attachments. Happy to send the rest (or the machine-readable XMLs if you want to diff them) on request.

**Plan for Apr 30 is unchanged:**
- 2030 MYT — preflight-check.yml against prod
- 2100 MYT — role apply + tiered reboot (same order as DR)
- 2200 MYT — validation + go/no-go on the final tier
- T+40 min tripwire stays in place; if we slip past it, remaining tiers skip and carry into the following weekly window rather than forcing anything

**Two small follow-ups I'm closing before Apr 30, just so you know:**
- One journald setting our role was writing the wrong way (`ForwardToSyslog`). One-line fix, applies automatically on the Apr 30 run.
- Inventory drift re-check for prod. During DR prep `kubectl get nodes` showed two k3s workers that weren't in our original inventory. Worth running the same check against prod once before the window so we don't find a third one at 2130 MYT.

Nothing I need from you right now — just wanted the rehearsal result in your inbox before the Apr 30 window. Shout if you want the full 18-host report bundle or anything else.

Thanks,
Zul

---

**Attachment:** `dr-rehearsal-sample-report-2026-04-23.html` — OpenSCAP HTML report for dr-k3s-master-01 (representative of the 8 k3s nodes; non-k3s hosts show slightly different rule counts because they don't carry the k3s sysctl deviation on `ip_forward`).
