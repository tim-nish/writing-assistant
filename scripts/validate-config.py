#!/usr/bin/env python3
"""validate-config.py — Stage-0 configuration validation (CAP-5, Story 7.4).

Runs BEFORE any generation or review. Validates the resolved configuration and
halts the pipeline up front on three classes of defect, so a configuration
problem is never discovered as a late article-quality finding:

  * unresolved example placeholders (values still carrying the shipped
    `user-config.example.yaml` defaults, e.g. `https://example.com`);
  * malformed URLs — notably a double-slash `canonical_url`, which a
    `canonical_url_base` with a trailing slash produces on composition;
  * missing required keys.

On any defect it prints a per-key report naming the file
(`user-config.yaml` / `writing-sources.yaml`) and the fix, then exits non-zero.
A clean, fully resolved configuration prints nothing and exits 0.

Stdlib-only by design; it drives the existing resolvers (`resolve-user-config.py`,
`resolve-writing-sources.py`) so there is one parse path, not two.
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
USER_RES = os.path.join(HERE, "resolve-user-config.py")
SRC_RES = os.path.join(HERE, "resolve-writing-sources.py")
EXAMPLE = os.path.realpath(os.path.join(HERE, "..", "config", "user-config.example.yaml"))

USER_FILE = "user-config.yaml"
SOURCES_FILE = "writing-sources.yaml"

# Required user-config keys (dotted paths). Absent or empty -> a finding.
REQUIRED_USER_KEYS = [
    "owner.name",
    "owner.site_url",
    "owner.site_name",
    "owner.focus_areas",
    "pointer_block.template",
    "frontmatter.schema",
    "syndication.policy",
]

# Keys whose value must be a well-formed URL.
URL_KEYS = [
    "owner.site_url",
    "syndication.variants.devto.canonical_url_base",
    "pointer_block.newsletter.rss_url",
    "pointer_block.newsletter.follow_url",
    "pointer_block.newsletter.capture_url",
]

# Keys a URL is *composed onto* (base + "/" + slug); a trailing slash here is the
# canonical double-slash defect from the acceptance criteria.
COMPOSED_URL_KEYS = {
    "owner.site_url",
    "syndication.variants.devto.canonical_url_base",
}

# Generic placeholder tokens (case-insensitive substring match) beyond an exact
# match against the shipped example.
PLACEHOLDER_TOKENS = ["example.com", "your name", "your-topic", "another-topic"]


def _resolver_json(script, args):
    cmd = [sys.executable, script]
    if args.global_config:
        cmd += ["--global-config", args.global_config]
    if args.repo_config:
        cmd += ["--repo-config", args.repo_config]
    if args.root:
        cmd += ["--root", args.root]
    cmd += ["resolved"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        return None, (p.stderr or p.stdout).strip()
    try:
        return json.loads(p.stdout), None
    except json.JSONDecodeError as e:  # pragma: no cover - defensive
        return None, f"could not parse resolver output: {e}"


def _example_json():
    cmd = [sys.executable, USER_RES, "--global-config", EXAMPLE,
           "--repo-config", os.devnull, "resolved"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        return {}
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:  # pragma: no cover - defensive
        return {}


def dig(d, path):
    cur = d
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def _url_findings(key, val):
    out = []
    if not re.match(r"^https?://", str(val)):
        out.append((USER_FILE, key,
                    f"'{val}' is not an absolute URL. Fix: use an http(s):// URL."))
        return out
    after_scheme = re.sub(r"^https?://", "", str(val))
    # Anything after the host: a doubled slash in the path is malformed.
    path_part = after_scheme[after_scheme.find("/"):] if "/" in after_scheme else ""
    if "//" in path_part:
        out.append((USER_FILE, key,
                    f"'{val}' contains a double slash in its path. "
                    "Fix: remove the doubled '/'."))
    if key in COMPOSED_URL_KEYS and str(val).endswith("/"):
        out.append((USER_FILE, key,
                    f"'{val}' has a trailing slash; canonical_url is composed as "
                    "base + '/' + slug, so this yields a double-slash URL. "
                    "Fix: drop the trailing '/'."))
    return out


def validate_user_config(args, findings):
    resolved, err = _resolver_json(USER_RES, args)
    if resolved is None:
        findings.append((USER_FILE, "(whole file)",
                         f"{err}  Fix: copy config/user-config.example.yaml to the "
                         "machine-global path and fill in your identity."))
        return
    example = _example_json()

    # 1. Missing required keys.
    for key in REQUIRED_USER_KEYS:
        v = dig(resolved, key)
        if v is None or v == "" or v == []:
            findings.append((USER_FILE, key,
                             "required key is missing or empty. "
                             "Fix: set it (see user-config.example.yaml)."))

    # 2. Unresolved placeholders (exact example match, or a generic token).
    for key in URL_KEYS + ["owner.name", "owner.site_name", "owner.focus_areas"]:
        v = dig(resolved, key)
        if v is None or not isinstance(v, str):
            continue
        ex = dig(example, key)
        low = v.lower()
        if (ex is not None and v == ex) or any(t in low for t in PLACEHOLDER_TOKENS):
            findings.append((USER_FILE, key,
                             f"value '{v}' is still the example placeholder. "
                             "Fix: replace it with your real value."))

    # 3. Malformed URLs.
    for key in URL_KEYS:
        v = dig(resolved, key)
        if isinstance(v, str) and v:
            findings.extend(_url_findings(key, v))


def validate_writing_sources(args, findings):
    cmd = [sys.executable, SRC_RES]
    if args.root:
        cmd += ["--root", args.root]
    cmd += ["sources"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0 or not p.stdout.strip():
        findings.append((SOURCES_FILE, "sources",
                         "no readable sources are declared. Fix: add at least one "
                         "`- path:` entry (see writing-sources.example.yaml)."))


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", help="host-repo root (default: git top-level, else cwd)")
    p.add_argument("--global-config", help="override the machine-global user-config path")
    p.add_argument("--repo-config", help="override the repo-local user-config path")
    p.add_argument("--skip-writing-sources", action="store_true",
                   help="validate only user-config (writing-sources not required)")
    args = p.parse_args(argv)

    findings = []
    validate_user_config(args, findings)
    if not args.skip_writing_sources:
        validate_writing_sources(args, findings)

    if not findings:
        return 0  # clean config: silent, exit 0

    sys.stderr.write(
        "Stage 0 — configuration validation failed. Fix these before the "
        "pipeline can run:\n\n")
    for fname, key, msg in findings:
        sys.stderr.write(f"  [{fname}] {key}: {msg}\n")
    sys.stderr.write("\nNo generation or review work was done.\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
