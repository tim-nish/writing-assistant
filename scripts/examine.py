#!/usr/bin/env python3
"""examine.py — the repository answers a stated question (Story 20.147, #1182).

Adopted from its prototype hold by the 2026-08-02 amendment
(specs/spec-writing-assistant/amendments.md, #1182/#1097/#1185/#1209): per-claim
`examine` is the stage-3+ grounding step now that harvest is retired. The
hypothesis it was built to test is ratified upstream (owner decision record —
2026-08-01 (retrieval direction: thesis-first examination)):

    Retrieval against an unstated query is the hard direction. A stage that
    reads the repository BEFORE the article's thesis exists must anticipate
    every question the thesis will later raise, which is why harvest was
    scoped to 358 files to serve a thesis about five mechanisms. Reading the
    repository AFTER a claim exists is bounded, scoreable, and fails honestly.

So this tool takes a CLAIM and returns pinned candidate evidence for it. It is
the oracle half of "the repository is a witness, not a granary".

SCOPE IS DERIVED, NOT CHOSEN (#1097, #1185)
-------------------------------------------
When the brief carries a derived `harvest_scope` (the union of the selected
Strands' served `projects:` — `scripts/terrain_scope.py`), pass it via
`--scope` (and `--member` for a per-Strand examination): a repository outside
the served attribution is REFUSED, NOT SEARCHED — grounding a claim in a
repository the experience did not happen in is a false attribution, the
read-side counterpart of the hub's write-side deny rule. The refusal logic is
consumed from `terrain_scope.py`, never restated here. Without `--scope`
(a run whose brief carries none), the declared-source boundary of `--root`
is the only fence, exactly as before.

WHAT IT DELIBERATELY DOES NOT DO
--------------------------------
**It does not judge.** `verdict` is always null on the way out. Deciding
whether the evidence supports, refutes, or misses the claim is the model's
job, and a script that guessed would recreate harvest's error one layer down —
a mechanism reporting a conclusion it cannot actually establish. The tool's
whole contract is: given a question, return material that bears on it, each
item pinned and time-stamped, and say what it searched.

THE TIME AXIS IS THE TYPE
-------------------------
Every item carries `time_axis: true|false`, and that is the load-bearing field:

  * `commit`  — a change plus its stated reason. Native time axis.
  * `issue`   — a problem, its deliberation, and its resolution over a thread.
    Native time axis.
  * `prose`   — a declared document at HEAD. Describes the CURRENT STATE and
    was not written to record how the position moved. `time_axis: false`, and
    the caller may ground a state claim in it but never an episode claim.

That distinction is the finding this prototype exists to operationalise: a
document written for its own purpose does not carry the causal history an
episode needs, and depending on extracting it "will vary according to the
circumstances of the source" (owner, 2026-08-01).

COVERAGE IS REPORTED, NEVER IMPLIED
-----------------------------------
`searched` names every source actually consulted and `skipped` names every one
that was not, with the reason. An empty result from a source that was never
reachable is not the same finding as an empty result from a source that was
read — the journey join asserted absence from a search over zero bytes (#1181)
precisely because it did not keep those apart.
"""

import argparse
import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
SRC_RES = os.path.join(SCRIPT_DIR, "resolve-writing-sources.py")
sys.path.insert(0, SCRIPT_DIR)
import terrain_scope  # noqa: E402 — the ONE refusal layer (#1185), consumed not restated

STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "is", "are", "was", "were", "be",
    "been", "being", "to", "of", "in", "on", "at", "by", "for", "with", "from",
    "that", "this", "these", "those", "it", "its", "as", "not", "no", "so",
    "than", "then", "when", "where", "which", "who", "what", "how", "why",
    "can", "cannot", "could", "would", "should", "will", "shall", "may",
    "might", "must", "does", "do", "did", "has", "have", "had", "one", "two",
    "every", "any", "all", "each", "only", "never", "always", "still", "even",
}


def run(cmd, cwd=None, timeout=60):
    """Run a command, returning (ok, stdout, stderr). Never raises — an
    unavailable tool is a coverage fact to report, not a crash."""
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                           timeout=timeout)
        return r.returncode == 0, r.stdout, r.stderr.strip()
    except FileNotFoundError:
        return False, "", f"{cmd[0]} not found"
    except subprocess.TimeoutExpired:
        return False, "", f"{cmd[0]} timed out after {timeout}s"


def terms_from_claim(claim, limit=6):
    """Content words from the claim, longest first.

    Deliberately naive: term selection is a place where a clever heuristic
    would silently narrow what the repository is allowed to say, and the
    caller can always pass --terms explicitly. Length-first is a transparent
    rule the caller can predict and override.
    """
    words = re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}", claim.lower())
    seen, out = set(), []
    for w in sorted(set(words), key=lambda w: -len(w)):
        if w in STOPWORDS or w in seen:
            continue
        seen.add(w)
        out.append(w)
    return out[:limit]


def head_sha(root):
    ok, out, _ = run(["git", "rev-parse", "--short", "HEAD"], cwd=root)
    return out.strip() if ok else "unknown"


def parse_anchors(raw):
    """`path:…`, `symbol:…`, `ref:…`, `since:…`, `until:…` — the addresses a
    commit query is allowed to be built from."""
    out = {"path": [], "symbol": [], "ref": [], "since": None, "until": None}
    for a in raw:
        kind, _, value = a.partition(":")
        kind, value = kind.strip().lower(), value.strip()
        if not value or kind not in out:
            raise SystemExit(
                f"unusable anchor {a!r} — expected path:<glob>, symbol:<text>, "
                f"ref:<sha|#123>, since:<date> or until:<date>")
        if kind in ("since", "until"):
            out[kind] = value
        else:
            out[kind].append(value)
    return out


def examine_commits(root, anchors, limit):
    """History, reached BY ANCHOR — never by keyword over commit messages.

    THIS IS THE CORRECTION THE OWNER MADE ON 2026-08-01, and it is the whole
    difference between this design and the one it replaces. Two properties of
    a source were conflated in the first draft:

      * whether it carries a TIME AXIS — which decides what class of claim it
        may ground;
      * how you REACH the right part of it — which decides whether it can be
        the first thing you look at.

    Commits carry a time axis and are **not content-addressable**: a commit
    message is ad-hoc prose written for another purpose, so searching it by
    the claim's keywords is the same unstated-query retrieval that harvest
    was, one corpus over. Measured on this repo: a claim containing the word
    "write" returned three unrelated commits, all with a time axis, all
    useless.

    So history answers ONE question — *how did THIS come to be?* — and it can
    only be asked once `THIS` has an address: a path, a symbol, a commit or
    issue reference, or a time window. Without one, this source is SKIPPED and
    says so; it does not fall back to searching, because a fallback here would
    quietly restore the thing being removed.
    """
    has = (anchors["path"] or anchors["symbol"] or anchors["ref"]
           or anchors["since"] or anchors["until"])
    if not has:
        return [], ("commits are anchor-addressed: supply path:, symbol:, "
                    "ref:, since: or until:. History answers 'how did THIS "
                    "come to be' and cannot be searched by claim keywords")
    items = []
    cmd = ["git", "log", "--no-merges", f"-{limit}", "--date=short",
           "--format=%x00%H%x01%h%x01%ad%x01%an%x01%s%x01%b"]
    if anchors["since"]:
        cmd.append(f"--since={anchors['since']}")
    if anchors["until"]:
        cmd.append(f"--until={anchors['until']}")
    for s in anchors["symbol"]:
        # -S is a pickaxe over the DIFF, not the message: it finds the commits
        # where this string entered or left the code, which is a fact about
        # the change rather than about how someone described it.
        cmd.append(f"-S{s}")
    for r in anchors["ref"]:
        # An identifier lookup is not keyword retrieval: `#1145` is a stable
        # address that means one thing, so matching it in a message is a join,
        # not a guess.
        cmd += ["--grep", re.escape(r), "--regexp-ignore-case"]
    if anchors["path"]:
        cmd.append("--")
        cmd += anchors["path"]
    ok, out, err = run(cmd, cwd=root)
    if not ok:
        return [], f"git log failed: {err}"
    for rec in out.split("\x00"):
        if not rec.strip():
            continue
        parts = rec.split("\x01")
        if len(parts) < 6:
            continue
        full, short, date, author, subject, body = parts[:6]
        ok2, files, _ = run(
            ["git", "show", "--name-only", "--format=", full], cwd=root)
        touched = [f for f in files.splitlines() if f.strip()][:12] if ok2 else []
        items.append({
            "source_type": "commit",
            "time_axis": True,
            "addressing": "anchored",
            "reached_by": anchors,
            "when": date,
            "pin": f"{os.path.basename(root)}@{short}",
            "ref": short,
            # The pointer form the provenance map cites (a bare sha —
            # `verify-provenance` types it as a time-axis source, #1184).
            "cite": short,
            "author": author,
            "title": subject,
            "excerpt": body.strip()[:1200],
            "touched": touched,
        })
    return items, None


def anchors_offered(evidence):
    """Addresses a SECOND hop could use, harvested from the first hop's hits.

    This is the seam that makes the two-hop shape work in practice: a
    searchable source (an issue thread, a prose hit) is where an address comes
    from, and history is what you ask once you have one. Offered, never
    followed — deciding which anchor is worth a second query is a judgment,
    and this tool does not make judgments.
    """
    paths, refs = set(), set()
    for e in evidence:
        if e["source_type"] == "prose":
            paths.add(e["ref"])
        text = " ".join(filter(None, [
            e.get("excerpt", ""), e.get("title", ""),
            " ".join(t.get("excerpt", "") for t in e.get("thread", []))]))
        for m in re.findall(r"\b(?:[\w.-]+/)+[\w.-]+\.(?:py|sh|md|yaml|json)\b", text):
            paths.add(m)
        for m in re.findall(r"#\d{2,6}\b", text):
            refs.add(m)
        for m in re.findall(r"\b[0-9a-f]{7,40}\b", text):
            refs.add(m)
    return ([f"path:{p}" for p in sorted(paths)[:12]]
            + [f"ref:{r}" for r in sorted(refs)[:12]])


def examine_issues(root, terms, limit, with_comments):
    """Issues and their threads. A thread is a position moving in public —
    the problem, the deliberation, and what was decided, in order."""
    if not terms:
        return [], "no terms to search issues with"
    query = " ".join(terms[:4])
    ok, out, err = run(
        ["gh", "issue", "list", "--state", "all", "--limit", str(limit),
         "--search", query, "--json", "number,title,body,createdAt,updatedAt,url,state,labels"],
        cwd=root, timeout=90)
    if not ok:
        return [], f"gh issue list failed: {err[:200]}"
    try:
        rows = json.loads(out)
    except ValueError:
        return [], "gh returned unparseable JSON"
    items = []
    for r in rows:
        item = {
            "source_type": "issue",
            "time_axis": True,
            "when": (r.get("createdAt") or "")[:10],
            "pin": r.get("url"),
            "cite": r.get("url"),   # URL pointer form for the provenance map
            "ref": f"#{r.get('number')}",
            "state": r.get("state"),
            "labels": [l["name"] for l in (r.get("labels") or [])],
            "title": r.get("title"),
            "excerpt": (r.get("body") or "").strip()[:1200],
            "thread": [],
        }
        if with_comments:
            # THE READ INCLUDES THE THREAD. A body-only projection of an issue
            # is a marked partial: the decision usually lives in the comments,
            # which is exactly the property that makes an issue an episode
            # source rather than another state document.
            ok2, cout, _ = run(
                ["gh", "issue", "view", str(r["number"]), "--json", "comments"],
                cwd=root, timeout=60)
            if ok2:
                try:
                    for c in json.loads(cout).get("comments", []):
                        item["thread"].append({
                            "when": (c.get("createdAt") or "")[:10],
                            "excerpt": (c.get("body") or "").strip()[:800],
                        })
                except ValueError:
                    pass
            else:
                item["thread_unavailable"] = True
        items.append(item)
    return items, None


def declared_prose(root):
    ok, out, _ = run([sys.executable, SRC_RES, "--root", root, "files"])
    if not ok:
        return []
    # The enumerator prints one absolute path per line (it is the single source
    # of truth for what "declared" means — this tool never re-derives it).
    return [ln.strip() for ln in out.splitlines() if ln.strip()]


def examine_prose(root, terms, limit):
    """Declared documents at HEAD. STATE-ONLY by construction: these describe
    the position as it stands, not how it moved, so they are returned with
    `time_axis: false` and the caller must not ground an episode in them."""
    files = declared_prose(root)
    if not files:
        return [], "no declared path sources resolved"
    prose = [f for f in files if f.endswith((".md", ".txt", ".rst"))]
    items, sha = [], head_sha(root)
    pat = re.compile("|".join(re.escape(t) for t in terms), re.I) if terms else None
    for path in prose:
        if len(items) >= limit:
            break
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for n, line in enumerate(lines, 1):
            if pat and pat.search(line):
                rel = os.path.relpath(path, root)
                items.append({
                    "source_type": "prose",
                    "time_axis": False,
                    "when": f"state at {sha}",
                    "pin": f"{rel}:{n}@{sha}",
                    "cite": f"{rel}:{n}@{sha}",   # path:line@sha pointer form
                    "ref": rel,
                    "title": rel,
                    "excerpt": line.strip()[:600],
                    "admissible_for": "state claims only — not an episode source",
                })
                break   # one hit per file; the caller reads the file if it wants more
    return items, None


def _scope_refusal(scope_path, member_index, repository):
    """The derived-scope binding (#1097/#1185), consumed from terrain_scope.

    `scope_path` is JSON carrying the brief's `harvest_scope` block (either
    the block itself or an object holding it under that key). Returns None
    when `repository` is within the served scope; otherwise the refusal dict
    — refused, not searched. With `--member`, the refusal is per-Strand
    (`terrain_scope.examination_refusal`, naming the Strand and its served
    attribution); otherwise the test is membership in the union."""
    try:
        with open(scope_path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as e:
        raise SystemExit(f"unreadable --scope {scope_path!r}: {e}")
    block = data.get("harvest_scope", data) if isinstance(data, dict) else None
    if not isinstance(block, dict) or "projects" not in block:
        raise SystemExit(f"--scope {scope_path!r} carries no harvest_scope "
                         "block (no `projects` key)")
    if member_index is not None:
        vals = next((b["projects"] for b in block.get("by_member", [])
                     if str(b.get("index")) == str(member_index)), None)
        member = {"index": member_index,
                  "projects": ({"served": True, "values": vals}
                               if vals is not None
                               else {"served": bool(block.get("served"))})}
        return terrain_scope.examination_refusal(member, repository)
    if not block.get("served") or not isinstance(block.get("projects"), list):
        return {"refused": True, "attribution": None,
                "line": (f"examination against {repository} is refused: the "
                         "brief's harvest_scope is not served at this pin — "
                         "cannot-determine, never searched on a guess")}
    if repository in block["projects"]:
        return None
    vals = [v for v in block["projects"]
            if v not in terrain_scope.RECOGNIZED_NON_REPO]
    return {"refused": True, "attribution": list(block["projects"]),
            "line": (f"examination against {repository} is refused, not "
                     f"searched: the derived scope names "
                     f"{', '.join(vals) or 'no repository'} — grounding a "
                     "claim in a repository the experience did not happen in "
                     "is a false attribution")}


def _record(ws, out):
    """Persist the examination AT THE READ THAT PRODUCED IT (AC1): the full
    record under $WS/examinations/, and every citable pin appended to the
    run's pin ledger ($WS/examination-pins.txt — the declared pointer set
    `verify-provenance` resolves sourced/derived claims against)."""
    exdir = os.path.join(ws, "examinations")
    os.makedirs(exdir, exist_ok=True)
    slug = re.sub(r"[^a-z0-9]+", "-", out["claim"].lower()).strip("-")[:60]
    path = os.path.join(exdir, f"{slug or 'claim'}.json")
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
    ledger = os.path.join(ws, "examination-pins.txt")
    have = set()
    if os.path.isfile(ledger):
        with open(ledger, encoding="utf-8") as fh:
            have = {ln.strip() for ln in fh if ln.strip()}
    with open(ledger, "a", encoding="utf-8") as fh:
        for e in out["evidence"]:
            c = e.get("cite")
            if c and c not in have:
                fh.write(c + "\n")
                have.add(c)
    return {"record": path, "pin_ledger": ledger}


def main():
    p = argparse.ArgumentParser(
        description="Ask the repository about ONE claim. Returns pinned "
                    "material; never a verdict.")
    p.add_argument("--root", default=".", help="host repository")
    p.add_argument("--claim", required=True,
                   help="the concrete claim to be tested, in one sentence")
    p.add_argument("--scope",
                   help="JSON file carrying the brief's derived harvest_scope "
                        "(#1097/#1185); a repository outside it is refused, "
                        "not searched (exit 3)")
    p.add_argument("--member",
                   help="the selected Strand index this claim belongs to — "
                        "makes the scope refusal per-Strand, naming its "
                        "served attribution")
    p.add_argument("--ws",
                   help="run workspace: persist the examination under "
                        "$WS/examinations/ and append pins to "
                        "$WS/examination-pins.txt at the read (AC1)")
    p.add_argument("--terms", default="",
                   help="comma-separated search terms; derived from the claim "
                        "when omitted")
    p.add_argument("--sources", default="commits,issues,prose",
                   help="which source classes to consult")
    p.add_argument("--anchor", action="append", default=[],
                   help="address for the commits source, repeatable: "
                        "path:<glob> | symbol:<text> | ref:<sha|#123> | "
                        "since:<date> | until:<date>. Commits are SKIPPED "
                        "without one — history is not keyword-searchable")
    p.add_argument("--limit", type=int, default=15, help="per-source cap")
    p.add_argument("--no-thread", action="store_true",
                   help="skip issue comments (a marked partial)")
    args = p.parse_args()

    root = os.path.abspath(args.root)
    if args.scope:
        refusal = _scope_refusal(args.scope, args.member,
                                 os.path.basename(root))
        if refusal is not None:
            # REFUSED, NOT SEARCHED (#1185): nothing is consulted, and the
            # refusal says so — this is not a coverage finding, it is the
            # oracle binding holding.
            print(json.dumps({
                "claim": args.claim,
                "repo": os.path.basename(root),
                "refusal": refusal,
                "verdict": None,
                "verdict_owner": "the model that stated the claim",
                "searched": [],
                "skipped": [{"source": s, "reason": refusal["line"]}
                            for s in ("commits", "issues", "prose")],
                "evidence": [],
            }, indent=2))
            return 3
    want = {s.strip() for s in args.sources.split(",") if s.strip()}
    terms = ([t.strip() for t in args.terms.split(",") if t.strip()]
             or terms_from_claim(args.claim))

    anchors = parse_anchors(args.anchor)
    evidence, searched, skipped = [], [], []
    if "commits" in want:
        items, why = examine_commits(root, anchors, args.limit)
        (searched if why is None else skipped).append(
            {"source": "commits", "reason": why} if why else
            {"source": "commits", "found": len(items)})
        evidence += items
    if "issues" in want:
        items, why = examine_issues(root, terms, args.limit, not args.no_thread)
        (searched if why is None else skipped).append(
            {"source": "issues", "reason": why} if why else
            {"source": "issues", "found": len(items),
             "thread_included": not args.no_thread})
        evidence += items
    if "prose" in want:
        items, why = examine_prose(root, terms, args.limit)
        (searched if why is None else skipped).append(
            {"source": "prose", "reason": why} if why else
            {"source": "prose", "found": len(items)})
        evidence += items

    episode_items = [e for e in evidence if e["time_axis"]]
    out = {
        "claim": args.claim,
        "terms": terms,
        "repo": os.path.basename(root),
        "head": head_sha(root),
        # NEVER FILLED HERE. The caller judges; see the module docstring.
        "verdict": None,
        "verdict_owner": "the model that stated the claim",
        "searched": searched,
        "skipped": skipped,
        "counts": {
            "total": len(evidence),
            "time_axis": len(episode_items),
            "state_only": len(evidence) - len(episode_items),
        },
        "coverage_claim": (
            "what this run consulted is exactly `searched`; anything in "
            "`skipped` was not read, and an empty result there is not an "
            "absence finding"),
        # THE SECOND HOP, OFFERED. Empty on a run that found no addresses,
        # which is itself the useful signal: nothing here can be traced
        # through history yet, so a commits query would be a guess.
        "anchors_offered": anchors_offered(evidence),
        "evidence": evidence,
    }
    if args.ws:
        out["recorded"] = _record(args.ws, out)
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
