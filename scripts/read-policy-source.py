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

The read scope is unchanged and still code-bounded:

  * `GLOSSARY.md` and `LESSONS.md`, always (whitelist);
  * at most 2 `topics/*.md` — the per-run `read --topics` selection the owner
    approved in draft-article Stage 2 (Story 13.35);
  * everything else is structurally unreadable — and now also unservable: the
    gateway's grant table enforces the same boundary on its side.

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
  read [--only NAME ...] [--topics NAME.md ...]
                   Print the pin (`pin: <pin>`), then each served file as a
                   `=== FILE @ <sha>` section with `N: text` lines, numbers and
                   text taken verbatim from the gateway's cites:
                     * LESSONS.md    <- `lessons_index` (every index line at its
                                        true line number);
                     * topics/*.md   <- `topic_thread` (whole file, line-quoted);
                     * GLOSSARY.md   <- `surface_names(kind=glossary)` enumerates
                                        the entry names, then per-entry
                                        `glossary_entry` calls compose the whole
                                        file (Story 18.16). An older gateway
                                        without `surface_names` degrades to the
                                        named exit-13 gap (not composable).
                   A gateway MISS is a served answer, not an error: it prints as
                   `miss: FILE` under the pin (exit 0) so the caller can surface
                   it with the question (consult-first convention). --only and
                   --topics keep their exact refusal semantics (exit 5).

Exit codes — the caller keys graceful degradation (CAP-6) off these:

  0   success (including served misses)
  2   usage / host-root resolution errors
  4   policy_source block malformed OR carrying a retired key (`path` — 13.73;
      `track`/`topics` — 13.36): the resolver's report, migration notice
      included, is relayed verbatim; a retired key is never silently honored
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

MAX_TOPICS = 2  # CAP-2: at most 2 topic files per read
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
    is in fact correct (observed 2026-07-23 against product-lab@f7d5a73). Both
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


def build_whitelist(override_topics=None):
    """The code-enforced allowlist of hub-relative names: GLOSSARY + LESSONS
    always; then the <=2 per-run `--topics` selection (Story 13.35). Static —
    the gateway's grant table is the serving-side enforcement of the same
    boundary."""
    entries = list(BASE_FILES)
    if override_topics is not None:
        for t in override_topics[:MAX_TOPICS]:
            entries.append("topics/" + t)
    return entries


def validate_run_topics(names):
    """Validate a per-run --topics selection (Story 13.35): basenames only, at
    most MAX_TOPICS. Returns an error string or None."""
    if len(names) > MAX_TOPICS:
        return (f"refused: --topics takes at most {MAX_TOPICS} files "
                f"(got {len(names)}) — the ≤{MAX_TOPICS} cap is code-enforced")
    for t in names:
        if "/" in t or os.sep in t or ".." in t or t.startswith("."):
            return (f"refused: --topics entries are basenames under topics/ "
                    f"({t!r} is not) — no other path is readable")
    return None


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
    override = getattr(args, "topics", None)
    if override is not None:
        bad = validate_run_topics(override)
        if bad:
            sys.stderr.write(bad + "\n")
            return REFUSED
    whitelist = build_whitelist(override_topics=override)
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
    calls = []
    for rel in simple:
        if rel == "LESSONS.md":
            calls.append(("lessons_index", {}))
        else:  # topics/<name>.md — whitelist guarantees the shape
            calls.append(("topic_thread", {"topic": os.path.basename(rel)[:-3]}))
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
    sp = sub.add_parser("read", parents=[root_parent])
    sp.add_argument("--only", nargs="+",
                    help="restrict to these whitelist entries; anything else is refused (exit 5)")
    sp.add_argument("--topics", nargs="+", metavar="NAME.md",
                    help="per-run topic selection (Story 13.35): BUILD the "
                    "whitelist from these <=2 basenames under topics/ (distinct "
                    "from --only, which filters within an already-built "
                    "whitelist); >2 or a non-basename is refused (exit 5)")
    args = p.parse_args(argv)
    if not hasattr(args, "root"):
        args.root = None
    return {"whitelist": cmd_whitelist, "pin": cmd_pin,
            "list-topics": cmd_list_topics, "read": cmd_read}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
