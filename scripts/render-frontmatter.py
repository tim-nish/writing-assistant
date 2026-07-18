#!/usr/bin/env python3
"""Render a config-bound `article` frontmatter block for a framework (CAP-6).

The field set, the mode/language enums, and the per-language canonical vs.
`mode: external` syndication policy all come from user config (Story 1.2 schema),
NOT from any hardcoded site schema. This emits the frontmatter SKELETON — value
slots stay as `{slot}` for the pipeline to fill (Story 4.4); mode/language and
the syndication shape are resolved here from config.

  EN (or any language whose policy mode is `canonical`):
     mode: canonical  +  a `syndication:` block from syndication.variants
  JA (or any language whose policy mode is `external`):
     mode: external   +  a note that the site record is body-forbidden

Config source: --config-json FILE (or - for stdin); else resolve-user-config.py.
"""

import argparse
import json
import os
import subprocess
import sys


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


def render(cfg, lang):
    fm = cfg.get("frontmatter", {})
    schema = fm.get("schema")
    if not schema:
        raise SystemExit("error: config has no frontmatter.schema (see config/user-config.example.yaml)")
    policy = cfg.get("syndication", {}).get("policy", {}).get(lang)
    if not policy:
        raise SystemExit(f"error: no syndication.policy for language {lang!r} in config")
    mode = policy["mode"]
    related_keys = fm.get("related_keys", ["projects", "publications", "products"])

    # Value renderers per known field; unknown fields fall back to a slot.
    def field_value(name):
        if name == "mode":
            return mode
        if name == "language":
            return lang
        if name == "title":
            return '"{title}"'
        if name == "summary":
            return ">\n  {summary}"           # <=240 chars (schema limit)
        if name == "topics":
            return "[{topic}]"
        if name == "related":
            return "{ " + ", ".join(f"{k}: []" for k in related_keys) + " }"
        return "{" + name + "}"

    out = ["---"]
    for name in schema:
        out.append(f"{name}: {field_value(name)}")
        if name == "language":
            # Pipeline-internal field (lede-retarget trigger, 2026-07-16):
            # required on the draft, stripped by variant packaging, never part
            # of the site schema in user config.
            out.append("audience: {audience}   # pipeline-internal — stripped at packaging")
            out.append("audience_id: {audience_id}   # pipeline-internal compatibility id (Story 13.71) — stripped at packaging")

    variants = cfg.get("syndication", {}).get("variants", {})
    if mode == "canonical":
        # dev.to syndication: canonical_url points back at the site page.
        base = variants.get("devto", {}).get("canonical_url_base", "{site_url}/articles")
        out += ["syndication:", "  devto:", f"    canonical_url: {base}/{{slug}}"]
    elif mode == "external":
        # Site-record constants live in the owner's `site_record` block (#282);
        # a legacy `syndication.variants.zenn` block is still honoured during
        # migration (stage 0 relays its deprecation pointer).
        site_rec = cfg.get("site_record") or variants.get("zenn", {}) or {}
        maxln = site_rec.get("external_record_max_lines", 20)
        out.append(f"# mode: external — site record <= {maxln} lines, body forbidden "
                   "(the external platform is canonical via repo-sync)")
    out.append("---")
    return "\n".join(out) + "\n"


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--config-json", help="resolved config as JSON (FILE or - for stdin)")
    p.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    p.add_argument("--global-config")
    p.add_argument("--repo-config")
    p.add_argument("--language", choices=["en", "ja"], default="en")
    args = p.parse_args(argv)
    sys.stdout.write(render(load_config(args), args.language))
    return 0


if __name__ == "__main__":
    sys.exit(main())
