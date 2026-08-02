#!/usr/bin/env python3
"""Derive a `# covers:` declaration for a check from the check's own text (#1318).

WHY DERIVE RATHER THAN HAND-AUTHOR. `--changed` selection (#998) runs the union
of the name-prefix family and every check whose `# covers:` globs match a
changed path. 135 of 170 checks declare nothing, so they are reachable by
prefix only — four of the five defects that reached the full tier in the
2026-08-02 sitting were in undeclared checks, including a publication-boundary
violation a scoped run structurally could not see. The obvious remedy is 135
hand-authored declarations; the owner declined it. A hand-authored declaration
is an independent judgement that can be wrong at birth and drifts silently
afterwards, and a declaration that drifts reads as coverage while covering
nothing. A check ALREADY names the paths it reads — it just does not name them
as coverage. A declaration derived from the check's own text sits next to the
text it derives from, so a wrong one is visible in review of that file.

WHY STATIC AND NOT AN INSTRUMENTED RUN. Observing a check's real reads cannot
drift by construction, which is the stronger property — but it costs an
instrumented full-tier run per regeneration, and the full-tier checks are
precisely the ones that take minutes. This pass is cheap enough to re-run on
every edit, so the derivation stays live. The price is stated below and is not
hidden: static extraction cannot see a path assembled at runtime.

WHAT IT CANNOT SEE, AND WHY THAT IS FLAGGED RATHER THAN GUESSED. A path built
from a variable (`"$d"/SKILL.md` over a directory list), a glob assembled from
parts, or a tree walk in embedded Python leaves no literal token to extract.
Emitting the narrow set anyway would be the worst outcome available: it reads
as coverage, and it is the failure mode the owner rejected hand-authoring to
avoid. So a derivation carrying any such signal is emitted in the REVIEW tier
and flagged with the reason, for a human to widen or confirm. Confidence is a
property of the DERIVATION, never of the check.

THE THREE SIGNALS (any one demotes a proposal to REVIEW):

  dynamic-path   the check uses a variable in path position whose value is not
                 resolvable to a literal in the file, and is not the repo root
                 or a mktemp workspace. The extractor cannot see through it.
  sparse         the extracted set is small relative to the check's size. A
                 400-line check asserting over two files is possible; it is
                 also exactly what a mostly-dynamic check looks like, so the
                 ratio buys a human look rather than a verdict.
  broad-only     everything that survived is a top-level directory. Sometimes
                 correct (a whole-tree scanner really does cover the tree) but
                 a broad declaration makes the check run on nearly every edit,
                 which is a cost a human should accept deliberately.

WRITES NOTHING BY DEFAULT. `--apply` writes, and refuses without `--only`: the
owner ratifies in batches, so a blanket apply is not an available motion here.

Usage:
    scripts/derive-check-coverage.py                    # propose, all undeclared
    scripts/derive-check-coverage.py --tier high        # only high-confidence
    scripts/derive-check-coverage.py --counts           # tier counts only
    scripts/derive-check-coverage.py --only check-x.sh check-y.sh --apply

Exit 0 on a clean pass, 2 on a usage error. Proposing is never a failure.
"""

from __future__ import annotations

import argparse
import fnmatch
import re
import subprocess
import sys
from pathlib import Path

# The prefixes a coverage glob can start with — the tracked top-level trees a
# check can assert over. A token outside these is not a repo path.
ROOTS = ("scripts", "skills", "specs", "docs", "config", "tests", ".claude")

PATH_TOKEN = re.compile(
    r"(?<![\w.-])(?:" + "|".join(re.escape(r) for r in ROOTS) + r")/[A-Za-z0-9_.*/-]*"
)
ASSIGN = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
VAR_IN_PATH = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?/")
VAR_REF = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")

# Variables whose path-position use tells us nothing: the repo root (every
# check computes it the same way) and the conventional loop cursors that run
# over a list the extractor has already read literally.
BENIGN_VARS = {"root", "TMPDIR", "HOME", "PWD"}

# Sparse signal: fewer than one extracted path per this many lines.
SPARSE_LINES_PER_PATH = 120
# ...but a short check with even one path is not sparse. Below this length the
# ratio is noise.
SPARSE_MIN_LINES = 60


def repo_root() -> Path:
    out = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=True,
    )
    return Path(out.stdout.strip())


def declared(text: str) -> bool:
    return any(ln.startswith("# covers:") for ln in text.splitlines())


def _literal_vars(text: str) -> tuple[set[str], set[str]]:
    """(resolvable, workspace) variable names.

    resolvable — assigned a value that reduces to a literal string, so any path
    inside it was already extracted from the assignment line.
    workspace   — rooted at mktemp or at the repo root, i.e. a scratch or
    repo-relative prefix that carries no coverage information of its own.
    """
    assigns: dict[str, str] = {}
    for line in text.splitlines():
        m = ASSIGN.match(line)
        if m and not line.lstrip().startswith("#"):
            assigns.setdefault(m.group(1), m.group(2))

    workspace = {"root"}
    resolvable: set[str] = set()
    for _ in range(4):  # fixpoint; the chains here are two or three deep
        for name, rhs in assigns.items():
            if "mktemp" in rhs:
                workspace.add(name)
                continue
            refs = set(VAR_REF.findall(rhs))
            if refs & workspace:
                workspace.add(name)
            if "$" not in rhs and "`" not in rhs:
                resolvable.add(name)
            elif refs and refs <= (resolvable | workspace) and "$(" not in rhs:
                resolvable.add(name)
    return resolvable, workspace


def _dynamic_vars(text: str) -> list[str]:
    """Variables used in path position that the extractor cannot see through."""
    resolvable, workspace = _literal_vars(text)
    seen = []
    for name in VAR_IN_PATH.findall(text):
        if name in BENIGN_VARS or name in workspace or name in resolvable:
            continue
        if name not in seen:
            seen.append(name)
    return seen


def _clean_token(tok: str, root: Path, self_stem: str) -> str | None:
    """A raw token to an emittable glob, or None if it is not a real path.

    Existence in the tree is the filter that kills prose fragments: a check's
    own commentary produces `specs/-only` and `fixtures/docs`, neither of which
    is a path. A token carrying a `*` is kept without an existence test — it is
    already a glob, and the check meant it as one.
    """
    tok = tok.rstrip("/.,;:'\")-")
    if not tok:
        return None
    if "/" not in tok:
        # A bare top-level tree (`docs/`, `scripts/`). Kept only as a fallback
        # by the caller — see the `deep` split in derive().
        return tok + "/**" if (root / tok).is_dir() else None
    if tok.startswith(f"scripts/{self_stem}"):
        return None  # the check's own file: the name-prefix selector owns it
    if "*" in tok:
        return tok
    p = root / tok
    if p.is_dir():
        return tok.rstrip("/") + "/**"
    if p.exists():
        return tok
    return None


def _subsumed(glob: str, others: list[str]) -> bool:
    for o in others:
        if o == glob:
            continue
        if fnmatch.fnmatch(glob, o) or (o.endswith("/**") and glob.startswith(o[:-2])):
            return True
    return False


class Proposal:
    def __init__(self, path: Path, globs: list[str], flags: list[str]):
        self.path = path
        self.globs = globs
        self.flags = flags

    @property
    def tier(self) -> str:
        if not self.globs:
            return "none"
        return "review" if self.flags else "high"

    @property
    def line(self) -> str:
        return "# covers: " + " ".join(self.globs)


def derive(path: Path, root: Path) -> Proposal:
    text = path.read_text(encoding="utf-8", errors="replace")
    self_stem = path.name[: -len(".sh")] if path.name.endswith(".sh") else path.name

    # Deep tokens (`skills/terrain/SKILL.md`) are the signal. A bare top-level
    # tree (`docs/`) is used ONLY when nothing deeper survived: alongside real
    # paths it is almost always prose ("...or under scripts/..."), while alone
    # it is usually a whole-tree scanner naming its trees, which is coverage.
    deep: list[str] = []
    top: list[str] = []
    for tok in PATH_TOKEN.findall(text):
        g = _clean_token(tok, root, self_stem)
        if not g:
            continue
        bucket = top if g.count("/") == 1 and g.endswith("/**") else deep
        if g not in bucket:
            bucket.append(g)
    globs = deep or top
    globs = [g for g in globs if not _subsumed(g, globs)]
    globs.sort()

    flags: list[str] = []
    dyn = _dynamic_vars(text)
    if dyn:
        flags.append("dynamic-path:" + ",".join(dyn[:4]))

    nlines = len(text.splitlines())
    if nlines >= SPARSE_MIN_LINES and len(globs) * SPARSE_LINES_PER_PATH < nlines:
        flags.append(f"sparse:{len(globs)}-paths/{nlines}-lines")

    if globs and all(g.count("/") == 1 and g.endswith("/**") for g in globs):
        flags.append("broad-only")

    return Proposal(path, globs, flags)


def insert_declaration(path: Path, line: str) -> None:
    """Write the declaration into the header block, next to the other headers.

    Placed after the last leading `#` comment line that is a declaration
    (`# parallel-safe`, `# serial-reason:`, `# tier:`) so the three read
    together; failing that, immediately after the shebang. run-checks.sh takes
    the first `# covers:` line anywhere in the file, so position is for the
    human, not the parser.
    """
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    anchor = 0
    for i, ln in enumerate(lines[:25]):
        if ln.startswith("#!"):
            anchor = max(anchor, i + 1)
        if re.match(r"^# (parallel-safe|serial-reason:|tier:)", ln):
            anchor = i + 1
    lines.insert(anchor, line + "\n")
    path.write_text("".join(lines), encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", nargs="+", metavar="NAME",
                    help="derive for these check basenames only (required by --apply)")
    ap.add_argument("--tier", choices=["high", "review", "none", "all"], default="all",
                    help="report only this confidence tier (default all)")
    ap.add_argument("--counts", action="store_true", help="tier counts only")
    ap.add_argument("--apply", action="store_true",
                    help="write the derived declaration into each named check")
    args = ap.parse_args()

    root = repo_root()
    checks = sorted((root / "scripts").glob("check-*.sh"))
    if args.only:
        want = {n if n.endswith(".sh") else n + ".sh" for n in args.only}
        want = {Path(n).name for n in want}
        checks = [c for c in checks if c.name in want]
        missing = want - {c.name for c in checks}
        if missing:
            print(f"derive-check-coverage: no such check(s): {', '.join(sorted(missing))}",
                  file=sys.stderr)
            return 2

    if args.apply and not args.only:
        print("derive-check-coverage: --apply requires --only naming the batch.\n"
              "  Declarations are ratified in batches, so a blanket apply is not\n"
              "  an available motion: name the checks you have verified (#1318).",
              file=sys.stderr)
        return 2

    proposals = []
    for c in checks:
        text = c.read_text(encoding="utf-8", errors="replace")
        if declared(text):
            continue
        proposals.append(derive(c, root))

    counts = {"high": 0, "review": 0, "none": 0}
    for p in proposals:
        counts[p.tier] += 1

    if args.apply:
        wrote = 0
        for p in proposals:
            if not p.globs:
                print(f"skip: {p.path.name} — nothing derivable, hand-author it", file=sys.stderr)
                continue
            insert_declaration(p.path, p.line)
            print(f"applied: {p.path.relative_to(root)}  {p.line}")
            wrote += 1
        already = len(checks) - len(proposals)
        if already:
            print(f"note: {already} of the named check(s) already declare '# covers:' — left alone")
        print(f"derive-check-coverage: applied {wrote} declaration(s)")
        return 0

    if not args.counts:
        for tier in ("high", "review", "none"):
            if args.tier not in (tier, "all"):
                continue
            group = [p for p in proposals if p.tier == tier]
            if not group:
                continue
            print(f"=== {tier.upper()} ({len(group)}) ===")
            for p in group:
                print(f"{p.path.relative_to(root)}")
                if p.globs:
                    print(f"    {p.line}")
                else:
                    print("    (no derivable path token — hand-author or delete)")
                if p.flags:
                    print(f"    flags: {' '.join(p.flags)}")
            print()

    total = len(proposals)
    declared_n = sum(1 for c in (root / "scripts").glob("check-*.sh")
                     if declared(c.read_text(encoding="utf-8", errors="replace")))
    print(f"derive-check-coverage: {declared_n} check(s) already declare; "
          f"{total} undeclared -> high={counts['high']} review={counts['review']} "
          f"none={counts['none']} (#1318)")
    print("derive-check-coverage: proposal only — nothing written. "
          "Apply a ratified batch with --only <names> --apply")
    return 0


if __name__ == "__main__":
    sys.exit(main())
