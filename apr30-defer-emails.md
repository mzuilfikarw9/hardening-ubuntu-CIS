# Apr 30 deferral — emails to CTO and team

Send NOW. Both can be copy-pasted directly.

---

## Email 1 — to CTO + Hugh

**To:** CTO, Hugh
**Subject:** Apr 30 prod hardening — deferring to Thu May 7, Hugh proceeds with MySQL tonight

Hi [CTO], Hugh,

Quick status before tonight's window kicks off — I'm deferring my prod hardening + reboot from tonight to next Thursday May 7, same 21:00-22:00 MYT slot.

What surfaced this evening: Hugh's MySQL DC update lands inside the same window and is expected to take 30-40 min. We can't reboot the mysql tier while his update is in flight, so the only way to fit both into a single 1-hour window is to adopt the parallel-per-tier reboot pattern Hugh proposed in his note. That pattern hasn't been validated yet — DR last week was the serial-with-quorum-waits pattern (~90 min for 18 hosts). Running an unrehearsed reboot approach on production tonight, alongside a concurrent MySQL maintenance, is more risk than I'm willing to carry into a hard 22:00 cutoff.

Plan from here:
- Tonight: Hugh runs the MySQL DC update 21:00-21:40 MYT as planned. I'm on standby on Slack/WhatsApp for the duration in case anything needs eyes.
- This week: I'll validate Hugh's parallel-per-tier reboot proposal on DR (low-risk environment, already hardened), measure actual time, and confirm whether it's safe to adopt for prod.
- Mon/Tue next week: I'll circulate an updated coordinated plan for May 7 — sequencing with Hugh's work, reboot pattern decision, any window-extension needs — for review by both of you before any team announcement.
- Thu May 7, 21:00-22:00 MYT: prod hardening + reboot, properly coordinated.

Today's prep work isn't wasted — the k3s sysctl override file is now staged on prod k3s nodes (preventing the Apr 20 NodePort regression), apt-daily timers are masked on prod mysql hosts (preventing dpkg lock contention), the role's journald regression is patched in code, and the new ip_forward preflight gate is validated against DR. All of that carries cleanly into May 7.

No team announcement for tonight's window has gone out yet, so nothing to retract there. I'll send a short note to the team confirming the date change.

Thanks for the patience. Better to land it cleanly than rush it under time pressure.

— Zul

---

## Email 2 — to team

**To:** dev team, ops team distribution list
**Subject:** Update — prod maintenance window moved from tonight to Thu May 7

Hi all,

Quick heads-up — the production CIS hardening + reboot window planned for tonight (21:00-22:00 MYT) has been rescheduled to **Thursday May 7, same 21:00-22:00 MYT time slot**. Coordinating with Hugh's MySQL update tonight needed more validation than we could fit in before the window, so we're moving ours to next week to do it properly.

What this means tonight:
- No maintenance from my side. Services run normally.
- Hugh is still running the MySQL DC update 21:00-21:40 MYT — that's a separate, smaller piece of work and shouldn't be visible to most of you.
- If you'd already paused work or rescheduled jobs around tonight's window, you can put them back.

I'll send a fresh announcement next week (Tue/Wed) with the May 7 details once the plan is locked. Same 26-host scope, same 1-hour window.

Sorry for the late shuffle.

— Zul

---

## Optional WhatsApp — to team chat

Short, casual:

> Heads-up team — tonight's prod maintenance window (21:00-22:00 MYT) is **rescheduled to next Thursday May 7**, same time. Hugh's MySQL update tonight still goes ahead as planned, but my CIS hardening + reboot is moving to next week so we can coordinate it properly. No action needed — services run normally tonight from my side. Fresh announcement coming Tue/Wed next week. 🙏

---

## Send order

1. **Email 1 to CTO + Hugh** first — get the technical decision documented and acknowledged.
2. **Email 2 to team** second — once the CTO has the context.
3. **WhatsApp** to team chat as a backup notification (optional but useful for fast reach).

If anyone replies asking why — point them to email 1's reasoning. If anyone pushes back on the date, the answer is "we'd rather slip a week than rush a production reboot." That's the same standard the CTO set with the T+40 tripwire.
