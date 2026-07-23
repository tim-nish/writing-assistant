#!/usr/bin/env python3
"""policy-gateway-stub.py — stub tsurezure-gateway MCP stdio server for check
harnesses (Story 13.72). stdlib only.

Speaks just enough line-delimited JSON-RPC for the reader's client:
`initialize`, `notifications/initialized` (ignored), `tools/list` (the
registered tool set, used to detect `surface_names`), and `tools/call` for the
gateway's tools (`glossary_entry`, `lessons_index`, `topic_thread`,
`policy_lookup`, `surface_names`), serving fixture content in the real
gateway's response envelope ({miss, pin, cites, lines, consulted} / {names} /
uniform miss shape).

Usage: policy-gateway-stub.py FIXTURE.json

Fixture format:
  {
    "pin": "product-lab@<40-hex>",
    "lessons":  [[file, line, text], ...],          # lessons_index hit lines
    "topics":   {"name": [[file, line, text], ...]},# topic_thread whole files
    "glossary": {"entry-name": [[file, line, text], ...]},
    "policy":   [[file, line, text], ...],          # policy_lookup hit lines
    "surface":  {"topics": [name, ...],             # surface_names identifiers
                 "glossary": [name, ...],
                 "lessons": [name, ...]},
    "surface_envelope": "names" | "lines",          # which served shape (below)
    "tools":    [name, ...]                          # registered tools/list set
  }
`surface_envelope` selects how surface_names answers: `names` (the spec's bare
list, the default) or `lines` (the cite-carrying envelope the live gateway
returns). Both are served in the wild, so both are fixtures.
Empty/absent arrays serve the uniform miss shape. `tools` defaults to all five
registered tools (incl. surface_names, tsurezure-gateway#41); omit surface_names
from it to simulate an older gateway that lacks bounded enumeration.

Harnesses point the reader here via WRITING_ASSISTANT_GATEWAY_CMD (the
documented test seam), e.g.:
  WRITING_ASSISTANT_GATEWAY_CMD="python3 scripts/fixtures/policy-gateway-stub.py fx.json"
"""

import json
import sys

DEFAULT_TOOLS = ["glossary_entry", "lessons_index", "topic_thread",
                 "policy_lookup", "surface_names"]


def registered_tools(fixture):
    return fixture.get("tools", DEFAULT_TOOLS)


def responses(fixture):
    pin = fixture["pin"]
    commit = pin.rsplit("@", 1)[1]
    tools = registered_tools(fixture)

    def hit(triples):
        lines = [{"cite": f"{f}:{n}@{commit}", "text": t} for f, n, t in triples]
        return {"miss": False, "pin": pin,
                "cites": [l["cite"] for l in lines], "lines": lines,
                "consulted": f"consulted: {pin} (stub)"}

    def miss(tool, request):
        return {"miss": True, "tool": tool, "request": request, "pin": pin,
                "consulted": f"consulted: {pin} miss"}

    def tool_call(name, args):
        if name == "lessons_index":
            triples = fixture.get("lessons", [])
            return hit(triples) if triples else miss(name, {"tags": args.get("tags")})
        if name == "topic_thread":
            triples = fixture.get("topics", {}).get(args.get("topic", ""), [])
            return hit(triples) if triples else miss(name, {"topic": args.get("topic")})
        if name == "glossary_entry":
            triples = fixture.get("glossary", {}).get(args.get("name", "").lower(), [])
            return hit(triples) if triples else miss(name, {"name": args.get("name")})
        if name == "policy_lookup":
            triples = fixture.get("policy", [])
            return hit(triples) if triples else miss(
                name, {"question": args.get("question"),
                       "topic_hints": args.get("topic_hints")})
        if name == "surface_names":
            # An older gateway does not register the tool at all — the reader
            # gates on tools/list, but honor the boundary here too (unknown).
            if "surface_names" not in tools:
                return None
            kind = args.get("kind", "")
            names = fixture.get("surface", {}).get(kind, [])
            if names:
                # Two served shapes, both real: the spec's bare `names` list,
                # and the cite-carrying `lines` envelope the LIVE gateway
                # actually returns (observed against product-lab@f7d5a73,
                # 2026-07-23). `surface_envelope: "lines"` in the fixture
                # selects the latter, so a reader that only reads `names`
                # cannot pass the harness while silently enumerating nothing
                # in production.
                if fixture.get("surface_envelope") == "lines":
                    lines = [{"cite": f"{kind}/{n}.md:1@{commit}", "text": n}
                             for n in names]
                    return {"miss": False, "pin": pin, "kind": kind,
                            "lines": lines,
                            "cites": [l["cite"] for l in lines],
                            "consulted": f"consulted: {pin} (stub)"}
                return {"miss": False, "pin": pin, "kind": kind, "names": names,
                        "consulted": f"consulted: {pin} (stub)"}
            return {"miss": True, "tool": name, "request": {"kind": kind},
                    "pin": pin, "consulted": f"consulted: {pin} miss"}
        return None
    return tool_call


def main():
    with open(sys.argv[1], encoding="utf-8") as fh:
        fixture = json.load(fh)
    tool_call = responses(fixture)
    tools = registered_tools(fixture)
    for raw in sys.stdin:
        raw = raw.strip()
        if not raw:
            continue
        msg = json.loads(raw)
        method = msg.get("method")
        rid = msg.get("id")
        if rid is None:
            continue  # notification
        if method == "initialize":
            result = {"protocolVersion": "2024-11-05",
                      "capabilities": {"tools": {}},
                      "serverInfo": {"name": "policy-gateway-stub", "version": "0"}}
        elif method == "tools/list":
            result = {"tools": [{"name": n} for n in tools]}
        elif method == "tools/call":
            params = msg.get("params", {})
            payload = tool_call(params.get("name"), params.get("arguments", {}))
            if payload is None:
                print(json.dumps({"jsonrpc": "2.0", "id": rid,
                                  "error": {"code": -32602,
                                            "message": f"unknown tool {params.get('name')!r}"}}),
                      flush=True)
                continue
            result = {"content": [{"type": "text", "text": json.dumps(payload)}]}
        else:
            print(json.dumps({"jsonrpc": "2.0", "id": rid,
                              "error": {"code": -32601, "message": f"unknown method {method!r}"}}),
                  flush=True)
            continue
        print(json.dumps({"jsonrpc": "2.0", "id": rid, "result": result}), flush=True)


if __name__ == "__main__":
    main()
