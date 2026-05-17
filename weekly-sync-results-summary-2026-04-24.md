# Weekly sync — results summary (casual version)

**Audience:** team weekly
**Length:** ~90 seconds spoken
**Style:** relaxed, results-first, plain language

---

So the main win this week — we took all 18 DR machines offline and back online one at a time, same sequence we'll use in prod next Wednesday, and nothing broke. The databases stayed up, Kubernetes kept running, ArgoCD came back fine after the masters rebooted. That's the bit I was most nervous about, and it just worked.

The security number is the fun part. Each machine started the month passing about 165 security checks out of 408. After we hardened them and rebooted, every machine is now passing around 300. So basically we doubled our compliance score. That works out to roughly 135 security gaps closed per machine, across all 18 hosts.

And the nice thing is this isn't a one-shot number. The scan is fully automated now, so we can re-run it any time and get a fresh score. If something drifts back later, we'll see it.

A couple of small cleanup items came up when we ran the post-reboot scan — not during the reboot itself. One server had a stuck update process that had been sitting there for over a month, and another had some old kernel packages left over that were crashing the scanner. Both were existing clutter we inherited, nothing to do with our work. We cleaned them up and added them to the pre-prod checklist so we catch the same thing on the prod machines before next Wednesday.

Next Wednesday's plan is the same as this week's. Preflight at 8:30, reboots at 9, done by 10. If anything runs more than 40 minutes past start, we stop early and pick up the rest the following week. That rule held nicely in DR.

That's the main update. Happy to dig into any of it.

---

## One-liners if someone asks a follow-up

**"What does passing 300 of 408 actually mean?"** — Think of it as a checklist of 408 security best-practices. We used to tick about 165 boxes. Now we tick about 300. The remaining 100ish are a mix of things the server just doesn't need (not applicable) and things we'll close in a second pass in May.

**"Is this going to slow things down?"** — No. Hardening is config changes — file permissions, kernel settings, SSH rules. No performance impact.

**"What if something breaks in prod that didn't break in DR?"** — DR and prod are built from the same template on the same subnet design. We'd have seen it in DR. But the 40-minute stop rule means we never push past the safe window if something misbehaves.

**"Can you re-run this scan any time?"** — Yes. One Ansible command, under 5 minutes per host.

**"Do we need to tell anyone (users, auditors, HKL IT)?"** — Team email for the Apr 30 window goes out today or tomorrow. For HKL handover we'll generate a fresh report after prod reboots and share it with them.
