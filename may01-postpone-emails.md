# Apr 30 deferral — late-note emails (May 1)

These are post-event communications: we didn't run last night, and we're explaining today.

---

## Email 1 — to CTO + Hugh

**To:** CTO, Hugh
**Subject:** Apr 30 prod hardening — moved to Thu May 7 (apologies for the late note)

Hi [CTO], Hugh,

Apologies for the late note on this. Brief update on the Apr 30 prod hardening window — we did not run last night, and the work is moving to next Thursday May 7, same 21:00-22:00 MYT slot.

Two reasons it didn't happen:

First, when Hugh's MySQL DC update landed inside the same window, fitting both into 60 minutes meant adopting the parallel-per-tier reboot pattern Hugh proposed in his note — which I haven't validated on DR yet. Running an unrehearsed reboot pattern on production at T-30 minutes from window start, alongside concurrent MySQL maintenance, was more risk than I was willing to carry into a hard 22:00 cutoff. Hugh's MySQL DC update went ahead and ran cleanly, so production MySQL is now in a known-good post-update state going into May 7.

Second, I had a motorcycle accident on the way home and my laptop took the worst of it — it crashed before I could send this note last night. Apologies for the radio silence. I'm OK, just delayed.

Plan from here:
- This week: validate Hugh's parallel reboot proposal on DR, finish a clean full-prod dry-run, add a post-reboot k3s safety gate to the playbook, lock the May 7 plan with both of you.
- Mon/Tue: I'll circulate the updated coordinated plan for review before any team announcement.
- Tue/Wed: team announcement for May 7.
- Thu May 7, 21:00-22:00 MYT: prod hardening + reboot, properly coordinated this time.

Yesterday's prep work isn't wasted — the k3s sysctl override file is already deployed on all 6 prod k3s nodes (preventing the Apr 20 NodePort regression from repeating), apt-daily timers are masked on prod mysql hosts (preventing dpkg lock contention), and the role's journald regression is patched in code. All of that carries clean into May 7.

Thanks for the patience on the late note.

— Zul

---

## Email 2 — to team

**To:** dev team, ops team distribution list
**Subject:** Update — prod maintenance window moved to Thu May 7

Hi all,

Quick note — the prod CIS hardening + reboot window planned for last night (Thu Apr 30, 21:00-22:00 MYT) didn't run and has been rescheduled to **Thursday May 7, same 21:00-22:00 MYT time slot**.

Two reasons: timing conflict with Hugh's MySQL DC update meant we couldn't fit both safely into the 60-minute window, and I had a small motorcycle incident on the way home that took my laptop offline before I could send a proper heads-up — apologies for the silence.

What this means:
- Last night ran normally on our side. Services unaffected.
- Hugh's MySQL update did go ahead and ran cleanly.
- I'll send a fresh announcement Tue/Wed next week with May 7 details once the plan is locked.

Sorry for the late note.

— Zul

---

## WhatsApp version (team chat)

> Hi all — quick note. Last night's prod maintenance window didn't run (timing conflict with Hugh's MySQL update + I had a small motorcycle incident on the way home that took my laptop offline before I could send a proper heads-up — apologies). Hugh's MySQL update went ahead and ran fine. My CIS hardening + reboot is rescheduled to **Thursday May 7, same 21:00-22:00 MYT**. I'm OK. Fresh announcement with details going out Tue/Wed. 🙏

---

## Send order

1. **Email 1 (CTO + Hugh) first** — they're the ones who need the technical reasoning and might worry if they don't hear back. Don't overdramatise the accident; mention it once, briefly, alongside the technical reason. The "I'm OK, just delayed" line is the important bit.
2. **Email 2 to team second.**
3. **WhatsApp to team chat** if applicable.

## Notes for if anyone asks

- **"Are you OK?"** — yes, fine, just shaken and laptop is being replaced/repaired.
- **"Do we need to push May 7 too?"** — no, this week is plenty of time to finalize the plan. We're not behind.
- **"Why didn't you just send a quick text?"** — fair question, the laptop crash + dealing with the incident took priority and by the time things settled it was late. Owning the delay is better than excuses.
