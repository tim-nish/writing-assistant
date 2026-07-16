#!/usr/bin/env python3
"""Resolve machine-global platform profiles (Story 16.1, SPEC-platform-variants CAP-2).

A **platform profile** is one declaration file per publication platform. Each
lives in a `platform-profiles/` subdirectory of the machine-global per-repo
config directory — never in a host repo's working tree and never as a constant
in stage code. That per-repo config directory is resolved through THE path
resolver (`resolve-paths.py repo-config-dir`); this script composes only the
`platform-profiles/` segment beneath it, never the config-home layout itself
(#211 footprint invariant). Print the profiles directory with `... dir`. A
profile declares exactly these top-level keys:

    platform            id (matches the file stem)
    audience            the one named reader for this platform's variant
    language            en | ja  (`ja` implies です/ます consistency downstream)
    packaging           frontmatter schema, tag cap, TL;DR placement, cover
                        requirements, canonical_url policy, and `visuals`
                        (diagram-rendering treatment) — the exhaustive set
    distribution_hook   where the end-pointer points for this audience

The variant stage's signature is (canonical draft, profile) → platform file
(consumed in Story 16.3). Adding a third platform is one profile file and zero
stage-code changes — this resolver globs the directory, so a new file resolves
on its own.

**Intent stays in user config.** A profile declares platform *packaging* only.
Publishing *intent* — the per-language canonical/external decision — lives in
user config's `syndication.policy` and is a relationship over the whole outlet
set, not an attribute of any one platform. A profile that declares an intent
key (`mode`, `canonical`, `canonicality`, or a `syndication` block) is rejected
(surfaced here; halted at stage 0 in Story 16.2). Legacy `syndication.variants.*`
keys migrate NOTHING into profiles — profiles' fields are new declarations; the
`deprecations` subcommand reports each legacy key's re-homing target.

Stdlib-only (host repos guarantee no venv); YAML is parsed by the shared subset
reader in resolve-user-config.py. Every command prints to stdout.

Subcommands:
  list           [--root R] [--profiles-dir D]   platform ids, one per line
  resolved       [--root R] [--profiles-dir D]    all profiles as one JSON object
  get PLATFORM   [--root R] [--profiles-dir D]    one profile as JSON
  validate       [--root R] [--profiles-dir D]    per-key findings on stderr, exit 4 if any
  deprecations   [--root R] [--global-config F] [--repo-config F]
                 one line per present legacy syndication.variants.* key
  dir            [--root R] [--profiles-dir D]     the resolved profiles directory
"""

import argparse
import glob
import importlib.util
import json
import os
import subprocess
import sys

# The complete top-level declaration set (exhaustive — an open-ended profile
# would be an untyped dimension). packaging is a map; the rest are scalars.
REQUIRED_KEYS = ["platform", "audience", "language", "packaging", "distribution_hook"]

# Publishing intent never lives in a platform profile (it is owner policy over
# the whole outlet set — user config's syndication.policy). Any of these in a
# profile is rejected. `canonical_url` is packaging (where/format), NOT intent.
INTENT_KEYS = ["mode", "canonical", "canonicality", "syndication"]

VALIDATION_FAILED = 4


def _load(mod_filename):
    """Load a sibling script as a module (the resolve-*.py idiom)."""
    here = os.path.dirname(os.path.realpath(__file__))
    name = mod_filename.replace(".py", "").replace("-", "_")
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, mod_filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rp = _load("resolve-paths.py")
uc = _load("resolve-user-config.py")   # shared stdlib YAML reader: uc.load_yaml


def host_root(arg_root):
    """--root or the git toplevel of cwd, realpath'd. Keep in sync with the
    identical helper in resolve-paths.py / resolve-user-config.py /
    resolve-writing-sources.py."""
    if arg_root:
        return os.path.realpath(arg_root)
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        sys.stderr.write("error: not inside a git repository (pass --root)\n")
        raise SystemExit(2)
    return os.path.realpath(r.stdout.strip())


def profiles_dir(root, override):
    """The platform-profiles directory: an explicit --profiles-dir (tests /
    overrides) else <repo-config-dir>/platform-profiles resolved via the path
    resolver. No caller composes this location itself."""
    if override:
        return os.path.realpath(override)
    return os.path.join(rp.repo_config_dir(root), "platform-profiles")


def _profile_files(pdir):
    """Live profile files in the directory: *.yaml, excluding *.example.yaml
    templates (so pointing at a shipped `config/` dir ignores examples)."""
    return [p for p in sorted(glob.glob(os.path.join(pdir, "*.yaml")))
            if not p.endswith(".example.yaml")]


def load_profiles(pdir):
    """Read and validate every live profile in pdir. Returns (profiles, findings)
    where profiles maps platform id -> profile dict (with `_path`), and findings
    is a list of (filename, key, message) for any structural problem. A profile
    with findings is omitted from the map (it is not a usable declaration)."""
    profiles, findings = {}, []
    for path in _profile_files(pdir):
        fname = os.path.basename(path)
        stem = fname[:-len(".yaml")]
        try:
            data = uc.load_yaml(open(path, encoding="utf-8").read())
        except uc.YamlSubsetError as exc:
            findings.append((fname, "(parse)", str(exc)))
            continue
        if not isinstance(data, dict):
            findings.append((fname, "(root)", "profile must be a YAML map"))
            continue
        bad = False
        for key in REQUIRED_KEYS:
            if key not in data or data[key] in (None, "", {}):
                findings.append((fname, key, "required profile key is missing or empty"))
                bad = True
        for key in INTENT_KEYS:
            if key in data:
                findings.append((fname, key,
                                 "publishing intent is not a profile field — it lives in "
                                 "user config's syndication.policy (Story 16.2 rejects it at stage 0)"))
                bad = True
        platform = data.get("platform")
        if platform and platform != stem:
            findings.append((fname, "platform",
                             f"id {platform!r} must match the file stem {stem!r}"))
            bad = True
        if bad:
            continue
        data["_path"] = path
        profiles[platform] = data
    return profiles, findings


def _emit_findings(findings):
    for fname, key, msg in findings:
        sys.stderr.write(f"  [{fname}] {key}: {msg}\n")


# --------------------------------------------------------------------------
# Subcommands


def cmd_dir(args):
    print(profiles_dir(host_root(args.root), args.profiles_dir))
    return 0


def cmd_list(args):
    pdir = profiles_dir(host_root(args.root), args.profiles_dir)
    profiles, findings = load_profiles(pdir)
    if findings:
        sys.stderr.write("error: unusable platform profile(s):\n")
        _emit_findings(findings)
        return VALIDATION_FAILED
    for platform in profiles:
        print(platform)
    return 0


def cmd_resolved(args):
    pdir = profiles_dir(host_root(args.root), args.profiles_dir)
    profiles, findings = load_profiles(pdir)
    if findings:
        sys.stderr.write("error: unusable platform profile(s):\n")
        _emit_findings(findings)
        return VALIDATION_FAILED
    print(json.dumps({p: {k: v for k, v in d.items() if k != "_path"}
                      for p, d in profiles.items()}, indent=2, ensure_ascii=False))
    return 0


def cmd_get(args):
    pdir = profiles_dir(host_root(args.root), args.profiles_dir)
    profiles, findings = load_profiles(pdir)
    named = [f for f in findings if f[0].startswith(args.platform + ".")]
    if named:
        sys.stderr.write(f"error: profile {args.platform!r} is unusable:\n")
        _emit_findings(named)
        return VALIDATION_FAILED
    if args.platform not in profiles:
        sys.stderr.write(f"error: no platform profile {args.platform!r} in {pdir}\n")
        return 1
    d = {k: v for k, v in profiles[args.platform].items() if k != "_path"}
    print(json.dumps(d, indent=2, ensure_ascii=False))
    return 0


def cmd_validate(args):
    """Structural validation for the stage-0 aggregate (Story 16.2 relays this).
    Prints per-key findings to stderr in the `  [file] key: message` shape and
    exits 4 if any; silent, exit 0 when clean."""
    pdir = profiles_dir(host_root(args.root), args.profiles_dir)
    _, findings = load_profiles(pdir)
    if findings:
        _emit_findings(findings)
        return VALIDATION_FAILED
    return 0


def cmd_deprecations(args):
    """Report present legacy `syndication.variants.*` keys with their re-homing
    target. Profiles migrate nothing — these keys re-home inside user config;
    profile fields are new declarations (SPEC-platform-variants OQ3, #211)."""
    cfg_args = argparse.Namespace(config_json=None, root=args.root,
                                  global_config=args.global_config,
                                  repo_config=args.repo_config)
    try:
        cfg = uc.resolve(cfg_args)
    except SystemExit:
        return 0   # no user config resolvable → nothing to deprecate
    variants = ((cfg.get("syndication") or {}).get("variants") or {})
    homes = {
        "canonical_url_base": "user config owner block (owner value)",
        "external_record_max_lines": "the top-level `site_record` block in user-config.yaml "
                                     "(owner-site record schema; see config/README.md)",
        "body_forbidden": "the top-level `site_record` block in user-config.yaml "
                          "(owner-site record schema; see config/README.md)",
    }
    n = 0
    for platform, block in sorted(variants.items()):
        if not isinstance(block, dict):
            continue
        for key in sorted(block):
            home = homes.get(key, "user config (owner value)")
            print(f"deprecated: syndication.variants.{platform}.{key} — "
                  f"re-home to {home}; platform profiles declare packaging anew, "
                  f"migrating nothing (#211)")
            n += 1
    if n == 0:
        print("ok: no legacy syndication.variants.* keys present")
    return 0


def build_parser():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def with_dir(sp):
        sp.add_argument("--root", help="host-repo root (default: git toplevel of cwd)")
        sp.add_argument("--profiles-dir",
                        help="override the profiles directory (tests / non-default locations)")
        return sp

    with_dir(sub.add_parser("list", help="platform ids, one per line"))
    with_dir(sub.add_parser("resolved", help="all profiles as one JSON object"))
    with_dir(sub.add_parser("validate", help="per-key findings, exit 4 if any"))
    with_dir(sub.add_parser("dir", help="the resolved profiles directory"))
    g = with_dir(sub.add_parser("get", help="one profile as JSON"))
    g.add_argument("platform")

    d = sub.add_parser("deprecations", help="legacy syndication.variants.* re-homing pointers")
    d.add_argument("--root", help="host-repo root (default: git toplevel of cwd)")
    d.add_argument("--global-config")
    d.add_argument("--repo-config")
    return p


DISPATCH = {
    "list": cmd_list, "resolved": cmd_resolved, "get": cmd_get,
    "validate": cmd_validate, "dir": cmd_dir, "deprecations": cmd_deprecations,
}


def main(argv=None):
    args = build_parser().parse_args(argv)
    return DISPATCH[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
