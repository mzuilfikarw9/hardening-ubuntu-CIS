# Team announcement — prod maintenance, Apr 30 evening

Send: today, ~12:00 MYT or as soon as dry-run greenlights
Recipients: dev team, ops team, anyone with running workloads on prod

---

## Email version

**Subject:** Heads-up — prod maintenance window tonight, 21:00–22:00 MYT

Hi all,

Final reminder — there's a production maintenance window tonight from **21:00 to 22:00 MYT**. This is part 2 of the CIS hardening rollout. The DR side ran cleanly last week and we're following the same plan on prod.

What's happening: tier-by-tier reboot of 26 hosts (proxysql, haproxy, k3s masters, k3s workers, mongo/rabbit, mysql, monitoring, minio, lisabackend) with the hardening role applied first. The cluster keeps quorum throughout — we never take more than one host in a tier offline at a time.

What to expect:

- HAProxy and k3s NodePort services may see brief blips (seconds, not minutes) as individual hosts cycle.
- DB reads/writes via ProxySQL stay available — MySQL Group Replication holds quorum throughout.
- ArgoCD UI may be briefly unreachable while the k3s masters reboot.
- If any tier looks shaky we stop early. There's also a T+40 min tripwire that skips remaining tiers if the run runs over time, so we don't push past the agreed window.

If you've got anything time-critical scheduled tonight (cron jobs, deployments, scheduled reports, customer-facing work), please pause or reschedule before 21:00. Otherwise just expect normal service to be back by 22:00.

I'll be on Slack/WhatsApp, ping me if anything looks off. Please **don't reboot, restart, or apply config** to any prod host manually between 20:30 and 22:30 MYT — that risks colliding with the playbook.

After tonight we're cleanly past the hardening rollout for both DR and prod.

Thanks all.

— Zul

---

## WhatsApp version

Short, scannable, single message:

> 📣 Heads-up team — prod maintenance window tonight, **21:00–22:00 MYT** (CIS hardening + reboot, same plan as the DR rehearsal last week). Tier-by-tier reboot of 26 hosts, expect brief blips on k3s NodePort and HAProxy. Save anything time-critical before 21:00 and please don't touch prod hosts manually between 20:30 and 22:30. I'll be on Slack/WA the whole window — ping if something looks off. Should be back to normal by 22:00. 🙏

---

## Notes

- Strip the emojis from the WhatsApp version if your group chat tone is more formal — they're optional.
- If anyone replies asking "can it wait?" the answer is "we already pushed once, the window has been on the calendar for two weeks, but if there's a critical conflict please flag it now before 16:00 MYT."
- Don't send the email until after the dry-run rerun confirms `unreachable=0` and `failed=0` across all 22 prod hosts. Sending then having to retract is worse than sending an hour later.
