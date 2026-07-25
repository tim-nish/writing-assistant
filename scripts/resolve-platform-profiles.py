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
  missing        [--root R] [--profiles-dir D]     declared platforms with no
                 resolvable profile, tagged seedable | no-template
  seed PLATFORM  [--root R] [--profiles-dir D] [--force]
                 write one profile from its shipped example — THE sanctioned
                 write path (Story 18.52, #568)

**The pipeline places the profile, not the owner (Story 18.52, #568).** Setup
and the emit-variants preflight consume `missing` and offer each seedable
platform in-conversation (approve/modify/skip), then write through `seed` —
never a machine-state path plus a `cp` instruction for the owner to run by
hand. `seed` creates the directory, writes through the path resolver, refuses
to overwrite an existing profile without `--force`, and verifies the result by
re-validating before reporting success.
"""

import argparse
import glob
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile


def _under_tmp(path):
    """True when `path` is inside the system temporary directory. Both sides
    realpath-canonicalized so a symlinked TMPDIR compares correctly. The same
    temp-under predicate the draft pipeline's isolation gate uses (Story 18.53);
    reused here, not re-derived, to keep one self-evident notion of "disposable"
    (Story 18.102, #689)."""
    tmp = os.path.realpath(tempfile.gettempdir())
    real = os.path.realpath(path)
    return real == tmp or real.startswith(tmp + os.sep)

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
    profiles, findings = load_profiles(pdir)
    # Seeded-profile drift (#719) is REPORT-ONLY and never changes the exit
    # code: the failure is an absence, so its carrier is a signal that makes the
    # absence visible, not a gate. Reported even when structural findings exist
    # — the two are independent, and suppressing one behind the other would hide
    # drift for exactly as long as an unrelated defect went unfixed.
    for platform in sorted(profiles):
        for key in seed_drift(platform, profiles[platform], args.examples_dir):
            sys.stderr.write(
                f"note: {platform}.yaml declares no {key!r}, which the shipped "
                f"example has since gained — your edits are untouched; add it "
                f"if you want the behaviour it enables (#719)\n")
    if findings:
        _emit_findings(findings)
        return VALIDATION_FAILED
    return 0


def examples_dir(override=None):
    """The shipped `config/platform-profiles/` templates directory (repo-local,
    read-only source material — never a write destination)."""
    if override:
        return os.path.realpath(override)
    here = os.path.dirname(os.path.realpath(__file__))
    return os.path.realpath(os.path.join(here, "..", "config", "platform-profiles"))


def example_seed_version(text):
    """The seed stamp for an example's content: a short sha256 over its bytes.

    A CONTENT hash rather than a hand-bumped revision string, because a string
    only records what someone remembered to bump. The noise a content hash would
    normally carry — a comment-only example edit reading as drift — does not
    arise here: the drift check below diffs DECLARED KEYS, never this stamp, so
    the stamp is provenance ("seeded from the example that hashed to X") and the
    check is independent of it.
    """
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]


def _declared_key_paths(node, prefix=""):
    """Every declared key path in a profile map, dotted (`packaging.layout.dir`).

    Only mapping structure is walked — a list value is a leaf. The comparison
    this feeds is about which DECLARATIONS exist, never about their values.
    """
    paths = set()
    if not isinstance(node, dict):
        return paths
    for key, value in node.items():
        if str(key).startswith("_"):        # `_path` and friends are injected
            continue
        path = f"{prefix}{key}"
        paths.add(path)
        paths |= _declared_key_paths(value, path + ".")
    return paths


def seed_drift(platform, profile, examples_override=None):
    """Key paths the shipped example declares that this seeded profile does not.

    The conformance-copy mismatch check (#719, SPEC-platform-variants): seeding
    correctly refuses to overwrite an owner-edited profile, so a load-bearing
    declaration the example gains later never reaches an existing installation —
    and where that declaration also gates a lint, its absence disables the very
    check that would have reported the consequence.

    REPORT-ONLY and PRESENCE-ONLY by contract. The example is authoritative for
    which declarations exist, never for their values: a profile whose `tag_cap`
    differs from the example's is a sovereign owner edit and reports nothing.
    A profile with no `seed_version` is pre-stamp and is diffed anyway rather
    than skipped — those are exactly the installations that predate the stamp
    and so are the most likely to have drifted.
    """
    src = os.path.join(examples_dir(examples_override), f"{platform}.example.yaml")
    if not os.path.isfile(src):
        return []                # hand-authored profile: nothing to conform to
    try:
        example = uc.load_yaml(open(src, encoding="utf-8").read())
    except uc.YamlSubsetError:
        return []                # a broken example accuses no one
    if not isinstance(example, dict):
        return []
    missing = _declared_key_paths(example) - _declared_key_paths(profile)
    # A missing parent already tells the whole story; its children are noise.
    return sorted(p for p in missing
                  if not any(p.startswith(q + ".") for q in missing))


def seedable(root, profiles_override=None, examples_override=None):
    """(seedable, unresolvable) for this host repo: platform ids that have a
    shipped example but no live profile, and ids with neither (nothing to seed
    from — the owner must author the profile or drop the declared variant)."""
    pdir = profiles_dir(root, profiles_override)
    live, _ = load_profiles(pdir)
    edir = examples_dir(examples_override)
    examples = {os.path.basename(p)[:-len(".example.yaml")]
                for p in sorted(glob.glob(os.path.join(edir, "*.example.yaml")))}
    return sorted(examples - set(live)), sorted(set(live))


def cmd_seed(args):
    """Seed one platform profile from its shipped example — the SANCTIONED
    write path for platform profiles (Story 18.52, #568; SPEC-repo-onboarding
    CAP-2). Setup and the emit-variants preflight call this instead of telling
    the owner to find a machine-state path and hand-copy files: the pipeline
    places the file, the owner only approves.

    The destination resolves through the path resolver like every other read
    (no caller composes the config-home layout), the directory is created if
    absent, and the write is VERIFIED by re-validating the profile before
    reporting success. An existing profile is never overwritten without
    --force — seeding is additive, and clobbering an owner's edits would be
    the opposite of the proposal contract this exists to honour.
    """
    root = host_root(args.root)
    pdir = profiles_dir(root, args.profiles_dir)

    # Isolation (Story 18.102, #689): a DISPOSABLE host root — one resolving
    # under the system temp dir — must not accrue DURABLE machine-global config.
    # Seeding against a `/tmp/...` test host with no isolated destination
    # composes `platform-profiles/` beneath the real per-repo config home keyed by
    # the temp root, leaving throwaway config dirs behind after the temp tree is
    # gone (71 such dirs were found). Refuse it. The predicate is the
    # DESTINATION, matching 18.53: a temp root writing UNDER the temp tree (an
    # explicit `--profiles-dir` fixture, or an isolated XDG_CONFIG_HOME) resolves
    # normally — that is what check harnesses use and it leaves no residue. An
    # ordinary owner root (not under temp) is never refused.
    if _under_tmp(root) and not _under_tmp(pdir):
        sys.stderr.write(
            f"error: refusing to seed durable config for a disposable host root "
            f"({root}) — it resolves under the system temp dir but the profile "
            f"destination ({pdir}) does not, so the seeded profile would outlive "
            f"the throwaway root as machine-global residue (#689). Point "
            f"--profiles-dir under the temp tree, or set XDG_CONFIG_HOME to an "
            f"isolated location, so a test host leaves no durable config behind.\n")
        return 1

    src = os.path.join(examples_dir(args.examples_dir),
                       f"{args.platform}.example.yaml")
    if not os.path.isfile(src):
        sys.stderr.write(
            f"error: no shipped example for platform {args.platform!r} "
            f"({src}) — a platform with no template is authored by hand, not seeded\n")
        return 1
    dest = os.path.join(pdir, f"{args.platform}.yaml")
    if os.path.exists(dest) and not args.force:
        sys.stderr.write(f"error: {dest} already exists; refusing to overwrite "
                         "(pass --force to replace it)\n")
        return 1

    os.makedirs(pdir, exist_ok=True)
    with open(src, encoding="utf-8") as fh:
        body = fh.read()
    # The example's header documents the manual copy this subcommand replaces;
    # rewrite it so the seeded file records how it actually got there.
    body = body.replace(
        "# Copy to the machine-global per-repo profiles directory (NEVER the host repo):",
        "# Seeded from the shipped example by `resolve-platform-profiles.py seed`\n"
        "# (Story 18.52, #568). Edit freely — this file is yours; re-seeding\n"
        "# refuses to overwrite it without --force. Original instructions:", 1)
    # The seed stamp records WHICH example revision this copy came from (#719).
    # Provenance only — `validate` reports drift from a key diff, never from
    # this value — so an owner editing the file below never invalidates it.
    body = (f"# Seeded from {os.path.basename(src)} @ "
            f"{example_seed_version(body)}\n"
            f"seed_version: {example_seed_version(body)}\n\n") + body
    tmp = dest + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(body)
    os.replace(tmp, dest)

    # Verify before finishing (SPEC-repo-onboarding CAP-1): a write that did not
    # produce a usable profile is a failure, not a warning.
    profiles, findings = load_profiles(pdir)
    named = [f for f in findings if f[0] == f"{args.platform}.yaml"]
    if named or args.platform not in profiles:
        sys.stderr.write(f"error: seeded {dest} but it does not validate:\n")
        _emit_findings(named or findings)
        return VALIDATION_FAILED
    print(f"seeded: {dest}")
    return 0


def cmd_missing(args):
    """Platform ids declared in `syndication.policy` with no resolvable profile,
    each tagged `seedable` (a shipped example exists) or `no-template`. This is
    the preflight's own answer — the resolver decides what is missing, so no
    caller re-derives it from a second profile check."""
    root = host_root(args.root)
    cfg_args = argparse.Namespace(config_json=None, root=args.root,
                                  global_config=args.global_config,
                                  repo_config=args.repo_config)
    try:
        cfg = uc.resolve(cfg_args)
    except SystemExit:
        cfg = {}
    declared = []
    policy = ((cfg.get("syndication") or {}).get("policy") or {})
    for lang, block in sorted(policy.items()):
        if isinstance(block, dict):
            declared.extend(block.get("variants") or [])
    seed_candidates, live = seedable(root, args.profiles_dir, args.examples_dir)
    for platform in sorted(set(declared)):
        if platform in live:
            continue
        state = "seedable" if platform in seed_candidates else "no-template"
        print(f"{platform}\t{state}")
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
    v = with_dir(sub.add_parser("validate", help="per-key findings, exit 4 if any"))
    v.add_argument("--examples-dir",
                   help="override the shipped examples directory (tests)")
    with_dir(sub.add_parser("dir", help="the resolved profiles directory"))
    g = with_dir(sub.add_parser("get", help="one profile as JSON"))
    g.add_argument("platform")

    s = with_dir(sub.add_parser("seed", help="write one profile from its shipped "
                                             "example (the sanctioned write path)"))
    s.add_argument("platform")
    s.add_argument("--examples-dir",
                   help="override the shipped examples directory (tests)")
    s.add_argument("--force", action="store_true",
                   help="replace an existing profile (default: refuse)")

    m = with_dir(sub.add_parser("missing", help="declared platforms with no "
                                                "resolvable profile, tagged "
                                                "seedable | no-template"))
    m.add_argument("--examples-dir",
                   help="override the shipped examples directory (tests)")
    m.add_argument("--global-config")
    m.add_argument("--repo-config")

    d = sub.add_parser("deprecations", help="legacy syndication.variants.* re-homing pointers")
    d.add_argument("--root", help="host-repo root (default: git toplevel of cwd)")
    d.add_argument("--global-config")
    d.add_argument("--repo-config")
    return p


DISPATCH = {
    "list": cmd_list, "resolved": cmd_resolved, "get": cmd_get,
    "validate": cmd_validate, "dir": cmd_dir, "deprecations": cmd_deprecations,
    "seed": cmd_seed, "missing": cmd_missing,
}


def main(argv=None):
    args = build_parser().parse_args(argv)
    return DISPATCH[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
