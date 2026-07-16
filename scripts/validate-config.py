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
(`user-config.yaml` / `writing-sources.yaml` / a platform profile) and the fix,
then exits non-zero. A clean, fully resolved configuration prints nothing and
exits 0.

When platform profiles are configured (Story 16.2) their validation folds into
this same round-trip: a profile with a missing required key, an intent key
(`mode`/`canonical`/`syndication` — publishing intent lives in user config, not
a profile), an unresolved placeholder, or a malformed URL halts stage 0 with a
per-key report naming the profile file; legacy `syndication.variants.*` keys are
relayed once as an advisory (non-blocking) deprecation notice.

Stdlib-only by design; it drives the existing resolvers (`resolve-user-config.py`,
`resolve-writing-sources.py`, `resolve-platform-profiles.py`) so there is one
parse path, not two.
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
PROFILE_RES = os.path.join(HERE, "resolve-platform-profiles.py")
EXAMPLE = os.path.realpath(os.path.join(HERE, "..", "config", "user-config.example.yaml"))
SOURCES_EXAMPLE = os.path.realpath(os.path.join(HERE, "..", "config", "writing-sources.example.yaml"))

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

# Placeholder tokens a live platform profile must not still carry (a copied but
# un-customized example). `<` catches angle-bracket placeholders like `<hook>`.
PROFILE_PLACEHOLDER_TOKENS = ["example.com", "change-me", "changeme", "<"]


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
        # The machine-global per-repo location (#211) — resolved by the path
        # resolver (the single owner of that layout), never composed here.
        here = os.path.dirname(os.path.realpath(__file__))
        loc_cmd = [sys.executable, os.path.join(here, "resolve-paths.py"), "sources-file"]
        if args.root:
            loc_cmd += ["--root", args.root]
        loc = subprocess.run(loc_cmd, capture_output=True, text=True).stdout.strip()
        target = loc or f"the machine-global config (resolve-paths.py sources-file)"
        findings.append((SOURCES_FILE, "sources",
                         f"no readable sources are declared. Fix: create `{SOURCES_FILE}` "
                         f"at {target} (never in the host repo, #211) with at least one "
                         f"`- path:` entry — copy the example at {SOURCES_EXAMPLE} "
                         f"as a starting point."))


def validate_policy_source(args, findings):
    """Relay a malformed `policy_source` block (resolver exit 4) as stage-0
    findings. An absent block is silent, and a well-formed block whose path is
    unusable is deliberately NOT a config error — usability is checked at read
    time and degrades the interview instead (SPEC-policy-source-seam CAP-6)."""
    cmd = [sys.executable, SRC_RES]
    if args.root:
        cmd += ["--root", args.root]
    cmd += ["policy-source"]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 4:
        return
    for line in p.stderr.strip().splitlines():
        m = re.match(r"^\[(.+?)\]\s+(\S+):\s+(.*)$", line)
        if m:
            findings.append((m.group(1), m.group(2), m.group(3)))
        else:  # pragma: no cover - defensive
            findings.append((SOURCES_FILE, "policy_source", line))


def _walk_strings(obj, prefix=""):
    """Yield (dotted-keypath, value) for every string leaf in a profile map."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == "_path":
                continue
            yield from _walk_strings(v, f"{prefix}.{k}" if prefix else k)
    elif isinstance(obj, list):
        for i, v in enumerate(obj):
            yield from _walk_strings(v, f"{prefix}[{i}]")
    elif isinstance(obj, str):
        yield prefix, obj


def _profile_res(args, sub, *extra):
    # resolve-platform-profiles.py takes --root as a SUB-command argument, so the
    # subcommand must come first (`<sub> --root R`), not before the flags.
    cmd = [sys.executable, PROFILE_RES, sub]
    if args.root:
        cmd += ["--root", args.root]
    cmd += list(extra)
    return subprocess.run(cmd, capture_output=True, text=True)


def validate_platform_profiles(args, findings, notices):
    """Fold platform-profile validation into the stage-0 aggregate (Story 16.2).

    Profiles are optional: with no profiles directory this is a silent no-op.
    When profiles ARE configured it (1) relays the resolver's structural
    findings — missing required keys, and intent keys (`mode`/`canonical`/
    `syndication`) that are unrepresentable in a profile — as per-key findings;
    (2) flags unresolved placeholders and malformed URLs in profile values; and
    (3) relays each legacy `syndication.variants.*` key as a one-time
    deprecation notice (advisory, non-blocking — profiles migrate nothing)."""
    # Gate: only engage when a profiles directory actually exists (a migration
    # in progress). A repo not using variants is never nagged.
    dp = _profile_res(args, "dir")
    if dp.returncode != 0 or not os.path.isdir(dp.stdout.strip()):
        return

    # 1. Structural findings (resolver exit 4 → per-key `  [file] key: msg`).
    v = _profile_res(args, "validate")
    if v.returncode == 4:
        for line in v.stderr.strip().splitlines():
            m = re.match(r"^\s*\[(.+?)\]\s+(\S+):\s+(.*)$", line)
            if m:
                findings.append((m.group(1), m.group(2), m.group(3)))
            else:  # pragma: no cover - defensive
                findings.append(("platform-profiles", "(profile)", line.strip()))

    # 2. Content findings over structurally-valid profiles (placeholder / URL).
    r = _profile_res(args, "resolved")
    if r.returncode == 0:
        try:
            profiles = json.loads(r.stdout)
        except json.JSONDecodeError:  # pragma: no cover - defensive
            profiles = {}
        for platform, prof in profiles.items():
            fname = f"{platform}.yaml"
            for keypath, val in _walk_strings(prof):
                low = val.lower()
                if any(t in low for t in PROFILE_PLACEHOLDER_TOKENS):
                    findings.append((fname, keypath,
                                     f"value '{val}' looks like an unresolved placeholder. "
                                     "Fix: set a real value."))
                    continue
                if re.match(r"^https?://", val):
                    after = re.sub(r"^https?://", "", val)
                    path_part = after[after.find("/"):] if "/" in after else ""
                    if "//" in path_part:
                        findings.append((fname, keypath,
                                         f"'{val}' contains a double slash in its path. "
                                         "Fix: remove the doubled '/'."))

    # 3. Legacy syndication.variants.* → one-time deprecation notice.
    dcmd = [sys.executable, PROFILE_RES, "deprecations"]
    if args.root:
        dcmd += ["--root", args.root]
    if args.global_config:
        dcmd += ["--global-config", args.global_config]
    if args.repo_config:
        dcmd += ["--repo-config", args.repo_config]
    d = subprocess.run(dcmd, capture_output=True, text=True)
    if d.returncode == 0:
        for line in d.stdout.strip().splitlines():
            if line.startswith("deprecated:"):
                notices.append(line)


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    p.add_argument("--global-config", help="override the machine-global user-config path")
    p.add_argument("--repo-config", help="override the repo-local user-config path")
    p.add_argument("--skip-writing-sources", action="store_true",
                   help="validate only user-config (writing-sources not required)")
    args = p.parse_args(argv)

    findings = []
    notices = []
    validate_user_config(args, findings)
    if not args.skip_writing_sources:
        validate_writing_sources(args, findings)
        validate_policy_source(args, findings)
        validate_platform_profiles(args, findings, notices)

    # Advisory notices (e.g. legacy-key deprecation) are relayed exactly once
    # and never block — a clean config with a pending migration still exits 0.
    for line in notices:
        sys.stderr.write(f"notice: {line}\n")

    if not findings:
        return 0  # clean config: silent (but for any notices above), exit 0

    sys.stderr.write(
        "Stage 0 — configuration validation failed. Fix these before the "
        "pipeline can run:\n\n")
    for fname, key, msg in findings:
        sys.stderr.write(f"  [{fname}] {key}: {msg}\n")
    sys.stderr.write("\nNo generation or review work was done.\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
