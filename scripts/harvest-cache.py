#!/usr/bin/env python3
"""harvest-cache.py — the blob-keyed extraction cache (CAP-10, #516, Story 18.31).

Per-source budgeted extraction (Story 18.30) restructured harvest so the model
extracts one source file at a time. This memoizes that per-source extraction by
the key `(path, blob-sha, extractor-version)` in the path resolver's **state
root** (never the host working tree), so a re-harvest **re-extracts only changed
blobs**: an unchanged file is a cache hit whose entries are reused verbatim, and
"one harvest" becomes an incremental refresh. Run-to-run variance then exists
only where blob content actually changed.

The cache is a conformance copy of extractions whose **authority is the blob**,
so invalidation is by **declared precedence, structural not advisory**: the key
carries both the content identity (`blob-sha` — the git blob object id of the
file's bytes) and the extraction-contract identity (`extractor-version` — a hash
of the extraction contract: `skills/harvest/SKILL.md` §3 procedure + KIND set and
`scripts/validate-fact-sheet.py`). A changed blob or a changed contract yields a
**different key**, so a stale extraction is *never looked up*, let alone served —
there is no version in which the cache can hand back an out-of-date extraction.

Storage: `<repo-dir>/harvest-cache/<key-hash>` (`repo-dir` = the resolver's
per-repo state directory). Cold cache = empty directory = every source a miss =
a first harvest under the per-source budget; the cache is an amortization of
re-reads, never a correctness precondition.

Usage:
  harvest-cache.py extractor-version                 # the current contract hash
  harvest-cache.py blob-sha --path P                 # git blob id of P's bytes
  harvest-cache.py path [--root R]                   # the cache directory
  harvest-cache.py get --root R --path P [--blob-sha S]   # exit 0 + print entries on hit; exit 1 on miss
  harvest-cache.py put --root R --path P [--blob-sha S]    # store stdin entries under the key
  harvest-cache.py key --root R --path P [--blob-sha S]    # print the key hash (debug/tests)

`--blob-sha` defaults to the git blob id of the file's current bytes, so callers
usually omit it; pass it only to key against a specific content revision.
"""
import argparse
import hashlib
import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RESOLVE_PATHS = os.path.join(SCRIPT_DIR, "resolve-paths.py")

# The extraction contract: any change to these files changes what an extraction
# *means*, so it must invalidate every cached extraction. Hashing their bytes is
# the mechanical lockstep the spec requires ("extractor-version bumps whenever
# the extraction contract changes — §3 procedure, KIND set, or validator") — no
# manual version bump to forget.
CONTRACT_FILES = [
    os.path.join(SCRIPT_DIR, "..", "skills", "harvest", "SKILL.md"),
    os.path.join(SCRIPT_DIR, "validate-fact-sheet.py"),
]


def extractor_version():
    h = hashlib.sha256()
    for path in CONTRACT_FILES:
        # A missing contract file is itself a contract state — fold its absence
        # into the hash rather than crashing, so the cache still invalidates
        # deterministically.
        h.update(os.path.basename(path).encode())
        h.update(b"\0")
        try:
            with open(path, "rb") as f:
                h.update(f.read())
        except OSError:
            h.update(b"<absent>")
        h.update(b"\0")
    return h.hexdigest()[:12]


def blob_sha(path):
    """The git blob object id of the file's current bytes — identical to
    `git hash-object <path>`, computed in-process so the cache needs no git."""
    with open(path, "rb") as f:
        data = f.read()
    h = hashlib.sha1()
    h.update(b"blob " + str(len(data)).encode() + b"\0")
    h.update(data)
    return h.hexdigest()


def repo_dir(root):
    cmd = [sys.executable, RESOLVE_PATHS, "repo-dir"]
    if root:
        cmd += ["--root", root]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.stderr.write(out.stderr)
        raise SystemExit(out.returncode)
    return out.stdout.strip()


def cache_dir(root):
    return os.path.join(repo_dir(root), "harvest-cache")


def key_hash(path, bsha, ver):
    # The relative path keeps the key stable across absolute-path differences
    # between machines; blob-sha is content identity; ver is contract identity.
    rel = os.path.basename(path)
    payload = f"{rel}\0{bsha}\0{ver}".encode()
    return hashlib.sha256(payload).hexdigest()


def _resolve_bsha(args):
    return args.blob_sha if args.blob_sha else blob_sha(args.path)


def cmd_extractor_version(args):
    print(extractor_version())
    return 0


def cmd_blob_sha(args):
    print(blob_sha(args.path))
    return 0


def cmd_path(args):
    print(cache_dir(args.root))
    return 0


def cmd_key(args):
    print(key_hash(args.path, _resolve_bsha(args), extractor_version()))
    return 0


def cmd_get(args):
    entry_path = os.path.join(cache_dir(args.root),
                              key_hash(args.path, _resolve_bsha(args), extractor_version()))
    if not os.path.exists(entry_path):
        return 1  # miss — the caller extracts and puts
    with open(entry_path, encoding="utf-8") as f:
        sys.stdout.write(f.read())
    return 0


def cmd_put(args):
    d = cache_dir(args.root)
    os.makedirs(d, exist_ok=True)
    entry_path = os.path.join(d, key_hash(args.path, _resolve_bsha(args), extractor_version()))
    data = sys.stdin.read()
    with open(entry_path, "w", encoding="utf-8") as f:
        f.write(data)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("extractor-version", help="print the current extractor-version (contract hash)")

    sp = sub.add_parser("blob-sha", help="print the git blob id of a file's bytes")
    sp.add_argument("--path", required=True)

    sp = sub.add_parser("path", help="print the cache directory")
    sp.add_argument("--root")

    for name, help_ in (("get", "print cached entries on hit (exit 0), else exit 1"),
                        ("put", "store stdin entries under the key"),
                        ("key", "print the key hash")):
        sp = sub.add_parser(name, help=help_)
        sp.add_argument("--root")
        sp.add_argument("--path", required=True)
        sp.add_argument("--blob-sha", dest="blob_sha", default=None)

    args = p.parse_args(argv)
    return {
        "extractor-version": cmd_extractor_version,
        "blob-sha": cmd_blob_sha,
        "path": cmd_path,
        "get": cmd_get,
        "put": cmd_put,
        "key": cmd_key,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
