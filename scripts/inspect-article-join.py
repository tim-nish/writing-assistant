#!/usr/bin/env python3
"""inspect-article-join — the per-paragraph Evidence / Gloss / consumption view
(Story 18.118, #725).

READ-ONLY. It writes nothing to the articles repo and nothing to the hub; the
report goes to stdout (or to `--out`, a path the caller chooses). The footprint
invariant is not merely respected here, it is the reason this is a report rather
than a pipeline stage.

WHY THIS EXISTS
---------------
A `draft-article` run reported "every core lesson has been consumed" while the
owner's lived estimate was that under 10% of the lessons learned building Tanuki
had reached an article. Both claims can be true because they measure different
universes, and nothing put them side by side at the prose level. This renders,
per paragraph:

  (a) the Evidence pointers its sentences carry   -> the provenance map
  (b) the hub Gloss Lesson entries that overlap   -> see THE THIRD LEG below
  (c) the article-level consumption claim          -> the plan's `consumed:`

THE THREE JOINS, AND WHICH ARE COMPUTABLE
-----------------------------------------
1. CLAIM-LEVEL (computable). The sidecar provenance map addresses sentences as
   `P<n>.S<n>[L<line>]` and carries each `sourced`/`derived` claim's pointers
   (`scripts/verify-provenance.py:16-22`). The `[L<line>]` anchor is the draft
   line, which is what makes a *paragraph*-level view possible at all: the
   paragraph's section is the nearest preceding `##`/`###` heading in the draft.
   No new persisted field is needed — the join key already ships.

2. ARTICLE-LEVEL (computable, but from PROSE). `consumed:` in `plans/<slug>.md`
   is the only consumption record, keyed by story-element id
   (`scripts/write-article-plan.py:115-122`). The mapping from an element id to
   its Evidence pointers, however, lives in the plan's `# Editorial decisions`
   BODY as free text, not in a declared field — so this script parses prose, and
   a plan that phrases it differently degrades to "no declared evidence" rather
   than silently to "no match". That difference is disclosed per element.

3. HUB GLOSS (NOT computable — reported as cannot-determine). See below.

THE THIRD LEG
-------------
Leg (b) cannot be computed from the consumer side, and this script refuses to
render its absence as "none".

The served lessons index gives one line per lesson in the declared format
`- [one_liner](lessons/<slug>.md) — <status> | tags: <t1, t2> | YYYY-MM-DD`
(`LESSONS.md:9`). That line carries NO Evidence pointers. The pointers live in
the lesson body (`lessons/<slug>.md`), which the seam does not serve — the
consumer spec records this as its own open question (SPEC-terrain OQ3).

So an empty leg (b) is `cannot-determine`, never `absent`. Rendering it as
"none" would assert an absence that was never established — the exact
three-valued discipline the terrain spec applies to its own verdicts. Supply
`--gloss-entries FILE` (JSON: `{"<lesson-slug>": ["<pointer>", ...]}`) when the
pointers are obtained by some other sanctioned route, and the leg becomes
computable for exactly the entries supplied; everything else stays
cannot-determine.

USAGE
  inspect-article-join.py --slug <slug> --articles-repo <path> --host-root <path>
                          [--gloss-entries <json>] [--out <path>]
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RESOLVE_PATHS = os.path.join(HERE, "resolve-paths.py")

# `P4.S2[L32]: derived <- ptr, ptr` — the `[L<line>]` group is optional because
# the pre-v2 map shape omits it; without it the section join degrades and is
# disclosed rather than guessed.
MAP_LINE = re.compile(
    r"^P(?P<para>\d+)\.S(?P<sent>\d+)"
    r"(?:\[L(?P<line>\d+)\])?"
    r"\s*:\s*(?P<kind>sourced|derived|narration|verify)"
    r"(?:\s*<-\s*(?P<ptrs>.+))?\s*$"
)

# A source pointer: `path:line@sha` / `path:line-line@sha`, or the `den:` ledger
# form. Deliberately permissive on the path so an unexpected shape is reported
# as an unparsed pointer rather than silently dropped.
POINTER = re.compile(r"(?:den:[^\s,]+|[^\s,]+:\d+(?:-\d+)?@[0-9a-f]{7,40})")

ELEMENT_HEAD = re.compile(r"^-\s+(?P<id>el-[a-z0-9-]+)\b")


def die(msg):
    sys.stderr.write("error: %s\n" % msg)
    raise SystemExit(2)


def split_frontmatter(text):
    """Return (frontmatter_text, body_text). No YAML dependency — the plan's
    frontmatter is flat scalars plus one flow list, which is all this reads."""
    if not text.startswith("---"):
        return "", text
    end = text.find("\n---", 3)
    if end == -1:
        return "", text
    return text[3:end], text[end + 4:]


def parse_frontmatter(fm):
    out = {}
    for line in fm.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line or line.startswith((" ", "\t")):
            continue
        key, _, val = line.partition(":")
        out[key.strip()] = val.strip()
    return out


def parse_flow_list(val):
    """`[a, b, c]` -> ['a','b','c']; anything else -> []."""
    val = (val or "").strip()
    if not (val.startswith("[") and val.endswith("]")):
        return []
    inner = val[1:-1].strip()
    return [p.strip() for p in inner.split(",") if p.strip()] if inner else []


def parse_plan(path):
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    fm_text, body = split_frontmatter(text)
    fm = parse_frontmatter(fm_text)
    if not fm.get("slug"):
        die("%s has no `slug:` — not an article plan" % path)

    # Element -> declared Evidence pointers, parsed from the `# Editorial
    # decisions` prose. An element block runs from its `- el-...` line to the
    # next one; pointers are collected from the whole block, which is why a
    # plan that names Evidence on a continuation line still resolves.
    elements, current, buf = {}, None, []

    def flush():
        if current is not None:
            elements[current] = sorted(set(POINTER.findall("\n".join(buf))))

    for line in body.splitlines():
        head = ELEMENT_HEAD.match(line)
        if head:
            flush()
            current, buf = head.group("id"), [line]
        elif current is not None:
            if line.startswith("# "):        # a new plan section ends the list
                flush()
                current, buf = None, []
            else:
                buf.append(line)
    flush()

    return {
        "slug": fm["slug"],
        "run_id": fm.get("run_id"),
        "pin": fm.get("pin"),
        "consumed": parse_flow_list(fm.get("consumed")),
        "elements": elements,
    }


def draft_sections(path):
    """line number (1-based) -> the section heading governing it.

    The paragraph->section join the plan's `sections:` key does not provide at
    paragraph granularity: derived from the draft's own heading structure at
    render time, storing nothing.
    """
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    sections, current = {}, "(lede — before the first heading)"
    in_fm = False
    for i, line in enumerate(lines, start=1):
        if i == 1 and line.strip() == "---":
            in_fm = True
            continue
        if in_fm:
            if line.strip() == "---":
                in_fm = False
            continue
        if line.startswith("#"):
            current = line.lstrip("#").strip()
        sections[i] = current
    return sections


def parse_provenance_map(path):
    """-> ([sentence, ...], [unparsed_line, ...])."""
    sentences, unparsed = [], []
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            m = MAP_LINE.match(line.strip())
            if not m:
                unparsed.append(line)
                continue
            ptrs = POINTER.findall(m.group("ptrs") or "")
            sentences.append({
                "para": int(m.group("para")),
                "sent": int(m.group("sent")),
                "line": int(m.group("line")) if m.group("line") else None,
                "kind": m.group("kind"),
                "pointers": ptrs,
            })
    return sentences, unparsed


def pick_map(workspace):
    """Prefer the v2 map — it carries the `[L]` anchors the section join needs."""
    for name in ("provenance-map-v2.txt", "provenance-map.txt"):
        p = os.path.join(workspace, name)
        if os.path.exists(p):
            return p
    return None


def resolve_workspace(host_root, run_id):
    try:
        out = subprocess.run(
            [sys.executable, RESOLVE_PATHS, "run-workspace",
             "--run-id", run_id, "--root", host_root],
            capture_output=True, text=True, check=True)
    except subprocess.CalledProcessError as exc:
        die("resolve-paths run-workspace failed for run %s: %s"
            % (run_id, (exc.stderr or "").strip()))
    return out.stdout.strip()


def build(plan, sections, sentences, gloss):
    """Group sentences into paragraphs and attach the three legs."""
    paragraphs, order = {}, []
    for s in sentences:
        if s["para"] not in paragraphs:
            paragraphs[s["para"]] = {"id": s["para"], "sentences": [],
                                     "pointers": [], "line": s["line"]}
            order.append(s["para"])
        p = paragraphs[s["para"]]
        p["sentences"].append(s)
        for ptr in s["pointers"]:
            if ptr not in p["pointers"]:
                p["pointers"].append(ptr)
        if p["line"] is None:
            p["line"] = s["line"]

    # pointer -> elements that declare it
    ptr_to_elements = {}
    for eid, ptrs in plan["elements"].items():
        for ptr in ptrs:
            ptr_to_elements.setdefault(ptr, set()).add(eid)

    for pid in order:
        p = paragraphs[pid]
        p["section"] = sections.get(p["line"], "(unknown — map carries no line anchor)") \
            if p["line"] is not None else "(unknown — map carries no line anchor)"
        matched = set()
        for ptr in p["pointers"]:
            matched |= ptr_to_elements.get(ptr, set())
        p["elements"] = sorted(matched)
        # Leg (b): only entries actually supplied are computable.
        p["gloss"] = sorted(
            {slug for slug, ptrs in gloss.items()
             if set(ptrs) & set(p["pointers"])}) if gloss else None
    return [paragraphs[i] for i in order]


def classify(plan, paragraphs):
    """Every `consumed:` id -> paragraph-attributable / article-level-only /
    not-attributable, with the reason the verdict was reached."""
    attributed = set()
    for p in paragraphs:
        attributed |= set(p["elements"])
    out = []
    for eid in plan["consumed"]:
        declared = plan["elements"].get(eid)
        if eid in attributed:
            verdict, why = "paragraph-attributable", \
                "at least one paragraph carries one of its declared pointers"
        elif declared:
            verdict, why = "article-level-only", \
                "declared %d evidence pointer(s), none of which any paragraph carries" % len(declared)
        elif declared is None:
            verdict, why = "not-attributable", \
                "named in `consumed:` but absent from the plan's editorial-decisions body"
        else:
            verdict, why = "not-attributable", \
                "present in the plan body but declaring no evidence pointer"
        out.append({"id": eid, "verdict": verdict, "why": why,
                    "declared": len(declared or [])})
    return out


def render(plan, paragraphs, verdicts, meta):
    L = []
    a = L.append
    a("# Per-paragraph join: %s" % plan["slug"])
    a("")
    a("Generated by `scripts/inspect-article-join.py` (Story 18.118, #725). "
      "Read-only: nothing was written to the articles repo or the hub.")
    a("")
    a("| input | source |")
    a("|---|---|")
    a("| plan | `%s` |" % meta["plan"])
    a("| draft | `%s` |" % meta["draft"])
    a("| provenance map | `%s` |" % meta["map"])
    a("| run id | `%s` |" % (plan["run_id"] or "—"))
    a("| host pin | `%s` |" % (plan["pin"] or "—"))
    a("")

    a("## Leg (b) coverage — read this before the table")
    a("")
    if meta["gloss_supplied"]:
        a("Hub Gloss entries were supplied via `--gloss-entries` (%d entries). "
          "Leg (b) is computable for exactly those entries; any lesson not among "
          "them remains **cannot-determine**." % meta["gloss_count"])
    else:
        a("**cannot-determine.** The served lessons index carries one line per "
          "lesson in the declared format "
          "`- [one_liner](lessons/<slug>.md) — <status> | tags: <t1, t2> | YYYY-MM-DD` "
          "(`LESSONS.md:9`), which holds **no Evidence pointers**; those live in "
          "the lesson body, which the seam does not serve. So leg (b) is reported "
          "as cannot-determine throughout — never as \"none\". An absence was not "
          "established, and rendering one here would assert what was never read.")
    a("")

    if meta["unparsed"]:
        a("⚠ %d provenance-map line(s) did not parse and are excluded:"
          % len(meta["unparsed"]))
        for line in meta["unparsed"][:5]:
            a("  - `%s`" % line)
        a("")
    if meta["no_anchor"]:
        a("⚠ %d paragraph(s) carry no `[L<line>]` anchor, so their section is "
          "unknown rather than guessed." % meta["no_anchor"])
        a("")

    a("## Paragraphs")
    a("")
    a("| ¶ | section | evidence pointers (a) | Gloss entries (b) | elements (c) |")
    a("|---|---|---|---|---|")
    for p in paragraphs:
        ptrs = "<br>".join("`%s`" % x for x in p["pointers"]) or "_none_"
        if p["gloss"] is None:
            gloss = "_cannot-determine_"
        else:
            gloss = ", ".join("`%s`" % g for g in p["gloss"]) or "_none_"
        els = ", ".join("`%s`" % e for e in p["elements"]) or "_none_"
        a("| P%d | %s | %s | %s | %s |" % (p["id"], p["section"], ptrs, gloss, els))
    a("")

    a("## Consumption claims")
    a("")
    a("| element | verdict | why |")
    a("|---|---|---|")
    for v in verdicts:
        a("| `%s` | **%s** | %s |" % (v["id"], v["verdict"], v["why"]))
    a("")

    counts = {}
    for v in verdicts:
        counts[v["verdict"]] = counts.get(v["verdict"], 0) + 1
    grounded = sum(1 for p in paragraphs if p["pointers"])
    a("## Totals")
    a("")
    a("- paragraphs: **%d** (%d carry at least one evidence pointer, %d carry none)"
      % (len(paragraphs), grounded, len(paragraphs) - grounded))
    a("- paragraphs whose evidence maps to no element: **%d**"
      % sum(1 for p in paragraphs if p["pointers"] and not p["elements"]))
    a("- consumption claims: " + (", ".join(
        "%s **%d**" % (k, counts[k]) for k in sorted(counts)) or "_none declared_"))
    a("")
    return "\n".join(L)


def main():
    ap = argparse.ArgumentParser(
        description="Per-paragraph Evidence / Gloss / consumption inspection "
                    "view for one canonical draft (read-only).")
    ap.add_argument("--slug", required=True)
    ap.add_argument("--articles-repo", required=True,
                    help="the articles repository holding plans/ and drafts/")
    ap.add_argument("--host-root", required=True,
                    help="the host repo the article was drafted from "
                         "(resolves the run workspace holding the provenance map)")
    ap.add_argument("--gloss-entries",
                    help='JSON {"<lesson-slug>": ["<pointer>", ...]} — supply only '
                         "pointers obtained by a sanctioned route; anything absent "
                         "stays cannot-determine")
    ap.add_argument("--out", help="write the report here instead of stdout")
    args = ap.parse_args()

    plan_path = os.path.join(args.articles_repo, "plans", args.slug + ".md")
    draft_path = os.path.join(args.articles_repo, "drafts", args.slug + ".md")
    for p in (plan_path, draft_path):
        if not os.path.exists(p):
            die("missing %s" % p)

    plan = parse_plan(plan_path)
    if not plan["run_id"]:
        die("plan %s has no `run_id:` — the provenance map cannot be located. "
            "This is itself a finding: the claim-level join depends on run state "
            "the plan only points at." % plan_path)

    workspace = resolve_workspace(args.host_root, plan["run_id"])
    map_path = pick_map(workspace)
    if not map_path:
        die("no provenance map in %s — the run workspace was pruned, so the "
            "claim-level join is unavailable for this article. Report this as a "
            "durability finding rather than an empty result." % workspace)

    gloss = {}
    if args.gloss_entries:
        with open(args.gloss_entries, encoding="utf-8") as fh:
            gloss = json.load(fh)

    sections = draft_sections(draft_path)
    sentences, unparsed = parse_provenance_map(map_path)
    if not sentences:
        die("provenance map %s parsed to zero sentences" % map_path)

    paragraphs = build(plan, sections, sentences, gloss)
    verdicts = classify(plan, paragraphs)
    report = render(plan, paragraphs, verdicts, {
        "plan": plan_path, "draft": draft_path, "map": map_path,
        "unparsed": unparsed,
        "no_anchor": sum(1 for p in paragraphs if p["line"] is None),
        "gloss_supplied": bool(gloss), "gloss_count": len(gloss),
    })

    if args.out:
        with open(args.out, "w", encoding="utf-8") as fh:
            fh.write(report + "\n")
        sys.stderr.write("wrote %s\n" % args.out)
    else:
        sys.stdout.write(report + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
