#!/usr/bin/env python3
"""Canonical adaptation — the standalone, owner-gated derivation of a
target-language canonical from a reviewed source canonical (Story 18.56,
SPEC-canonical-adaptation CAP-1 + CAP-3).

This script is the MECHANICAL CORE of an invocation in the same family as
`emit variants`: it is never a stage of the draft flow and is never fired
implicitly by emission. It resolves and validates the source canonical,
resolves the adaptation target, composes the ADAPTATION PLAN, and emits that
plan in the owner-facing proposal-payload shape. It writes NOTHING: persisting
the derived canonical is Story 18.57's job, and nothing at all may be written
before the owner's answer is recorded (CAP-3).

WHERE THE TARGET IS DECLARED (spec OQ1, settled here as PROFILE POINTER)
------------------------------------------------------------------------
`--target <platform-id>` points at an existing platform profile. The profile
already declares the one named reader (`audience`) and that reader's
`language` — the same declaration the variant stage's retarget trigger reads —
so naming a target introduces NO new declaration type, and a second adaptation
target is one profile file (CAP-6). What the profile deliberately does not
carry is HOW prose is told in that language: register and terminology are
properties of the LANGUAGE, not of one platform's packaging, and a profile is
packaging-scoped by the ratified intent/packaging boundary (2026-07-16). Those
live as data in `config/language-conventions.yaml` (overridable per repo at
`<repo-config-dir>/language-conventions.yaml`). Consequently NO language
appears in a branch in this file: `ja` is a key in profile + convention data,
never a case in code.

PRECONDITIONS (CAP-1) — the same ones the variant stage applies, evaluated
with the variant stage's OWN predicates (loaded from draft-pipeline.py: the
`[VERIFY]` marker regexes, the frontmatter reader, the emission-trailer
normalizer and the output.drafts resolver), so there is no second, drifting
copy of the marker or path logic:

  - the source is the PERSISTED canonical at `<output.drafts>/<slug>.md`; a
    run-workspace copy is refused, naming `complete` as the remedy;
  - the draft carries zero well-formed `[VERIFY]` markers;
  - the draft declares a resolved `audience`, `audience_id` and `language`.

THE PLAN (CAP-3). The plan is DATA this script emits; the prose is authored by
the invoking skill. `plan` with no `--fill` returns the SKELETON: the resolved
source and target facts, the register and terminology conventions read from
declaration data, and the source's section inventory — the slots the skill must
fill (re-founded opening, per-section structural mapping, re-composed title,
declared omissions). `plan --fill <json>` merges the authored prose and
validates it: every source section accounted for exactly once, a dropped
section declared as an omission with a reason, and register/terminology NOT
proposable (they are declared, not decided per article). `payload` emits the
same plan in the proposal-payload shape for
`validate-proposal-payload.py --surface adaptation-plan`, with the three
options the gate offers: approve / modify / stop.

THE DERIVED CANONICAL (CAP-4, Story 18.57). `write` persists the adaptation's
output as an ORDINARY canonical — `<output.drafts>/<slug>.<language>.md`, its
own `slug` (`<slug>.<language>`), `mode: canonical`, the target language and
reader, and its own `canonical-sha256` trailer — through the pipeline's ONE
canonical write path (`draft-pipeline.py _persist_canonical`), so no second
hasher and no second writer exists. The only thing that marks it as derived is
declaration, not behaviour: an ancestry pin

    adapted_from: <source slug>@<source hash>

whose hash is the SAME convention the emission trailer uses (sha256 over the
content without the trailer). Downstream stages consume it with zero
special-casing: `emit variants --slug <slug>.<language>` resolves it like any
canonical because it IS one.

Two checks guard the ancestry and the claims invariant:
  - `lint-ancestry` NAMES a malformed block, an unresolvable source slug and a
    hash that matches no source content — never swallows one;
  - `claims-check` compares the source and derived canonicals' PROVENANCE-MAP
    POINTER SETS (CAP-2). Pointer identity is language-independent, so this
    reports an added claim and a silently dropped one while saying nothing at
    all about structure, section order, payoff position, framing, register or
    title — all of which CAP-2 leaves free. There was no existing claim-set
    comparison to reuse: `verify-provenance.py` grades ONE map against ONE fact
    sheet, and the map's positions are per-artifact, so cross-artifact
    comparison is new here (deliberately built on the shipped map parser rather
    than a second map format).

Stdlib-only (host repos guarantee no venv). Exit codes: 0 ok, 1 refusal
(precondition unmet / plan defect / check finding), 2 usage.

Subcommands:
  plan          --slug S --target P [--draft PATH] [--root R] [--fill F]
  payload       --slug S --target P [--draft PATH] [--root R] --fill F
  write         --slug S --target P --fill F --body B --ws W [--root R]
  lint-ancestry --derived PATH [--root R]
  staleness     [--derived PATH] [--root R]
  claims-check  --source-map M --derived-map M [--fill F]
"""

import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys

REFUSED = 1
USAGE = 2

# The disposition vocabulary of the structural mapping. Closed on purpose: a
# free-text disposition cannot be checked, and "which sections move, merge or
# reorder" is exactly what the owner ratifies at the gate.
DISPOSITIONS = ("keep", "move", "merge", "split", "drop")

# Slots the invoking skill authors. Register and terminology are absent by
# design — they are declared data, not per-article proposals.
FILL_SLOTS = ("refounded_opening", "structural_mapping", "recomposed_title", "omissions")
DECLARED_ONLY = ("register", "terminology")

SECTION_RE = re.compile(r"^(#{2,6})\s+(.*\S)\s*$", re.MULTILINE)

CONVENTIONS_FILE = "language-conventions.yaml"


def _load(mod_filename):
    """Load a sibling script as a module (the resolve-*.py idiom)."""
    here = os.path.dirname(os.path.realpath(__file__))
    name = mod_filename.replace(".py", "").replace("-", "_")
    spec = importlib.util.spec_from_file_location(name, os.path.join(here, mod_filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


dp = _load("draft-pipeline.py")            # the variant stage's own predicates
pp = _load("resolve-platform-profiles.py")  # target declaration (profiles)
rp = _load("resolve-paths.py")              # THE path resolver — never composed here
uc = _load("resolve-user-config.py")        # shared stdlib YAML subset reader


def _err(msg):
    sys.stderr.write(f"error: {msg}\n")
    return REFUSED


# --------------------------------------------------------------------------
# Source canonical (CAP-1)


def resolve_source(args):
    """Return (path, text, fields) for the PERSISTED, REVIEWED source canonical,
    or raise Refusal. The refusal cases and their remedies mirror the variant
    stage (`draft-pipeline.py cmd_variants`) exactly — same predicates, same
    `complete` remedy — because the preconditions ARE the variant stage's."""
    drafts_dir = os.path.realpath(dp._resolve_drafts_dir(args.root))
    canonical_path = os.path.join(drafts_dir, f"{args.slug}.md")

    if getattr(args, "draft", None):
        src = os.path.realpath(args.draft)
        if src != canonical_path:
            raise Refusal(
                f"draft {args.draft!r} is not the persisted canonical — adaptation "
                f"consumes {canonical_path} (SPEC-canonical-adaptation CAP-1), never "
                "a workspace copy. Run the draft flow's completion first "
                f"(`draft-pipeline.py complete --draft <ws-draft> --slug {args.slug}`), "
                f"then re-run `adapt-canonical.py plan --slug {args.slug}`.")
    if not os.path.isfile(canonical_path):
        raise Refusal(
            f"no persisted canonical at {canonical_path} — adaptation consumes the "
            "persisted canonical draft (SPEC-canonical-adaptation CAP-1), never a "
            "workspace copy. Finish the draft flow first: `draft-pipeline.py complete "
            f"--draft <ws-draft> --slug {args.slug}` persists "
            f"<output.drafts>/{args.slug}.md, then re-run `adapt-canonical.py plan "
            f"--slug {args.slug}`.")

    text = open(canonical_path, encoding="utf-8").read()
    # Normalize exactly the way the variant stage does before it reads or hashes
    # a persisted canonical, so both see the same content (one convention).
    text = dp._strip_emission_trailer(text)

    unresolved = [c for c in dp.VERIFY_CANDIDATE.findall(text)
                  if dp.VERIFY_CANONICAL.match(c)]
    if unresolved:
        raise Refusal(
            f"draft still has {len(unresolved)} unresolved [VERIFY] marker(s); "
            "complete Stage 4 (and review) before adapting — adaptation derives from "
            "a REVIEWED canonical, and an unverified claim must not be carried into a "
            "second language")

    fields, _body = dp._read_frontmatter(text)
    for key in ("language", "audience", "audience_id"):
        val = fields.get(key)
        if not val or val == "{%s}" % key:
            raise Refusal(
                f"draft frontmatter has no resolved `{key}`; adaptation compares the "
                "source's named reader against the target's, so it must be declared at "
                "draft time — it is never inferred here")
    return canonical_path, text, fields


class Refusal(Exception):
    pass


# --------------------------------------------------------------------------
# Target declaration (OQ1: profile pointer) + language conventions


def resolve_target(args):
    """Resolve the adaptation target from the platform profile it points at.
    Returns {platform, audience, language}. No language is special-cased."""
    root = pp.host_root(args.root)
    pdir = pp.profiles_dir(root, args.profiles_dir)
    profiles, findings = pp.load_profiles(pdir)
    if args.target not in profiles:
        raise Refusal(
            f"no platform profile {args.target!r} in {pdir} — the adaptation target is "
            "named by pointing at a platform profile (it declares the target reader and "
            "language). Seed or author that profile "
            f"(`resolve-platform-profiles.py seed {args.target}`) and re-run."
            + (f" Unusable profiles: {findings}" if findings else ""))
    prof = profiles[args.target]
    return {"platform": args.target,
            "audience": prof.get("audience"),
            "language": prof.get("language")}


def conventions_path(root, override):
    """The language-conventions declaration: an explicit override, else a
    per-repo file beneath the RESOLVED repo-config directory, else the shipped
    default in this plugin's config/. No caller composes a config-home layout."""
    if override:
        return os.path.realpath(override)
    repo_local = os.path.join(rp.repo_config_dir(root), CONVENTIONS_FILE)
    if os.path.isfile(repo_local):
        return repo_local
    here = os.path.dirname(os.path.realpath(__file__))
    return os.path.realpath(os.path.join(here, "..", "config", CONVENTIONS_FILE))


def resolve_conventions(args, language):
    """Register + terminology treatment for a LANGUAGE, read from declaration
    data (CAP-6: not a branch in this file)."""
    path = conventions_path(pp.host_root(args.root), args.conventions)
    if not os.path.isfile(path):
        raise Refusal(f"no language-conventions declaration at {path}")
    try:
        data = uc.load_yaml(open(path, encoding="utf-8").read())
    except uc.YamlSubsetError as exc:
        raise Refusal(f"language-conventions declaration {path} is unreadable: {exc}")
    langs = (data or {}).get("languages") or {}
    entry = langs.get(language)
    if not isinstance(entry, dict) or not all(entry.get(k) for k in DECLARED_ONLY):
        raise Refusal(
            f"language {language!r} declares no register/terminology conventions in "
            f"{path} — adaptation reads them as data, never from a language branch in "
            "stage code (SPEC-canonical-adaptation CAP-6). Add a `languages."
            f"{language}` entry with `register` and `terminology`.")
    return {k: entry[k] for k in DECLARED_ONLY}


# --------------------------------------------------------------------------
# The adaptation plan (CAP-3)


def sections(text):
    """The source canonical's section inventory (heading text, in order)."""
    _fields, body = dp._read_frontmatter(text)
    return [m.group(2) for m in SECTION_RE.finditer(body)]


def skeleton(source_path, fields, target, conv, secs):
    return {
        "stage": "adapt",
        "source": {"path": source_path, "slug": fields.get("slug"),
                   "title": fields.get("title"), "language": fields.get("language"),
                   "audience": fields.get("audience"),
                   "audience_id": fields.get("audience_id"),
                   "sections": secs},
        "target": target,
        # Declared, not proposed: the invariants of CAP-3.
        "register": conv["register"],
        "terminology": conv["terminology"],
        "filled": False,
        "slots": list(FILL_SLOTS),
        "written": False,
        "note": "nothing is written before the owner answers the gate; persisting the "
                "derived canonical is a separate story (18.57)",
    }


def merge_fill(plan, fill):
    """Merge the skill-authored prose into the skeleton and validate it.
    Raises Refusal on any plan defect — a defective plan never reaches a
    payload, so it never reaches the owner."""
    if not isinstance(fill, dict):
        raise Refusal("--fill must be a JSON object with the plan's authored slots")
    for key in DECLARED_ONLY:
        if key in fill:
            raise Refusal(
                f"{key!r} is declared data, not a per-article proposal — it comes from "
                "the language-conventions declaration; remove it from --fill")
    missing = [s for s in FILL_SLOTS if s not in fill]
    if missing:
        raise Refusal(f"--fill is missing plan slot(s): {', '.join(missing)}")

    opening = str(fill.get("refounded_opening") or "").strip()
    title = str(fill.get("recomposed_title") or "").strip()
    if not opening:
        raise Refusal("refounded_opening is empty — the plan must state what context "
                      "the target reader lacks or already has")
    if not title:
        raise Refusal("recomposed_title is empty — the plan must state the re-composed "
                      "title for the target reader")

    mapping = fill.get("structural_mapping")
    if not isinstance(mapping, list) or not mapping:
        raise Refusal("structural_mapping must be a non-empty list of "
                      "{source_section, disposition, note}")
    seen, rows = [], []
    for i, row in enumerate(mapping):
        if not isinstance(row, dict):
            raise Refusal(f"structural_mapping[{i}] is not an object")
        sec = str(row.get("source_section") or "").strip()
        disp = str(row.get("disposition") or "").strip()
        note = str(row.get("note") or "").strip()
        if disp not in DISPOSITIONS:
            raise Refusal(f"structural_mapping[{i}] disposition {disp!r} is not one of "
                          f"{', '.join(DISPOSITIONS)}")
        if not note:
            raise Refusal(f"structural_mapping[{i}] has no note — say why the section "
                          "moves, merges or stays for this reader")
        if sec in seen:
            raise Refusal(f"structural_mapping names section {sec!r} twice")
        seen.append(sec)
        rows.append({"source_section": sec, "disposition": disp, "note": note})

    unmapped = [s for s in plan["source"]["sections"] if s not in seen]
    extra = [s for s in seen if s not in plan["source"]["sections"]]
    if unmapped:
        raise Refusal("structural_mapping does not account for source section(s): "
                      + "; ".join(unmapped))
    if extra:
        raise Refusal("structural_mapping names section(s) absent from the source "
                      "canonical: " + "; ".join(extra))

    omissions = fill.get("omissions")
    if not isinstance(omissions, list):
        raise Refusal("omissions must be a list (empty when nothing is dropped)")
    oms = []
    for i, om in enumerate(omissions):
        if not isinstance(om, dict) or not str(om.get("what") or "").strip() \
                or not str(om.get("reason") or "").strip():
            raise Refusal(f"omissions[{i}] must declare `what` and `reason` — a "
                          "deliberate omission is declared, never implicit")
        # `pointers` is how an omission becomes CHECKABLE (CAP-2): the
        # claims-conformance pass reads the dropped claims' fact-sheet pointers
        # from here, so a load-bearing claim left out on purpose is declared in
        # the same place a dropped section already is.
        ptrs = om.get("pointers") or []
        if not isinstance(ptrs, list) or any(not str(p).strip() for p in ptrs):
            raise Refusal(f"omissions[{i}] `pointers` must be a list of non-empty "
                          "fact-sheet pointers (omit it when the omission drops no "
                          "sourced claim)")
        oms.append({"section": str(om.get("section") or "").strip(),
                    "what": str(om["what"]).strip(),
                    "reason": str(om["reason"]).strip(),
                    "pointers": [str(p).strip() for p in ptrs]})
    dropped = [r["source_section"] for r in rows if r["disposition"] == "drop"]
    declared = {o["section"] for o in oms}
    undeclared = [s for s in dropped if s not in declared]
    if undeclared:
        raise Refusal("dropped section(s) with no declared omission: "
                      + "; ".join(undeclared)
                      + " — declare each in `omissions` with its section and reason")

    plan = dict(plan)
    plan.update({"filled": True, "refounded_opening": opening,
                 "structural_mapping": rows, "recomposed_title": title,
                 "omissions": oms})
    plan.pop("slots", None)
    return plan


# --------------------------------------------------------------------------
# The gate payload (CAP-3): one screen, approve / modify / stop


def compose_payload(plan):
    """One proposal item carrying the whole plan, in the shape
    `validate-proposal-payload.py` accepts: plain text only, Where + Why, and
    choices whose Effect names the concrete effect on the artifact."""
    if not plan.get("filled"):
        raise Refusal("the plan carries no authored prose yet — fill "
                      f"{', '.join(FILL_SLOTS)} (adapt-canonical.py plan ... --fill) "
                      "before composing the gate payload")
    src, tgt = plan["source"], plan["target"]
    derived = f"{src['slug']}.{tgt['language']}.md"
    item = {
        "where": (f"Adaptation of canonical {src['slug']} for target {tgt['platform']}: "
                  f"reader {tgt['audience']}, language {tgt['language']}. "
                  f"Source sections mapped: {len(plan['structural_mapping'])}."),
        "why": ("Adaptation re-decides how this article is told for the target reader; "
                "the claims stay fixed. Whether this article gets a derived canonical "
                "at all is your decision here."),
        "plan": {
            "refounded opening": plan["refounded_opening"],
            "structural mapping": [
                f"{r['source_section']} -> {r['disposition']}: {r['note']}"
                for r in plan["structural_mapping"]],
            "register": plan["register"],
            "terminology": plan["terminology"],
            "recomposed title": plan["recomposed_title"],
            "declared omissions": [
                f"{o['section'] or '(no section)'}: {o['what']} — {o['reason']}"
                for o in plan["omissions"]] or ["none — every source claim is carried"],
        },
        "choices": [
            {"label": "approve",
             "effect": f"writes the derived canonical {derived} from this plan; the "
                       "source canonical is untouched"},
            {"label": "modify",
             "effect": f"revises the plan from your answer, then writes {derived} from "
                       "the revised plan"},
            {"label": "stop",
             "effect": "writes nothing; this article stays single-canonical and no "
                       "derived canonical exists anywhere"},
        ],
    }
    return {"items": [item]}


# --------------------------------------------------------------------------
# The derived canonical (CAP-4)

# The ancestry pin, spelled as ONE scalar `<slug>@<sha>` — reusing the
# articles-repo plans' existing `pin: <repo>@<sha>` idiom rather than inventing a
# second ancestry convention (ratified 2026-07-23). It is an ordinary scalar
# frontmatter value, so the pipeline's frontmatter reader returns it as the raw
# string this parser then splits, and no second frontmatter grammar appears.
ANCESTRY_KEY = "adapted_from"
_ANCESTRY_PIN = re.compile(r"^(?P<slug>[^\s@]+)@(?P<sha>[0-9a-f]{64})$")

# Frontmatter keys the derivation OWNS: the derived canonical is a canonical in
# its own right, so these are re-declared for the target reader rather than
# inherited from the source.
DERIVED_KEYS = ("slug", "title", "language", "audience", "audience_id")


def derived_slug(source_slug, language):
    return f"{source_slug}.{language}"


def canonical_hash(text):
    """The ONE hash convention: sha256 over the content WITHOUT the emission
    trailer — the variant trailer's own convention, reached through the
    pipeline's normalizer so there is never a second hasher."""
    return hashlib.sha256(dp._strip_emission_trailer(text).encode("utf-8")).hexdigest()


def parse_ancestry(fields):
    """Read the ancestry pin out of already-parsed frontmatter. Returns
    (ancestry_or_None, defect_or_None) — an absent pin is neither (the file
    is simply not a derivation); a malformed one is a NAMED defect. The pin is
    the scalar `<slug>@<sha>` (ratified 2026-07-23); the internal shape stays
    `{slug, canonical_sha256}` so downstream (staleness, lint) is untouched."""
    raw = fields.get(ANCESTRY_KEY)
    if raw is None:
        return None, None
    if not isinstance(raw, str):
        return None, f"`{ANCESTRY_KEY}` is not a scalar pin: {raw!r}"
    m = _ANCESTRY_PIN.match(raw.strip().strip('"\''))
    if not m:
        return None, (f"`{ANCESTRY_KEY}` must be the scalar pin `<slug>@<sha>` "
                      f"(a slug, `@`, and a 64-char sha256 digest); got {raw!r}")
    return {"slug": m.group("slug"), "canonical_sha256": m.group("sha")}, None


def compose_derived(source_text, source_fields, plan, target, ancestry, body):
    """Build the derived canonical's text: the source's frontmatter with the
    derivation-owned keys re-declared for the target reader plus the ancestry
    pin, over the skill-authored target-language body. Every other declared
    field (date, topics, related, ...) is carried verbatim — the derived file
    conforms to the same frontmatter schema because it is the same kind of
    file."""
    lines = source_text.splitlines()
    end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    overrides = {
        "slug": derived_slug(source_fields.get("slug"), target["language"]),
        "title": plan["recomposed_title"],
        "language": target["language"],
        "audience": target["audience"],
        "audience_id": target["audience"],
        "mode": "canonical",
    }
    out, written = [], set()
    for line in lines[1:end]:
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        key = m.group(1) if m else None
        if key == ANCESTRY_KEY:
            continue                      # never inherit a grandparent's ancestry
        if key in overrides:
            out.append(f'{key}: "{overrides[key]}"' if key in ("title",)
                       else f"{key}: {overrides[key]}")
            written.add(key)
            continue
        out.append(line)
    for key, val in overrides.items():
        if key not in written:
            out.append(f'{key}: "{val}"' if key in ("title",) else f"{key}: {val}")
    out.append(f'{ANCESTRY_KEY}: {ancestry["slug"]}@{ancestry["canonical_sha256"]}')
    return "---\n" + "\n".join(out) + "\n---\n\n" + body.strip("\n") + "\n"


def recorded_answer(ws):
    """The owner's recorded answer to the adaptation gate (CAP-3). Returns the
    selection string, or raises Refusal — `write` is the step AFTER the gate, so
    an unanswered gate means nothing may be written."""
    path = os.path.join(ws, "presented-payloads.jsonl")
    records = []
    try:
        for line in open(path, encoding="utf-8"):
            if line.strip():
                records.append(json.loads(line))
    except OSError:
        raise Refusal(
            f"no presented-payload log at {path} — the derived canonical is written "
            "only after the owner answers the adaptation gate (CAP-3). Present the "
            "payload (`adapt-canonical.py payload ... | validate-proposal-payload.py "
            "--ws <ws> --surface adaptation-plan`) and record the answer first.")
    except json.JSONDecodeError as exc:
        raise Refusal(f"presented-payload log {path} is unreadable: {exc}")
    answers = [r for r in records if r.get("kind") == "answer"]
    if not answers:
        raise Refusal(
            "the adaptation gate has no recorded answer — nothing is written before "
            "the owner answers (CAP-3). Record it with `validate-proposal-payload.py "
            "--ws <ws> --answer <ask_id>`.")
    selection = str((answers[-1].get("answer") or {}).get("selection") or "").strip()
    if selection == "stop":
        raise Refusal(
            "the owner chose `stop` at the adaptation gate: nothing is written and "
            "this article stays single-canonical. Re-invoke the adaptation only if "
            "they ask for it.")
    if selection not in ("approve", "modify"):
        raise Refusal(
            f"the recorded answer's selection is {selection!r}; the adaptation gate's "
            "options are approve / modify / stop, and only approve or modify write a "
            "derived canonical")
    return selection


def cmd_write(args):
    """Persist the derived canonical (CAP-4) — after the recorded answer, never
    before it. The write itself goes through the pipeline's ONE canonical write
    path, so the derived file carries its own emission trailer under the same
    hash convention as every other canonical."""
    selection = recorded_answer(args.ws)
    source_path, text, fields = resolve_source(args)
    plan = _build(args)
    target = plan["target"]
    body = sys.stdin.read() if args.body == "-" else open(args.body, encoding="utf-8").read()
    if not body.strip():
        raise Refusal("--body is empty — the derived canonical's target-language prose "
                      "is authored by the invoking skill from the approved plan")
    ancestry = {"slug": fields.get("slug"), "canonical_sha256": canonical_hash(text)}
    derived_text = compose_derived(text, fields, plan, target, ancestry, body)
    dslug = derived_slug(fields.get("slug"), target["language"])
    try:
        path, sha = dp._persist_canonical(derived_text, dslug, args.root,
                                          create_out=args.create_out)
    except dp._CanonicalWriteError as exc:
        raise Refusal(f"could not persist the derived canonical at {exc.path}: "
                      f"{exc.reason}")
    print(json.dumps({"stage": "adapt-write", "selection": selection,
                      "source": {"path": source_path, "slug": fields.get("slug"),
                                 "canonical_sha256": ancestry["canonical_sha256"]},
                      "derived": {"path": path, "slug": dslug,
                                  "language": target["language"],
                                  "audience": target["audience"],
                                  "canonical_sha256": sha},
                      ANCESTRY_KEY: ancestry,
                      "next": f"emit variants --slug {dslug}"},
                     indent=2, ensure_ascii=False))
    return 0


def ancestry_defects(derived_path, root):
    """Every way an ancestry block can be wrong, NAMED (CAP-4 success). Returns
    (list_of_defects, ancestry_or_None)."""
    defects = []
    try:
        text = open(derived_path, encoding="utf-8").read()
    except OSError as exc:
        return ([{"defect": "unreadable-derived-canonical", "path": derived_path,
                  "detail": str(exc)}], None)
    fields, _body = dp._read_frontmatter(text)
    ancestry, malformed = parse_ancestry(fields)
    if malformed:
        defects.append({"defect": "malformed-ancestry", "path": derived_path,
                        "detail": malformed})
        return defects, None
    if ancestry is None:
        defects.append({
            "defect": "missing-ancestry", "path": derived_path,
            "detail": (f"no `{ANCESTRY_KEY}` block; a derived canonical records the "
                       "source it was adapted from (CAP-4)")})
        return defects, None

    drafts_dir = os.path.realpath(dp._resolve_drafts_dir(root))
    source_path = os.path.join(drafts_dir, f"{ancestry['slug']}.md")
    if not os.path.isfile(source_path):
        defects.append({
            "defect": "ancestry-source-missing", "path": derived_path,
            "source_slug": ancestry["slug"],
            "detail": (f"`{ANCESTRY_KEY}.slug` resolves to no canonical at "
                       f"{source_path}")})
        return defects, ancestry
    current = canonical_hash(open(source_path, encoding="utf-8").read())
    if current != ancestry["canonical_sha256"]:
        defects.append({
            "defect": "ancestry-hash-mismatch", "path": derived_path,
            "source_path": source_path,
            "recorded_sha256": ancestry["canonical_sha256"],
            "current_sha256": current,
            "detail": ("the recorded source hash matches no current source content — "
                       "the source canonical moved since this derivation, or the "
                       "block was hand-edited")})
    return defects, ancestry


def cmd_lint_ancestry(args):
    defects, ancestry = ancestry_defects(os.path.realpath(args.derived), args.root)
    out = {"stage": "lint-ancestry", "derived": os.path.realpath(args.derived),
           ANCESTRY_KEY: ancestry, "defects": defects}
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return REFUSED if defects else 0


# --------------------------------------------------------------------------
# The staleness chain (CAP-5, Story 18.58)
#
# Editing the source canonical makes its derivation stale — and everything
# downstream of the derivation stale WITH it. The chain is
#
#     EN canonical edit -> JA canonical stale -> its Zenn variant stale
#
# The second hop is not a second mechanism: the derived canonical's own variants
# are graded by the SHIPPED `variant-staleness` check against the derivation,
# unchanged. What this adds is the UPSTREAM link — when the derivation itself is
# stale, its variants are stale by inheritance no matter how fresh their own
# recorded hash is, because the content they were emitted from is superseded.


def discover_derivations(root, only=None):
    """Every derived canonical at the resolved output.drafts (an `adapted_from`
    block is what makes a file one), or just the named path."""
    if only:
        return [os.path.realpath(only)]
    drafts_dir = os.path.realpath(dp._resolve_drafts_dir(root))
    if not os.path.isdir(drafts_dir):
        return []
    return [os.path.join(drafts_dir, f) for f in sorted(os.listdir(drafts_dir))
            if f.endswith(".md") and dp._declares_ancestry(os.path.join(drafts_dir, f))]


def chain_report(derived_path, root):
    """One derivation's staleness, plus its variants' — the whole chain from the
    source canonical down. Returns (entry, publish_blockers)."""
    defects, ancestry = ancestry_defects(derived_path, root)
    entry = {"derived": derived_path, ANCESTRY_KEY: ancestry, "variants": []}
    blockers = []

    # A defective ancestry block is named here too: a derivation whose source
    # cannot be resolved cannot be shown fresh, so it is never silently fresh.
    hard = [d for d in defects if d["defect"] != "ancestry-hash-mismatch"]
    if hard:
        entry["status"] = "unverifiable"
        entry["defects"] = hard
        for d in hard:
            blockers.append({"path": derived_path, "blocker": d["defect"],
                             "detail": d["detail"]})
        return entry, blockers

    mismatch = next((d for d in defects if d["defect"] == "ancestry-hash-mismatch"), None)
    entry["recorded_source_sha256"] = ancestry["canonical_sha256"]
    entry["current_source_sha256"] = (mismatch["current_sha256"] if mismatch
                                      else ancestry["canonical_sha256"])
    entry["status"] = "stale" if mismatch else "fresh"
    if mismatch:
        blockers.append({
            "path": derived_path, "blocker": "stale-derivation",
            "source_path": mismatch["source_path"],
            "source_slug": ancestry["slug"],
            "recorded_sha256": ancestry["canonical_sha256"],
            "current_sha256": mismatch["current_sha256"],
            "detail": ("the source canonical changed since this derivation; a Japanese "
                       "article stating the superseded version must not publish. "
                       "Re-adaptation is a FRESH owner decision through "
                       "`adapt canonical <slug> for <target>` — never an implicit "
                       "re-run and never an in-place edit of the derivation")})

    # Second hop: the shipped variant-staleness check, unchanged, against the
    # DERIVATION. Its findings pass through verbatim.
    text = open(derived_path, encoding="utf-8").read()
    inner = dp._staleness_report(text, root=root)
    entry["variants"] = inner["variants"]
    entry["derived_sha256"] = inner["canonical_sha256"]
    blockers.extend(inner.get("publish_blockers", []))

    # The upstream link: a stale derivation makes every variant of it stale by
    # inheritance, including one whose own recorded hash still matches.
    if mismatch:
        already = {b.get("path") for b in inner.get("publish_blockers", [])}
        for v in inner["variants"]:
            if v["path"] in already:
                continue
            blockers.append({
                "path": v["path"], "platform": v["platform"],
                "blocker": "stale-by-inheritance",
                "upstream": derived_path,
                "upstream_blocker": "stale-derivation",
                "source_slug": ancestry["slug"],
                "recorded_sha256": ancestry["canonical_sha256"],
                "current_sha256": mismatch["current_sha256"],
                "detail": ("emitted from a derivation whose source canonical has since "
                           "changed; it is stale even though its own recorded hash "
                           "matches. Re-adapt first, then re-emit")})
    return entry, blockers


def cmd_staleness(args):
    """The chained staleness check (CAP-5). Reports each derivation and its
    variants; anything not fresh lands in the PUBLISH-BLOCKER bucket with the
    hash pair — never a warning, never silent."""
    derivations, blockers = [], []
    for path in discover_derivations(args.root, args.derived):
        entry, found = chain_report(path, args.root)
        derivations.append(entry)
        blockers.extend(found)
    out = {"stage": "adaptation-staleness", "derivations": derivations}
    if blockers:
        out["publish_blockers"] = blockers
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


# --------------------------------------------------------------------------
# Claims conformance (CAP-2)


def pointer_set(map_path):
    """The claim identity set of one artifact: every pointer its provenance map
    carries on a `sourced` or `derived` entry. Positions are deliberately
    dropped — structure, order and framing are FREE under CAP-2, so a check
    that read them would report exactly what the spec permits."""
    try:
        entries = dp.parse_provenance_map(open(map_path, encoding="utf-8").read())
    except OSError as exc:
        raise Refusal(f"provenance map {map_path} is unreadable: {exc}")
    except ValueError as exc:
        raise Refusal(f"provenance map {map_path} is malformed: {exc}")
    return {p for _pos, cls, ptrs, _anchor in entries
            if cls in ("sourced", "derived") for p in ptrs}


def cmd_claims_check(args):
    """Compare the derived canonical's claims against the source's (CAP-2): an
    added claim is a defect; a load-bearing claim dropped without a declared
    omission is a defect. Nothing else is reported."""
    source = pointer_set(args.source_map)
    derived = pointer_set(args.derived_map)
    declared = set()
    if args.fill:
        raw = sys.stdin.read() if args.fill == "-" else open(args.fill, encoding="utf-8").read()
        try:
            fill = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise Refusal(f"--fill is not valid JSON: {exc}")
        for om in (fill.get("omissions") or []):
            for p in (om.get("pointers") or []):
                declared.add(str(p).strip())

    defects = []
    for p in sorted(derived - source):
        defects.append({
            "defect": "added-claim", "pointer": p,
            "detail": ("present in the derivation but absent from the source "
                       "canonical; adaptation re-decides the telling, never the "
                       "claims (CAP-2) — route a new claim to the source canonical "
                       "and re-adapt")})
    for p in sorted(source - derived - declared):
        defects.append({
            "defect": "dropped-claim", "pointer": p,
            "detail": ("carried by the source canonical and absent from the "
                       "derivation with no declared omission; declare it in the "
                       "plan's `omissions` (with its `pointers`) or carry it")})
    for p in sorted(declared - source):
        defects.append({
            "defect": "omission-unknown-pointer", "pointer": p,
            "detail": "declared as omitted but the source canonical never carried it"})

    out = {"stage": "claims-check",
           "source_pointers": len(source), "derived_pointers": len(derived),
           "declared_omissions": sorted(declared),
           "free": ["structure", "section order", "payoff position", "framing",
                    "register", "title"],
           "defects": defects}
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return REFUSED if defects else 0


# --------------------------------------------------------------------------
# Subcommands


def _build(args):
    source_path, text, fields = resolve_source(args)
    target = resolve_target(args)
    if (target["language"] == fields.get("language")
            and target["audience"] == fields.get("audience_id")):
        raise Refusal(
            f"target {target['platform']!r} names the same reader and language as the "
            "source canonical, so there is nothing to adapt — emit it as a variant "
            "instead (`emit variants`), which is pure packaging")
    conv = resolve_conventions(args, target["language"])
    plan = skeleton(source_path, fields, target, conv, sections(text))
    if getattr(args, "fill", None):
        raw = sys.stdin.read() if args.fill == "-" else open(args.fill, encoding="utf-8").read()
        try:
            fill = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise Refusal(f"--fill is not valid JSON: {exc}")
        plan = merge_fill(plan, fill)
    return plan


def cmd_plan(args):
    print(json.dumps(_build(args), indent=2, ensure_ascii=False))
    return 0


def cmd_payload(args):
    print(json.dumps(compose_payload(_build(args)), indent=2, ensure_ascii=False))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, help_ in (("plan", "compose the adaptation plan (skeleton, or filled with --fill)"),
                        ("payload", "emit the filled plan as an owner-facing proposal payload"),
                        ("write", "persist the derived canonical after the recorded answer")):
        sp = sub.add_parser(name, help=help_)
        sp.add_argument("--slug", required=True,
                        help="slug of the PERSISTED source canonical at <output.drafts>/<slug>.md")
        sp.add_argument("--target", required=True,
                        help="adaptation target: the id of the platform profile that "
                             "declares the target reader and language")
        sp.add_argument("--draft", help="explicit path to the source canonical; anything "
                                        "other than the persisted canonical is refused")
        sp.add_argument("--root", help="host repo root (default: git toplevel of cwd)")
        sp.add_argument("--profiles-dir", help="platform-profiles directory override (tests)")
        sp.add_argument("--conventions", help="language-conventions.yaml override (tests)")
        sp.add_argument("--fill", help="JSON file (or - for stdin) carrying the authored "
                                       "plan slots")
        if name == "write":
            sp.add_argument("--body", required=True,
                            help="file (or - for stdin) carrying the derived "
                                 "canonical's target-language prose, authored from the "
                                 "approved plan")
            sp.add_argument("--ws", required=True,
                            help="run workspace holding the gate's recorded answer; "
                                 "without an approve/modify answer nothing is written")
            sp.add_argument("--create-out", action="store_true",
                            help="consent to creating an output.drafts directory that "
                                 "resolves outside the host repo")

    la = sub.add_parser("lint-ancestry",
                        help="name every defect in a derived canonical's ancestry block")
    la.add_argument("--derived", required=True, help="path to the derived canonical")
    la.add_argument("--root", help="host repo root (default: git toplevel of cwd)")

    st = sub.add_parser("staleness",
                        help="the chained staleness check: source canonical -> "
                             "derivation -> its variants (CAP-5)")
    st.add_argument("--derived", help="one derived canonical (default: every "
                                      "derivation at the resolved output.drafts)")
    st.add_argument("--root", help="host repo root (default: git toplevel of cwd)")

    cc = sub.add_parser("claims-check",
                        help="compare source and derived claim sets (CAP-2)")
    cc.add_argument("--source-map", required=True,
                    help="the source canonical's provenance map")
    cc.add_argument("--derived-map", required=True,
                    help="the derived canonical's provenance map")
    cc.add_argument("--fill", help="the approved plan's JSON, for its declared omissions")

    args = p.parse_args(argv)
    if args.cmd in ("payload", "write") and not args.fill:
        sys.stderr.write(f"error: {args.cmd} requires --fill (an unfilled plan is "
                         "neither presentable nor writable)\n")
        return USAGE
    fn = {"plan": cmd_plan, "payload": cmd_payload, "write": cmd_write,
          "lint-ancestry": cmd_lint_ancestry, "staleness": cmd_staleness,
          "claims-check": cmd_claims_check}[args.cmd]
    try:
        return fn(args)
    except Refusal as exc:
        return _err(str(exc))


if __name__ == "__main__":
    sys.exit(main())
