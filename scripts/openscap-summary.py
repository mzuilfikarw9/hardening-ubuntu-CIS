#!/usr/bin/env python3
"""
openscap-summary.py — Aggregate per-host OpenSCAP XCCDF results into a
single executive summary (CSV + HTML).

Reads:  deliverables/openscap/<env>/<hostname>/<hostname>-results.xml
Writes: deliverables/openscap/<env>/<env>-openscap-summary.csv
        deliverables/openscap/<env>/<env>-openscap-summary.html

Usage:
    python3 scripts/openscap-summary.py --env dr
    python3 scripts/openscap-summary.py --env prod

No third-party deps — stdlib only (xml.etree, csv, html, argparse).
"""

from __future__ import annotations

import argparse
import csv
import html
import sys
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree as ET

# XCCDF 1.2 namespace used by oscap output
NS = {"xccdf": "http://checklists.nist.gov/xccdf/1.2"}

# Outcomes we care about in order of severity (worst first in reports)
OUTCOMES = ["fail", "error", "unknown", "notchecked", "notapplicable",
            "informational", "pass", "fixed"]


def parse_host_results(xml_path: Path) -> dict:
    """Return dict(rule_id -> outcome) plus metadata for one host."""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    # Find the TestResult element — oscap emits exactly one per scan.
    test_result = root.find(".//xccdf:TestResult", NS)
    if test_result is None:
        raise ValueError(f"No TestResult in {xml_path}")

    profile = test_result.find("xccdf:profile", NS)
    profile_id = profile.get("idref") if profile is not None else "(unknown)"

    rules = {}
    for rr in test_result.findall("xccdf:rule-result", NS):
        rule_id = rr.get("idref")
        result_el = rr.find("xccdf:result", NS)
        outcome = result_el.text.strip() if result_el is not None else "unknown"
        rules[rule_id] = outcome

    return {
        "profile": profile_id,
        "start_time": test_result.get("start-time"),
        "end_time": test_result.get("end-time"),
        "rules": rules,
    }


def write_csv(out_path: Path, hosts: list[str],
              rule_rows: dict[str, dict[str, str]]) -> None:
    """Rule × host matrix. Each cell is the outcome for that host."""
    with out_path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["rule_id"] + hosts)
        for rule_id in sorted(rule_rows.keys()):
            row = [rule_id] + [rule_rows[rule_id].get(h, "n/a")
                               for h in hosts]
            w.writerow(row)


def outcome_css_class(outcome: str) -> str:
    """Map outcome to CSS class for the HTML summary."""
    if outcome == "pass" or outcome == "fixed":
        return "pass"
    if outcome == "fail" or outcome == "error":
        return "fail"
    if outcome == "notapplicable":
        return "na"
    return "other"


def write_html(out_path: Path, env: str, hosts: list[str],
               host_summary: dict[str, Counter],
               rule_rows: dict[str, dict[str, str]],
               scan_times: dict[str, tuple[str, str]]) -> None:
    """Executive summary: per-host pass rate, then full rule × host matrix."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Per-host pass rate (pass+fixed / applicable)
    def pass_rate(c: Counter) -> str:
        applicable = sum(c[k] for k in OUTCOMES if k != "notapplicable")
        if applicable == 0:
            return "n/a"
        passes = c["pass"] + c["fixed"]
        return f"{passes / applicable * 100:.1f}%"

    with out_path.open("w") as f:
        f.write(f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>OpenSCAP CIS L1 Server Summary — {env.upper()}</title>
<style>
  body {{ font-family: Arial, sans-serif; margin: 2em; color: #222; }}
  h1, h2 {{ margin-top: 1.5em; }}
  table {{ border-collapse: collapse; margin: 1em 0; font-size: 13px; }}
  th, td {{ border: 1px solid #ccc; padding: 4px 8px; text-align: left;
           vertical-align: top; }}
  th {{ background: #f0f0f0; }}
  .pass  {{ background: #d4edda; color: #155724; }}
  .fail  {{ background: #f8d7da; color: #721c24; font-weight: bold; }}
  .na    {{ background: #f4f4f4; color: #666; }}
  .other {{ background: #fff3cd; color: #856404; }}
  .rule-id {{ font-family: monospace; font-size: 11px; }}
  .meta {{ color: #666; font-size: 12px; }}
</style>
</head>
<body>
<h1>OpenSCAP CIS L1 Server Scan — {env.upper()}</h1>
<p class="meta">Generated {now} ·
  Profile: <code>xccdf_org.ssgproject.content_profile_cis_level1_server</code> ·
  SSG 0.1.80 ·
  Hosts scanned: {len(hosts)}</p>

<h2>Per-host summary</h2>
<table>
<tr>
  <th>Host</th><th>Scan start</th><th>Scan end</th>
  <th>Pass</th><th>Fail</th><th>Error</th>
  <th>N/A</th><th>Other</th><th>Pass rate</th>
</tr>
""")
        for h in hosts:
            c = host_summary[h]
            start, end = scan_times.get(h, ("", ""))
            other = sum(c[k] for k in OUTCOMES
                        if k not in ("pass", "fixed", "fail", "error",
                                     "notapplicable"))
            f.write(
                f"<tr><td>{html.escape(h)}</td>"
                f"<td class='meta'>{html.escape(start or '')}</td>"
                f"<td class='meta'>{html.escape(end or '')}</td>"
                f"<td class='pass'>{c['pass'] + c['fixed']}</td>"
                f"<td class='fail'>{c['fail'] + c['error']}</td>"
                f"<td class='fail'>{c['error']}</td>"
                f"<td class='na'>{c['notapplicable']}</td>"
                f"<td class='other'>{other}</td>"
                f"<td><b>{pass_rate(c)}</b></td></tr>\n")
        f.write("</table>\n")

        f.write("<h2>Rule × host matrix</h2>\n<table>\n<tr><th>Rule</th>")
        for h in hosts:
            f.write(f"<th>{html.escape(h)}</th>")
        f.write("</tr>\n")

        for rule_id in sorted(rule_rows.keys()):
            # Skip rules that passed on every host — keeps the matrix focused
            # on actionable items. Flip this flag to show everything.
            outcomes = {rule_rows[rule_id].get(h, "n/a") for h in hosts}
            if outcomes <= {"pass", "fixed", "notapplicable", "n/a"}:
                continue

            short = rule_id.replace(
                "xccdf_org.ssgproject.content_rule_", "")
            f.write(f"<tr><td class='rule-id'>{html.escape(short)}</td>")
            for h in hosts:
                outcome = rule_rows[rule_id].get(h, "n/a")
                f.write(
                    f"<td class='{outcome_css_class(outcome)}'>"
                    f"{html.escape(outcome)}</td>")
            f.write("</tr>\n")

        f.write("</table>\n")
        f.write('<p class="meta">Rules that passed on every host are hidden '
                'from the matrix to keep it focused. Per-host HTML reports '
                'under each host directory show every rule with full remediation '
                'guidance.</p>\n')
        f.write("</body></html>\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--env", required=True, choices=["dr", "prod"],
                    help="Environment under openscap/ to aggregate")
    ap.add_argument("--base-dir",
                    default=str(Path(__file__).resolve().parent.parent.parent
                                / "openscap"),
                    help="Root of openscap output (default: deliverables/openscap)")
    args = ap.parse_args()

    env_dir = Path(args.base_dir) / args.env
    if not env_dir.is_dir():
        print(f"ERROR: {env_dir} does not exist. "
              f"Run openscap-scan.yml first.", file=sys.stderr)
        return 1

    host_dirs = sorted(p for p in env_dir.iterdir()
                       if p.is_dir() and (p / f"{p.name}-results.xml").exists())
    if not host_dirs:
        print(f"ERROR: no per-host results XML found under {env_dir}",
              file=sys.stderr)
        return 1

    hosts = [p.name for p in host_dirs]
    host_summary: dict[str, Counter] = {}
    rule_rows: dict[str, dict[str, str]] = defaultdict(dict)
    scan_times: dict[str, tuple[str, str]] = {}

    for hd in host_dirs:
        xml_path = hd / f"{hd.name}-results.xml"
        try:
            parsed = parse_host_results(xml_path)
        except Exception as e:
            print(f"WARNING: failed to parse {xml_path}: {e}", file=sys.stderr)
            continue
        host_summary[hd.name] = Counter(parsed["rules"].values())
        scan_times[hd.name] = (parsed.get("start_time") or "",
                               parsed.get("end_time") or "")
        for rule_id, outcome in parsed["rules"].items():
            rule_rows[rule_id][hd.name] = outcome

    csv_path = env_dir / f"{args.env}-openscap-summary.csv"
    html_path = env_dir / f"{args.env}-openscap-summary.html"
    write_csv(csv_path, hosts, rule_rows)
    write_html(html_path, args.env, hosts, host_summary, rule_rows, scan_times)

    print(f"Wrote {csv_path}")
    print(f"Wrote {html_path}")
    print(f"Scanned {len(hosts)} hosts, {len(rule_rows)} distinct rules.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
