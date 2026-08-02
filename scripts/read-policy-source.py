#!/usr/bin/env python3
"""read-policy-source.py — bounded, pinned, READ-ONLY policy reader, served by
tsurezure-gateway (Story 13.72, SPEC-policy-source-seam CAP-2 as amended
2026-07-18: served transport, same CLI contract; umbrella issue #366).

The CLI contract is unchanged from the filesystem-era reader — same
subcommands, flags, output shapes, and `file:line@commit` evidence grammar —
but every byte of policy content now arrives over MCP `tools/call` requests to
the tsurezure-gateway stdio server (consumer `writing-assistant`). The reader
opens ZERO files under any hub path: it does not know the hub path — the
`policy_source` config block is a presence toggle (`enabled: true`, Story
13.73/#366; the retired `path` key is a relayed configuration error) — and it
never runs `git -C <hub>`. The gateway resolves the hub from its own operator
config; the pin and every citation are passed through from gateway payloads
verbatim.

The read scope is code-bounded:

  * `GLOSSARY.md` and `LESSONS.md`, always (whitelist);
  * everything else is structurally unreadable — and now also unservable: the
    gateway's grant table enforces the same boundary on its side.
  * The per-run `read --topics` whitelist-building input (Story 13.35) was
    REMOVED by Story 20.161 (SPEC-policy-topic-at-draft amended 2026-08-02,
    #1246): nothing selects topic files in advance any more — a read needing
    served policy is asked as a `query --claim`. The PERMISSION boundary is
    unchanged: the gateway's grant table still decides what may be served.

Gateway transport: the server command is resolved from the environment
variable `WRITING_ASSISTANT_GATEWAY_CMD` (a shell-split command string — the
test seam; check harnesses point it at a stub server), else the registration
default `node ~/work/tsurezure-gateway/dist/index.js --consumer
writing-assistant`. All I/O carries a 30s timeout; a hung or missing gateway
degrades to exit 11, never a hang.

Subcommands (each takes --root, the HOST repo root; default: git top-level):

  whitelist        Print the static allowlist, one path per line (GLOSSARY.md,
                   LESSONS.md). Needs no gateway call — it names what MAY be
                   requested, not what the hub contains.
  pin              Print the gateway's pin verbatim (`<policy-source>@<commit>`,
                   e.g. `product-lab@<sha>`) — present on hits and misses alike.
  list-topics      Enumerate topics/*.md names via `surface_names(kind=topics)`
                   (Story 18.16 — tsurezure-gateway#41 closed the exit-13 gap):
                   one identifier per line. An older gateway that lacks
                   `surface_names` degrades to the named exit-13 gap and the
                   caller asks the owner for topic names (proposal contract).
  gloss [--tag TAG]  Read the plain-register Gloss surface via the gateway's
                   two-tier `gloss_index` tool (hub spec `specs/gloss.md`;
                   tsurezure-gateway#64). With no --tag: the whole tier-1
                   overview index (one headline line per lesson — the first
                   sentence of the ratified `gloss:` rendering, verbatim).
                   With --tag: that tier-2 shard whole. Output shape matches
                   `read`: `pin:`, then `=== FILE @ sha` sections with
                   `N: text` lines. A gateway that does not register
                   `gloss_index` degrades to a NAMED exit-13 tool-surface gap
                   (the same shape as the pre-#41 surface_names gap) — the
                   caller discloses the reason and never invents a rendering.
  query --claim TEXT
                   CLAIM-BOUNDED read (Story 20.160, #1255): one claim in, the
                   gateway's `policy_lookup` matched lines out, in the same
                   output grammar as `read`. Nothing selects topic files in
                   advance — the bound is the claim, not a pre-picked file set
                   — so the ≤2 cap and the read whitelist are not consulted on
                   this path; the gateway's grant table remains the permission
                   boundary. This is the seeding transport for stage 2's
                   tension questions. A gateway not registering `policy_lookup`
                   is the named exit-13 gap; a served miss prints as
                   `miss: query <claim>` under the pin (exit 0).
  read [--only NAME ...]
                   Print the pin (`pin: <pin>`), then each served file as a
                   `=== FILE @ <sha>` section with `N: text` lines, numbers and
                   text taken verbatim from the gateway's cites:
                     * LESSONS.md    <- `lessons_index` (every index line at its
                                        true line number);
                     * GLOSSARY.md   <- `surface_names(kind=glossary)` enumerates
                                        the entry names, then per-entry
                                        `glossary_entry` calls compose the whole
                                        file (Story 18.16). An older gateway
                                        without `surface_names` degrades to the
                                        named exit-13 gap (not composable).
                   A gateway MISS is a served answer, not an error: it prints as
                   `miss: FILE` under the pin (exit 0) so the caller can surface
                   it with the question (consult-first convention). --only keeps
                   its exact refusal semantics (exit 5).

Exit codes — the caller keys graceful degradation (CAP-6) off these:

  0   success (including served misses)
  2   usage / host-root resolution errors
  4   policy_source block malformed OR carrying the retired `path` key (13.73):
      the resolver's report, migration notice included, is relayed verbatim; the
      retired key is never silently honored
  5   REFUSED: a requested path is outside the code whitelist
  10  unavailable: policy_source not declared / `enabled` falsy
                                                    (degrade: generic mode, silent)
  11  unavailable: gateway unreachable / transport error / timeout
      (degrade: generic mode, log once; the old 11/12 path-vs-git distinction
      collapses here — 12 is never emitted, though callers still accept it)
  13  NAMED TOOL-SURFACE GAP (fallback only, Story 18.16): the subcommand's
      surface cannot be composed because the gateway is too old to register
      `surface_names` (degrade like 11/12: one line, generic mode). A current
      gateway serves list-topics and whole-GLOSSARY via `surface_names`, so 13
      is no longer reached on the happy path.

For 10/11 a single `policy_source unavailable: <reason>` line goes to stderr;
for 13 a single `policy tool-surface gap: <reason>` line. The run never fails
because of the policy source.
"""

import argparse
import importlib.util
import json
import os
import shlex
import subprocess
import sys

REFUSED = 5
MALFORMED = 4
UNAVAIL_UNSET = 10
UNAVAIL_GATEWAY = 11  # old 11 (path) and 12 (git) collapse here
TOOL_GAP = 13

BASE_FILES = ("GLOSSARY.md", "LESSONS.md")

GATEWAY_CMD_ENV = "WRITING_ASSISTANT_GATEWAY_CMD"
DEFAULT_GATEWAY_CMD = [
    "node",
    os.path.expanduser("~/work/tsurezure-gateway/dist/index.js"),
    "--consumer", "writing-assistant",
]
GATEWAY_TIMEOUT = 30  # seconds; a hung gateway degrades to exit 11, never hangs

# Named tool-surface gaps — now the OLDER-GATEWAY fallback only (Story 18.16):
# tsurezure-gateway#41 shipped `surface_names`, which composes both surfaces on
# a current gateway. These strings still describe why a pre-#41 gateway cannot
# serve them, and are emitted on that fallback path (never on the happy path).
GAP_LIST_TOPICS = (
    "gateway cannot enumerate topics (no tool lists topics/*.md names; "
    "topic_thread needs an exact name and its miss names no candidates)")
GAP_WHOLE_GLOSSARY = (
    "gateway cannot serve GLOSSARY.md whole (glossary_entry is per-entry by "
    "heading and entry names are not enumerable; policy_lookup serves only "
    "query-matched lines)")
GAP_GLOSS = (
    "gateway does not register gloss_index (the two-tier plain-register Gloss "
    "surface, tsurezure-gateway#64) — the deployed gateway predates it or its "
    "operator config declares no gloss surface; serving it is a hub-side act, "
    "never a consumer-side workaround")
GAP_QUERY = (
    "gateway does not register policy_lookup (the claim-bounded query tool the "
    "seeding read is asked through) — the deployed gateway predates it or its "
    "operator config grants no queryable surface; serving it is a hub-side act, "
    "never a consumer-side workaround")
GAP_ELEMENTS = (
    "gateway does not register element_survey (the structured element-manifest "
    "survey, tsurezure-gateway#76) — the deployed gateway predates it; serving "
    "it is a hub-side act, never a consumer-side workaround")


def _load_rws():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


RWS = _load_rws()


def resolve_policy_source(root):
    """The declared policy_source presence toggle via the one config parse
    path (Story 13.73: block = {"enabled": bool} — no hub path exists in
    consumer config; a leftover retired `path` key is a relayed configuration
    error, exit 4, migration notice included, never silently honored).

    Returns (block, None) or (None, (exit_code, reason))."""
    block, errors = RWS.get_policy_source(RWS.read_lines(root), root)
    if block is None:
        return None, (UNAVAIL_UNSET, "policy_source not declared in writing-sources.yaml")
    if errors:
        for key, msg in errors:
            sys.stderr.write(f"[{RWS.SOURCES_FILE}] {key}: {msg}\n")
        return None, (MALFORMED, "policy_source block is malformed (see stage-0 validation)")
    if not block["enabled"]:
        return None, (UNAVAIL_UNSET,
                      "policy_source disabled (enabled: false) in writing-sources.yaml")
    return block, None


class GatewayError(Exception):
    """Any transport-level failure reaching the gateway (exit 11)."""


def gateway_cmd():
    """The gateway server command: env seam first, then the MCP registration
    default. Never read from ~/.claude.json."""
    raw = os.environ.get(GATEWAY_CMD_ENV, "").strip()
    if raw:
        return shlex.split(raw)
    return list(DEFAULT_GATEWAY_CMD)


_INIT_MSGS = (
    {"jsonrpc": "2.0", "id": 1, "method": "initialize",
     "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                "clientInfo": {"name": "read-policy-source", "version": "13.72"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized"},
)


def _session(requests):
    """One gateway session: initialize, then the id-bearing JSON-RPC
    `requests` (a batch). Returns ({id: response_dict}, returncode). Any
    transport failure — command missing, timeout — raises GatewayError; the
    reader NEVER falls back to reading files."""
    msgs = list(_INIT_MSGS) + list(requests)
    cmd = gateway_cmd()
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True)
    except OSError as e:
        raise GatewayError(f"cannot spawn gateway {cmd[0]!r}: {e}") from e
    try:
        out, _err = proc.communicate(
            "".join(json.dumps(m) + "\n" for m in msgs), timeout=GATEWAY_TIMEOUT)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.communicate()
        raise GatewayError(f"timeout after {GATEWAY_TIMEOUT}s") from None
    responses = {}
    for line in out.splitlines():
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if isinstance(d, dict) and "id" in d:
            responses[d["id"]] = d
    return responses, proc.returncode


def call_gateway(calls):
    """A `tools/call` per (tool, args), all in one session.

    All requests are independent, so they are written in one batch and the
    line-delimited JSON-RPC responses matched back by id. Returns the parsed
    tool payloads (the gateway's JSON response objects) in call order. Any
    transport failure — command missing, timeout, nonzero exit with no
    responses, unparsable or missing response, JSON-RPC error — raises
    GatewayError; the reader NEVER falls back to reading files.
    """
    requests = []
    ids = []
    for i, (tool, arguments) in enumerate(calls):
        rid = 100 + i
        ids.append(rid)
        requests.append({"jsonrpc": "2.0", "id": rid, "method": "tools/call",
                         "params": {"name": tool, "arguments": arguments}})
    responses, returncode = _session(requests)
    payloads = []
    for rid, (tool, _a) in zip(ids, calls):
        d = responses.get(rid)
        if d is None:
            raise GatewayError(
                f"no response for {tool} (gateway exit {returncode})")
        if "error" in d:
            raise GatewayError(f"{tool}: {d['error'].get('message', 'JSON-RPC error')}")
        try:
            payload = json.loads(d["result"]["content"][0]["text"])
        except (KeyError, IndexError, TypeError, ValueError) as e:
            raise GatewayError(f"{tool}: malformed response payload ({e})") from e
        payloads.append(payload)
    return payloads


def gateway_tool_names():
    """The set of tool names the gateway registers (MCP `tools/list`). Used to
    detect whether the gateway is new enough to serve `surface_names` before a
    surface is composed from it — an older gateway lacks the tool and the
    caller falls back to the named exit-13 gap (degrade, don't crash). A real
    transport failure (spawn, timeout) raises GatewayError; a gateway that
    answers but omits or errors on `tools/list` yields an empty set, which
    reads as 'no surface_names' and takes the same safe fallback."""
    rid = 50
    responses, _rc = _session(
        [{"jsonrpc": "2.0", "id": rid, "method": "tools/list", "params": {}}])
    d = responses.get(rid)
    if d is None or "error" in d:
        return set()
    try:
        return {t["name"] for t in d["result"]["tools"]}
    except (KeyError, TypeError):
        return set()


def has_surface_names():
    """True when the gateway registers the bounded-enumeration `surface_names`
    tool (closed the exit-13 gaps upstream, tsurezure-gateway#41). Gates the
    surface_names path; its absence is the older-gateway exit-13 fallback."""
    return "surface_names" in gateway_tool_names()


def surface_names(kind):
    """Bounded enumeration via the gateway's `surface_names` tool
    (kind: topics | glossary | lessons): identifiers only, never bodies
    (spec §3). Returns the payload dict; read the identifiers out of it with
    `surface_identifiers` rather than by key, because the served envelope has
    two shapes. Callers
    gate this behind has_surface_names(), so an older gateway degrades to the
    named exit-13 gap and never reaches here."""
    (payload,) = call_gateway([("surface_names", {"kind": kind})])
    return payload


def surface_identifiers(payload):
    """The identifiers out of a `surface_names` payload, in served order.

    The gateway serves the enumeration in the SAME cite-carrying envelope its
    other tools use — `lines: [{cite, text}]`, one identifier per `text` — and
    the spec also documents a bare `names` list. Reading only `names` silently
    yields an empty enumeration against the live gateway, which is not a
    harmless miss: `validate-config.py`'s topic-existence lint treats a
    successful-but-empty enumeration as authoritative and reports every mapped
    topic as absent from the hub — a blocking stage-0 error for a mapping that
    is in fact correct (observed 2026-07-23 against product-lab@<private-pin>). Both
    shapes are accepted, so neither a current nor a future gateway can
    reintroduce that silence.
    """
    names = payload.get("names")
    if isinstance(names, list) and names:
        return [str(n) for n in names if str(n).strip()]
    out = []
    for entry in payload.get("lines") or []:
        text = str((entry or {}).get("text") or "").strip()
        if text:
            out.append(text)
    return out


def split_cite(cite):
    """`file:line@commit` -> (file, line, commit) — passthrough, no rewriting."""
    fileline, commit = cite.rsplit("@", 1)
    file, line = fileline.rsplit(":", 1)
    return file, int(line), commit


def build_whitelist():
    """The code-enforced allowlist of hub-relative names: GLOSSARY + LESSONS.
    Static — the gateway's grant table is the serving-side enforcement of the
    same boundary. The per-run `--topics` whitelist-building input was removed
    by Story 20.161 (#1246): a read needing served policy beyond this surface
    is asked as a `query --claim`, bounded by the claim rather than by a
    pre-picked file set."""
    return list(BASE_FILES)


def _unavailable(code_reason):
    code, reason = code_reason
    if code in (UNAVAIL_UNSET, UNAVAIL_GATEWAY):
        sys.stderr.write(f"policy_source unavailable: {reason}\n")
    return code


def _tool_gap(reason):
    sys.stderr.write(f"policy tool-surface gap: {reason}\n")
    return TOOL_GAP


def cmd_whitelist(args):
    """The static allowlist — what MAY be requested. Never needed the
    filesystem; now needs no gateway call either."""
    root = RWS.host_root(args.root)
    _block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    for rel in build_whitelist():
        print(rel)
    return 0


def cmd_pin(args):
    root = RWS.host_root(args.root)
    _block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    try:
        (payload,) = call_gateway([("lessons_index", {})])
    except GatewayError as e:
        return _unavailable((UNAVAIL_GATEWAY, f"gateway unreachable ({e})"))
    print(payload["pin"])
    return 0


def cmd_list_topics(args):
    """Enumerate topics/*.md via the gateway's `surface_names(kind=topics)`
    tool (Story 18.16 — tsurezure-gateway#41 closed the exit-13 gap): print
    each topic identifier, one per line. An older gateway that lacks
    `surface_names` degrades to the named exit-13 gap (GAP_LIST_TOPICS) — the
    caller then asks the owner for topic names (draft-article Stage 2,
    proposal contract)."""
    root = RWS.host_root(args.root)
    _block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    try:
        if not has_surface_names():
            return _tool_gap(GAP_LIST_TOPICS)
        payload = surface_names("topics")
    except GatewayError as e:
        return _unavailable((UNAVAIL_GATEWAY, f"gateway unreachable ({e})"))
    for name in surface_identifiers(payload):
        print(name)
    return 0


def _emit_section(payload):
    """One `=== FILE @ sha` section from a gateway hit — file names, line
    numbers, and text are the gateway's own, passed through verbatim."""
    lines = payload["lines"]
    served_rel, _n, served_sha = split_cite(lines[0]["cite"])
    print(f"=== {served_rel} @ {served_sha}")
    for entry in lines:
        _f, n, _c = split_cite(entry["cite"])
        print(f"{n}: {entry['text']}")


def _emit_sections(payload):
    """`=== FILE @ sha` sections from a gateway hit whose lines may span more
    than one served file (the gloss tier-1 index is grouped per index file).
    File names, line numbers, and text are the gateway's own, verbatim."""
    current = None
    for entry in payload["lines"]:
        rel, n, sha = split_cite(entry["cite"])
        if rel != current:
            print(f"=== {rel} @ {sha}")
            current = rel
        print(f"{n}: {entry['text']}")


def cmd_gloss(args):
    """The plain-register Gloss surface, via `gloss_index` (two-tier: no tag ->
    the whole tier-1 overview index; --tag -> that tier-2 shard whole). A
    gateway that does not register the tool is the NAMED exit-13 gap — the
    surface exists in the gateway's contract but this deployment cannot serve
    it, and the caller degrades with the reason rather than substituting any
    other text for a ratified rendering."""
    root = RWS.host_root(args.root)
    _block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    try:
        if "gloss_index" not in gateway_tool_names():
            return _tool_gap(GAP_GLOSS)
        arguments = {"tag": args.tag} if getattr(args, "tag", None) else {}
        (payload,) = call_gateway([("gloss_index", arguments)])
    except GatewayError as e:
        return _unavailable((UNAVAIL_GATEWAY, f"gateway unreachable ({e})"))
    print(f"pin: {payload['pin']}")
    if payload.get("miss"):
        # A miss is a SERVED answer under the pin — an empty or ungranted
        # gloss surface, distinguishable from unavailability.
        print(f"miss: gloss{f' --tag {args.tag}' if getattr(args, 'tag', None) else ''}")
        return 0
    _emit_sections(payload)
    return 0


def cmd_elements(args):
    """The hub's element manifest as structured records, via `element_survey`
    (tsurezure-gateway#76): every record matching the optional --kind/--tag
    filters, complete per query (the tool's contract — no floor, no cap, no
    truncation), each record line passed through VERBATIM in the standard
    output grammar. A gateway that does not register the tool is the NAMED
    exit-13 gap; a served miss (undeclared or empty manifest, unknown filter)
    is a served answer under the pin, distinguishable from unavailability."""
    root = RWS.host_root(args.root)
    _block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    arguments = {}
    if getattr(args, "kind", None):
        arguments["kind"] = args.kind
    if getattr(args, "tag", None):
        arguments["tag"] = args.tag
    try:
        if "element_survey" not in gateway_tool_names():
            return _tool_gap(GAP_ELEMENTS)
        (payload,) = call_gateway([("element_survey", arguments)])
    except GatewayError as e:
        return _unavailable((UNAVAIL_GATEWAY, f"gateway unreachable ({e})"))
    print(f"pin: {payload['pin']}")
    if payload.get("miss"):
        suffix = "".join(
            f" --{k} {v}" for k, v in (("kind", arguments.get("kind")),
                                       ("tag", arguments.get("tag"))) if v)
        print(f"miss: elements{suffix}")
        return 0
    _emit_sections(payload)
    return 0


def cmd_query(args):
    """Claim-bounded read: one CLAIM in, the served MATCHED lines out, via the
    gateway's `policy_lookup` tool (Story 20.160, #1255;
    SPEC-policy-topic-at-draft amended 2026-08-02, #1246).

    This is the seeding transport for draft-article stage 2. The bound is the
    CLAIM, not a pre-picked file set: nothing selects topic files in advance
    (the `--topics` input itself is gone, Story 20.161), and the read whitelist
    is not consulted here at all.
    The PERMISSION boundary is untouched — the gateway's own grant table
    decides what may be served, exactly as it does for `read` — and the output
    grammar is the same `pin:` + `=== FILE @ sha` + `N: text`, so a caller
    already handling a surface file handles this one unchanged.

    A gateway that does not register `policy_lookup` is a NAMED exit-13
    tool-surface gap; a served miss (no matched line) is a served answer under
    the pin, distinguishable from unavailability, and the caller surfaces it
    with the question per the consult-first convention.
    """
    root = RWS.host_root(args.root)
    _block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    claim = (getattr(args, "claim", "") or "").strip()
    if not claim:
        sys.stderr.write("refused: query takes a non-empty --claim (the "
                         "question the read is bounded by)\n")
        return REFUSED
    try:
        if "policy_lookup" not in gateway_tool_names():
            return _tool_gap(GAP_QUERY)
        (payload,) = call_gateway([("policy_lookup", {"question": claim})])
    except GatewayError as e:
        return _unavailable((UNAVAIL_GATEWAY, f"gateway unreachable ({e})"))
    print(f"pin: {payload['pin']}")
    if payload.get("miss"):
        print(f"miss: query {claim}")
        return 0
    _emit_sections(payload)
    return 0


def compose_glossary(names):
    """Compose the whole GLOSSARY.md section from per-entry `glossary_entry`
    calls (Story 18.16): `surface_names(kind=glossary)` gives the entry
    identifiers, the bodies come one entry at a time. Returns a payload-shaped
    dict whose merged, line-sorted `lines` carry the gateway's own
    `file:line@commit` cites unchanged — so _emit_section renders a single
    `=== GLOSSARY.md @ sha` section in the file's true line order. Every entry
    a miss (or no entries) yields {'miss': True}, a served empty answer."""
    if not names:
        return {"miss": True}
    payloads = call_gateway([("glossary_entry", {"name": n}) for n in names])
    merged = []
    pin = None
    for payload in payloads:
        if payload.get("miss"):
            continue
        pin = payload["pin"]
        merged.extend(payload["lines"])
    if not merged:
        return {"miss": True}
    merged.sort(key=lambda entry: split_cite(entry["cite"])[1])
    return {"miss": False, "pin": pin, "lines": merged}


def cmd_read(args):
    root = RWS.host_root(args.root)
    _block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    whitelist = build_whitelist()
    targets = []
    for name in (args.only or whitelist):
        match = next((rel for rel in whitelist
                      if rel == name or os.path.basename(rel) == name), None)
        if match is None:
            sys.stderr.write(
                f"refused: {name!r} is not on the policy read whitelist "
                f"({', '.join(whitelist)}); q_a/ and all other "
                "paths are structurally unreadable\n")
            return REFUSED
        if match not in targets:
            targets.append(match)
    # GLOSSARY.md whole-file composes from surface_names + per-entry
    # glossary_entry (Story 18.16). The others are single tool calls.
    want_glossary = "GLOSSARY.md" in targets
    simple = [rel for rel in targets if rel != "GLOSSARY.md"]
    # The whitelist admits only LESSONS.md here (topics left with the removed
    # `--topics` input, Story 20.161).
    calls = [("lessons_index", {}) for rel in simple if rel == "LESSONS.md"]
    pin = None
    glossary = None
    try:
        if want_glossary:
            # Older gateway without surface_names: the whole-GLOSSARY surface is
            # not composable — the named exit-13 gap stays the honest fallback.
            if not has_surface_names():
                return _tool_gap(GAP_WHOLE_GLOSSARY)
            names_payload = surface_names("glossary")
            pin = names_payload.get("pin")
            glossary = compose_glossary(surface_identifiers(names_payload))
        payloads = call_gateway(calls) if calls else []
    except GatewayError as e:
        return _unavailable((UNAVAIL_GATEWAY, f"gateway unreachable ({e})"))
    if pin is None:
        pin = payloads[0]["pin"]
    print(f"pin: {pin}")
    simple_payloads = dict(zip(simple, payloads))
    for rel in targets:
        payload = glossary if rel == "GLOSSARY.md" else simple_payloads[rel]
        if payload.get("miss"):
            # A miss is a SERVED answer under the pin — the caller surfaces it
            # (consult-first convention), distinguishable from unavailability.
            print(f"miss: {rel}")
            continue
        _emit_section(payload)
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    ROOT_HELP = "HOST-repo root (default: git top-level of cwd; errors outside a git repo)"
    p.add_argument("--root", help=ROOT_HELP)
    root_parent = argparse.ArgumentParser(add_help=False)
    root_parent.add_argument("--root", default=argparse.SUPPRESS, help=ROOT_HELP)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("whitelist", parents=[root_parent])
    sub.add_parser("pin", parents=[root_parent])
    sub.add_parser("list-topics", parents=[root_parent])
    gp = sub.add_parser("gloss", parents=[root_parent])
    gp.add_argument("--tag", metavar="TAG",
                    help="tier-2 shard tag (a shard file's basename without "
                         ".md); omit for the whole tier-1 overview index")
    ep = sub.add_parser("elements", parents=[root_parent])
    ep.add_argument("--kind", metavar="KIND",
                    help="filter records to one element kind "
                         "(lesson | journey | decision); omit for all")
    ep.add_argument("--tag", metavar="TAG",
                    help="filter records to those carrying this tag; omit for all")
    qp = sub.add_parser("query", parents=[root_parent])
    qp.add_argument("--claim", metavar="TEXT", required=True,
                    help="the claim/question the read is bounded by (Story "
                         "20.160): served matched lines out, no topic files "
                         "selected in advance")
    sp = sub.add_parser("read", parents=[root_parent])
    sp.add_argument("--only", nargs="+",
                    help="restrict to these whitelist entries; anything else is refused (exit 5)")
    # `--topics` (the whitelist-BUILDING input, Story 13.35) was removed by
    # Story 20.161 (#1246); `--only` filters within the computed whitelist and
    # stays.
    args = p.parse_args(argv)
    if not hasattr(args, "root"):
        args.root = None
    return {"whitelist": cmd_whitelist, "pin": cmd_pin,
            "list-topics": cmd_list_topics, "gloss": cmd_gloss,
            "elements": cmd_elements, "query": cmd_query,
            "read": cmd_read}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
