# Daily sync script — Fri 24 Apr 2026

**Audience:** CTO + team
**Target length:** ~4 minutes spoken, leave room for questions
**Delivery tips:** Speak in paragraphs, not bullet points. Pause after the headline, pause again before Apr 30 plan. If anyone interrupts with a question, answer and come back to the thread.

---

Morning everyone. Quick update on where we are with the CIS hardening work and the DR rehearsal.

Short version first — the dress rehearsal Tuesday night went clean. We took all 18 DR hosts through the tiered reboot playbook between 10 PM and just after midnight. Every tier came back: proxysql, haproxy, k3s workers, k3s masters, mongo/rabbit, mysql. No Sev-1, no quorum loss on etcd or MySQL Group Replication or Mongo, ArgoCD was serving 200 on every worker once the masters were back. The T+40 tripwire we agreed on held comfortably — live reboot phase was about 90 minutes end-to-end.

On the scan side, we baselined mid-April at 160 to 170 rules passing per host against the SSG Ubuntu 24.04 profile. After hardening and reboot we're at 295 to 305. Net, that's about 135 rules newly passing per host. I've got the sign-off email drafted for you — I'll send it after this call with a representative HTML report from master-01 attached. Not going to spam 18 reports in one email; let me know if you want the full bundle.

Two small hiccups worth flagging, both on the scanning side rather than the reboot itself. `dr-mysql-03` had a 40-day-old zombie `apt-get` process blocking the scanner install. Root cause: the MySQL vendor rotated their GPG signing key back in March and nobody had re-trusted it, so daily unattended-upgrades had been wedged ever since. Cleared it, scan passed. `dr-proxysql-02` had two dpkg `rc`-state kernel packages that were making the OpenSCAP scanner segfault — known `libopenscap8` bug on rc-state entries. Purged them, scan passed. Both are on the pre-Apr-30 prep list for prod so we don't hit the same thing at 10 PM Wednesday.

Now, one thing I want to clear up in case it comes up — because the NetAssist results we got from Daniel at project start show different numbers than ours. Both tools sit on the same upstream, which is the CIS Ubuntu 24.04 L1 Server benchmark. The difference is scope. NetAssist checks 251 rules per host; the SSG profile we use checks 408. Same control families, different rule granularity. It's two different instruments looking at the same thing at different zoom levels — not that one's right and one's wrong.

Of the 85 specific rules Daniel flagged as failed on production, our Ansible role remediates about 57 directly, 7 are partial — they depend on operator config like firewall allow-lists or SSH allow-groups — and 19 are gaps we don't yet close. I also found one regression yesterday where our role was writing a journald setting the wrong way — `ForwardToSyslog`. One-line fix, already in, applies automatically on Apr 30. So the honest framing is: Daniel's NetAssist report is the baseline snapshot we're remediating against, and our OpenSCAP pipeline is how we prove compliance on a rolling basis going forward. They're complementary. I'll close the remaining 19 gaps in a scoped round-2 pass in May — most are small PAM edits.

Blockers — nothing red. Five things to close between now and next Wednesday. Refresh the MySQL vendor GPG key on all three prod mysql hosts. Run `kubectl get nodes` against prod to confirm no hidden workers — we found two in DR that weren't in our original inventory. Purge any dpkg `rc`-state kernel packages on prod mysql and proxysql. Add a preflight gate that aborts the reboot if `ip_forward` comes up wrong on a k3s node. And send the team announcement email for the Apr 30 window — going out today or tomorrow.

Apr 30 plan is unchanged. 2030 preflight against prod. 2100 role apply plus tiered reboot, 26 hosts, same order as DR. 2200 validation and go/no-go on the final tier. T+40 tripwire stays in — if we slip past it, remaining tiers skip and carry into the following weekly window. We do not force anything.

After Apr 30, I'll generate the prod OpenSCAP report in the same shape as the DR one so we've got the before/after number for compliance. Then we pick up the round-2 hardening pass in May. Three items in that pass need a decision from you or HKL before I implement — bootloader password, securetty plus root PATH scrub, and the journal-remote target. They either impact break-glass procedures or need a remote log host decided. I'll circulate that list separately this week so we can tee them up.

That's the update. Anything I missed, or anything you want to dig into?

---

## Quick-answer cheatsheet (for if questions come up)

**"Why is our number different from Daniel's?"** — Same benchmark, different scan tool. His checks 251 rules, ours checks 408. Control families identical, rule granularity differs.

**"Are we confident on Apr 30?"** — Yes, conditional on the five blocker items being closed. DR rehearsal proved the motion works on identical topology.

**"What if something goes wrong on Apr 30?"** — T+40 tripwire. Remaining tiers skip, we take them in the following weekly window. We do not force.

**"Why do we still have 19 gaps after all this?"** — Scope call. Closing them now means changing the role between DR and prod, which adds risk. Safer to ship the known-tested role on Apr 30 and close the gaps in a scoped round-2 pass in May, on an already-rebooted fleet.

**"What's the regression you mentioned?"** — Our journald drop-in was writing `ForwardToSyslog=yes`. CIS wants `no`. One-line edit to the role, fix goes in with the Apr 30 run automatically. No separate change needed.

**"Why did the MySQL GPG thing happen?"** — Vendor rotated keys in March, nobody in the pipeline re-trusted. Daily `unattended-upgrades` has been silently wedged for 40 days. We'll catch it earlier in future — adding an apt-health check to the weekly preflight is on my list.
