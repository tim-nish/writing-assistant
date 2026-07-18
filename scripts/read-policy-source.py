#!/usr/bin/env python3
"""read-policy-source.py — bounded, pinned, READ-ONLY policy reader, served by
tsurezure-gateway (Story 13.72, SPEC-policy-source-seam CAP-2 as amended
2026-07-18: served transport, same CLI contract; umbrella issue #366).

The CLI contract is unchanged from the filesystem-era reader — same
subcommands, flags, output shapes, and `file:line@commit` evidence grammar —
but every byte of policy content now arrives over MCP `tools/call` requests to
the tsurezure-gateway stdio server (consumer `writing-assistant`). The reader
opens ZERO files under any hub path: it does not know the hub path, never
joins `policy_source.path` into the filesystem, and never runs `git -C <hub>`.
The gateway resolves the hub from its own config; the pin and every citation
are passed through from gateway payloads verbatim.

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
  list-topics      TOOL-SURFACE GAP (exit 13): no gateway tool enumerates
                   topics/*.md names — `topic_thread` needs an exact name and
                   its miss shape names no candidates. The caller falls back to
                   asking the owner for topic names (proposal contract).
  read [--only NAME ...] [--topics NAME.md ...]
                   Print the pin (`pin: <pin>`), then each served file as a
                   `=== FILE @ <sha>` section with `N: text` lines, numbers and
                   text taken verbatim from the gateway's cites:
                     * LESSONS.md    <- `lessons_index` (every index line at its
                                        true line number);
                     * topics/*.md   <- `topic_thread` (whole file, line-quoted);
                     * GLOSSARY.md   <- TOOL-SURFACE GAP (exit 13):
                                        `glossary_entry` is per-entry by heading
                                        and entry names are not enumerable, so
                                        the whole-file surface is not composable.
                   A gateway MISS is a served answer, not an error: it prints as
                   `miss: FILE` under the pin (exit 0) so the caller can surface
                   it with the question (consult-first convention). --only and
                   --topics keep their exact refusal semantics (exit 5).

Exit codes — the caller keys graceful degradation (CAP-6) off these:

  0   success (including served misses)
  2   usage / host-root resolution errors
  4   policy_source block malformed (resolver's report relayed verbatim)
  5   REFUSED: a requested path is outside the code whitelist
  10  unavailable: policy_source not declared        (degrade: generic mode, silent)
  11  unavailable: gateway unreachable / transport error / timeout
      (degrade: generic mode, log once; the old 11/12 path-vs-git distinction
      collapses here — 12 is never emitted, though callers still accept it)
  13  NAMED TOOL-SURFACE GAP: the subcommand's surface cannot be composed from
      the gateway's four tools (degrade like 11/12: one line, generic mode; the
      gaps are recorded in the Story 13.72 evidence section)

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

# Named tool-surface gaps (Story 13.72 evidence; raised separately per #366's
# unresolved-questions rule). These are facts about the gateway's four tools,
# not about this reader.
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
    """The declared policy_source block via the one config parse path.

    Only the unset/malformed distinction is consumed here (exit 10 vs 4). The
    block's `path` value — which may still exist until Story 13.73 removes it —
    is IGNORED entirely: it is never joined into the filesystem.

    Returns (block, None) or (None, (exit_code, reason))."""
    block, errors = RWS.get_policy_source(RWS.read_lines(root), root)
    if block is None:
        return None, (UNAVAIL_UNSET, "policy_source not declared in writing-sources.yaml")
    if errors:
        for key, msg in errors:
            sys.stderr.write(f"[{RWS.SOURCES_FILE}] {key}: {msg}\n")
        return None, (MALFORMED, "policy_source block is malformed (see stage-0 validation)")
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


def call_gateway(calls):
    """One gateway session: initialize, then a `tools/call` per (tool, args).

    All requests are independent, so they are written in one batch and the
    line-delimited JSON-RPC responses matched back by id. Returns the parsed
    tool payloads (the gateway's JSON response objects) in call order. Any
    transport failure — command missing, timeout, nonzero exit with no
    responses, unparsable or missing response, JSON-RPC error — raises
    GatewayError; the reader NEVER falls back to reading files.
    """
    msgs = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                    "clientInfo": {"name": "read-policy-source", "version": "13.72"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
    ]
    ids = []
    for i, (tool, arguments) in enumerate(calls):
        rid = 100 + i
        ids.append(rid)
        msgs.append({"jsonrpc": "2.0", "id": rid, "method": "tools/call",
                     "params": {"name": tool, "arguments": arguments}})
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
        if isinstance(d, dict) and d.get("id") in ids:
            responses[d["id"]] = d
    payloads = []
    for rid, (tool, _a) in zip(ids, calls):
        d = responses.get(rid)
        if d is None:
            raise GatewayError(
                f"no response for {tool} (gateway exit {proc.returncode})")
        if "error" in d:
            raise GatewayError(f"{tool}: {d['error'].get('message', 'JSON-RPC error')}")
        try:
            payload = json.loads(d["result"]["content"][0]["text"])
        except (KeyError, IndexError, TypeError, ValueError) as e:
            raise GatewayError(f"{tool}: malformed response payload ({e})") from e
        payloads.append(payload)
    return payloads


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
    """NAMED TOOL-SURFACE GAP (Story 13.72 evidence): the gateway's four tools
    offer no topic enumeration, so the listing this subcommand promised cannot
    be served. Exit 13 — the caller asks the owner for topic names instead
    (draft-article Stage 2, proposal contract)."""
    root = RWS.host_root(args.root)
    _block, err = resolve_policy_source(root)
    if err:
        return _unavailable(err)
    return _tool_gap(GAP_LIST_TOPICS)


def _emit_section(payload):
    """One `=== FILE @ sha` section from a gateway hit — file names, line
    numbers, and text are the gateway's own, passed through verbatim."""
    lines = payload["lines"]
    served_rel, _n, served_sha = split_cite(lines[0]["cite"])
    print(f"=== {served_rel} @ {served_sha}")
    for entry in lines:
        _f, n, _c = split_cite(entry["cite"])
        print(f"{n}: {entry['text']}")


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
    # GLOSSARY.md whole-file is not composable from the gateway's four tools —
    # a named gap, never a guessed composition and never a file read.
    if "GLOSSARY.md" in targets:
        return _tool_gap(GAP_WHOLE_GLOSSARY)
    calls = []
    for rel in targets:
        if rel == "LESSONS.md":
            calls.append(("lessons_index", {}))
        else:  # topics/<name>.md — whitelist guarantees the shape
            calls.append(("topic_thread", {"topic": os.path.basename(rel)[:-3]}))
    try:
        payloads = call_gateway(calls)
    except GatewayError as e:
        return _unavailable((UNAVAIL_GATEWAY, f"gateway unreachable ({e})"))
    pin = payloads[0]["pin"]
    print(f"pin: {pin}")
    for rel, payload in zip(targets, payloads):
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
