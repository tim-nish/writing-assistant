#!/usr/bin/env python3
"""Render the shared pointer block (spec §3 invariant) from user config.

The pointer block is byte-identical across all four frameworks, so the draft
skill renders it from ONE config-supplied template here rather than hand-copying
prose into each framework (which would silently drift). Identity content — focus
areas, site URL/name, the related/newsletter/counterpart lines — is drawn from
user config (CAP-6), never hardcoded.

Config source (resolved user-config as JSON): --config-json FILE (or - for
stdin); if omitted, this shells out to resolve-user-config.py with any
--global-config/--repo-config/--root passthrough.

Per-draft inputs:
  --language en|ja            the draft's language (selects the counterpart line)
  --related-title / --related-url   a related project/publication to link (both required to emit)
  --counterpart-url           the URL of the JA/EN counterpart, if one exists
  --newsletter-status STATUS  override pointer_block.newsletter.status for this draft

Branching is encoded here, not baked as a single static line:
  * newsletter line: newsletter.status coming-soon -> RSS/follow ; live -> capture
  * related line: emitted only when a related title AND url are supplied
  * counterpart line: EN draft + JA counterpart -> ja_counterpart ;
                      JA draft + EN counterpart -> en_counterpart ; else omitted

If a required identity value is missing from config, this emits a
not-publishable GATE marker (and exits 3) instead of a silently blank block.
"""

import argparse
import json
import os
import subprocess
import sys

GATE_UNFILLED_EXIT = 3


def load_config(args):
    if args.config_json:
        raw = sys.stdin.read() if args.config_json == "-" else open(args.config_json, encoding="utf-8").read()
        return json.loads(raw)
    here = os.path.dirname(os.path.realpath(__file__))
    cmd = [sys.executable, os.path.join(here, "resolve-user-config.py")]
    for flag, val in (("--root", args.root), ("--global-config", args.global_config),
                      ("--repo-config", args.repo_config)):
        if val:
            cmd += [flag, val]
    cmd.append("resolved")
    return json.loads(subprocess.run(cmd, capture_output=True, text=True, check=True).stdout)


def fill(template, values):
    for k, v in values.items():
        template = template.replace("{" + k + "}", v)
    return template


def render(cfg, args):
    owner = cfg.get("owner", {})
    pb = cfg.get("pointer_block", {})
    lines_cfg = pb.get("lines", {})
    news = pb.get("newsletter", {})

    # Required identity — a missing value makes the GATE unfilled / not publishable.
    missing = [k for k in ("focus_areas", "site_name", "site_url") if not owner.get(k)]
    template = pb.get("template")
    if missing or not template:
        need = ", ".join("owner." + m for m in missing) or "pointer_block.template"
        return (f"<!-- GATE {{Pointer block}}: NOT PUBLISHABLE — missing user config: {need} -->\n",
                GATE_UNFILLED_EXIT)

    # related line — only when both title and url are supplied
    related_line = ""
    if args.related_title and args.related_url:
        related_line = fill(lines_cfg.get("related", ""),
                            {"title": args.related_title, "url": args.related_url})

    # newsletter line — state-dependent
    status = args.newsletter_status or news.get("status", "coming-soon")
    if status == "live":
        newsletter_line = fill(lines_cfg.get("newsletter_live", ""),
                               {"capture_url": news.get("capture_url", "")})
    else:
        newsletter_line = fill(lines_cfg.get("newsletter_coming_soon", ""),
                               {"rss_url": news.get("rss_url", ""),
                                "follow_url": news.get("follow_url", "")})

    # counterpart line — conditional on draft language + presence of a counterpart
    counterpart_line = ""
    if args.counterpart_url:
        key = "ja_counterpart" if args.language == "en" else "en_counterpart"
        counterpart_line = fill(lines_cfg.get(key, ""),
                                {"url": args.counterpart_url,
                                 "title": args.related_title or args.counterpart_url})

    rendered = fill(template, {
        "focus_areas": owner["focus_areas"],
        "site_name": owner["site_name"],
        "site_url": owner["site_url"],
        "related_line": related_line,
        "newsletter_line": newsletter_line,
        "counterpart_line": counterpart_line,
    })

    # Drop conditional lines that resolved to empty (e.g. no related / counterpart).
    kept = [ln for ln in rendered.split("\n") if ln.strip().strip("*").strip() != ""]
    return "\n".join(kept) + "\n", 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--config-json", help="resolved config as JSON (FILE or - for stdin)")
    p.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    p.add_argument("--global-config")
    p.add_argument("--repo-config")
    p.add_argument("--language", choices=["en", "ja"], default="en")
    p.add_argument("--related-title")
    p.add_argument("--related-url")
    p.add_argument("--counterpart-url")
    p.add_argument("--newsletter-status", choices=["coming-soon", "live"])
    args = p.parse_args(argv)
    text, code = render(load_config(args), args)
    sys.stdout.write(text)
    return code


if __name__ == "__main__":
    sys.exit(main())
