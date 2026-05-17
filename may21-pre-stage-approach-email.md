# Prod hardening Thu May 21 — Option C (pre-stage approach) announcement

Two versions. Short. Ready to paste.

---

## Email to CTO + Hugh

**To:** CTO, Hugh
**Subject:** Prod hardening — Thu May 21, pre-stage approach to keep window at 1 hour

Hi [CTO], Hugh,

Locking in Thursday May 21 for prod hardening. To keep business downtime at 1 hour without rushing, I'm splitting the work into two phases on the same day:

- **~19:30 MYT — pre-stage role apply.** Writes the CIS hardening config to all 22 prod hosts. Config-only, no reboot, expected to be invisible to running services. ~30 min.
- **21:00-22:00 MYT — live window.** Tier-serial reboot only (`reboot-ha.yml`). ~60-70 min based on DR scaling. T+40 min tripwire stays in place.

Reasoning: DR rehearsal took 90 min end-to-end for 18 hosts. Prod is 22 hosts, scaling to ~100-110 min. Doing the role apply in pre-stage means the live downtime window is reboot-only, which fits 1 hour comfortably instead of being squeezed into 60 minutes with no margin.

Safety against the Apr 20 k3s/ArgoCD failure mode is in place: `99-k3s-overrides.conf` was deployed to all 6 prod k3s nodes on Apr 30; the post-reboot k3s gate I built (validated on DR this week) halts the play if `ip_forward` comes back wrong on any k3s host; the journald regression in the role is patched.

Team announcement Mon/Tue.

— Zul

---

## Email to team

**To:** dev team, ops team distribution list
**Subject:** Prod maintenance window — Thursday May 21, 21:00-22:00 MYT

Hi all,

Heads-up — production CIS hardening + reboot is scheduled for **Thursday May 21**. Two-phase plan on the day:

- **~19:30 MYT — config push.** I'll be applying CIS config to prod hosts in the background. No service impact expected.
- **21:00-22:00 MYT — maintenance window.** Tier-by-tier reboot of 22 prod hosts. Brief blips on HAProxy / k3s NodePort / ArgoCD possible during this hour.

If you've got time-critical work scheduled in that window (cron jobs, deployments, customer-facing actions), please reschedule before 21:00 MYT. Everything should be back to normal by 22:00.

I'll be on Slack/WhatsApp from 19:00 through 22:30 MYT. Ping me if anything looks off.

— Zul

---

## WhatsApp version (team chat)

> Heads-up team — prod CIS hardening + reboot lands **Thursday May 21**. Config push around 19:30 MYT (no impact expected), then live maintenance window 21:00-22:00 MYT for the reboot phase. Brief blips possible on HAProxy / k3s NodePort / ArgoCD during the 1-hour window. Save anything time-critical before 21:00 MYT. I'll be on Slack/WA from 19:00-22:30. 🙏

---

## Why Option C in one sentence

DR took 90 min for 18 hosts; squeezing 22 prod hosts into a 60-min window means no margin for a slow tier, but splitting the work so only the reboot phase is in the live window keeps business downtime at 1 hour while giving us proper room for the config apply.

## Send order

1. Email 1 (CTO + Hugh) — today or tomorrow morning.
2. Email 2 (team) — Mon/Tue, 2-3 days before May 21.
3. WhatsApp on the day of the window (May 21 morning) as a final reminder.
