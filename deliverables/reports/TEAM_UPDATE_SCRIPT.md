# Team update — CIS hardening progress

*Informal script. Read it through once, then talk naturally. Rough 5-minute walkthrough.*

---

## The setup

So, quick update on where we are with the CIS L1 hardening work. As a reminder: the CTO's ask is that we get **35 more controls passing** on top of the baseline — we were at 166 passing, target is around 201. We have 36 Ubuntu servers in scope: 21 on 22.04 and 15 on 24.04.

Rather than just hit all 36 at once, I picked **two canary VMs** — one per Ubuntu version — and applied the full hardening to them first. That way if anything breaks, it breaks on a disposable box, not production.

- `172.16.102.52` — Ubuntu 22.04 canary
- `172.16.102.51` — Ubuntu 24.04 canary

---

## What we actually did

I wrote an Ansible playbook that applies the CIS L1 controls. It's organised by CIS section — kernel modules, mount options, process hardening, SSH, sudo, file permissions, and so on — so it's easy to see which control maps to which change.

The playbook ran clean on both canaries. **Zero failures.** SSH still works after the run, which was the thing I was most nervous about, because the playbook locks down sshd pretty hard.

---

## The blocker we hit

Here's the interesting part. While we were running, we discovered that **apt is broken across the HKL network** — not just for us, for any host trying to pull updates. Two issues stacked on top of each other:

1. **DNS hijacking** — internal DNS at `172.16.102.254` returns wrong IPs for Ubuntu mirror hostnames. So `archive.ubuntu.com` resolves to a local box that serves 404s.
2. **Path-MTU black hole** — the egress route silently drops large TCP packets. Small stuff goes through, anything over ~1400 bytes just vanishes.

So anything that required installing a package — AIDE, chrony, auditd, PAM pwquality, ufw — we couldn't do. I didn't want to fight the network for a week, so I **pivoted to an offline-safe subset** of the playbook. It only touches config files, sysctls, and file permissions. No apt, no package installs, no network dependencies.

That subset still covers a big chunk of CIS: kernel module blocklist, mount options, SSH hardening, sudo defaults, password policy, warning banners, network sysctls, file permissions. Basically everything the consultant scanner checks except the parts that depend on packages we can't install.

---

## Did we hit the +35 target?

**Honest answer: I don't know yet.** The playbook ran clean, but I haven't re-scanned to confirm the control count. Two reasons:

1. The canaries need a reboot first — some of the mount options and sysctls only activate at boot. Scanning before reboot would give a false-low number.
2. The SCAP scanner (`oscap`) isn't on our local setup. It usually lives on a scanner VM; we're standing that back up.

**My estimate:** the offline subset covers roughly 35 to 50 CIS controls that were failing before. Based on what we changed, I expect we'll meet or exceed the +35 target once we scan. But that's an estimate — the real number will come from the scan.

---

## What's next

1. **Reboot both canaries** — this morning.
2. **Set up a scanner** on my Mac using Docker, or loop the consultant back in to re-scan with their content. The consultant's scan is actually the authoritative one since their numbers produced the 166 baseline.
3. **If we hit 201 passing**, we roll this same playbook out to the remaining 34 hosts in batches — 25% at a time — with a rollback plan.
4. **If we undershoot**, we look at which specific controls are still failing and patch the role. Probably a handful of small fixes, not a rewrite.

The package-install controls (AIDE, chrony, auditd rules, PAM pwquality) stay deferred until we get a working apt mirror — either by fixing DNS, standing up an internal mirror, or sideloading packages. That's a separate workstream.

---

## Risks worth calling out

- **SSH lockout** — we mitigated by validating `sshd -T` before reloading and by keeping both canaries reachable throughout. Fleet rollout will use the same guardrails.
- **Reboot required** — mount options and some sysctls need a reboot. For production, we'll need to coordinate reboot windows host by host.
- **The network problem is fleet-wide, not ours to fix** — worth flagging to infra so the long-term fix happens in parallel.

---

## Questions?

*(open floor)*
