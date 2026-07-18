#!/usr/bin/env python3
"""policy-gateway-stub.py — stub tsurezure-gateway MCP stdio server for check
harnesses (Story 13.72). stdlib only.

Speaks just enough line-delimited JSON-RPC for the reader's client:
`initialize`, `notifications/initialized` (ignored), and `tools/call` for the
gateway's four tools (`glossary_entry`, `lessons_index`, `topic_thread`,
`policy_lookup`), serving fixture content in the real gateway's response
envelope ({miss, pin, cites, lines, consulted} / uniform miss shape).

Usage: policy-gateway-stub.py FIXTURE.json

Fixture format:
  {
    "pin": "product-lab@<40-hex>",
    "lessons":  [[file, line, text], ...],          # lessons_index hit lines
    "topics":   {"name": [[file, line, text], ...]},# topic_thread whole files
    "glossary": {"entry-name": [[file, line, text], ...]},
    "policy":   [[file, line, text], ...]           # policy_lookup hit lines
  }
Empty/absent arrays serve the uniform miss shape.

Harnesses point the reader here via WRITING_ASSISTANT_GATEWAY_CMD (the
documented test seam), e.g.:
  WRITING_ASSISTANT_GATEWAY_CMD="python3 scripts/fixtures/policy-gateway-stub.py fx.json"
"""

import json
import sys


def responses(fixture):
    pin = fixture["pin"]
    commit = pin.rsplit("@", 1)[1]

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
        return None
    return tool_call


def main():
    with open(sys.argv[1], encoding="utf-8") as fh:
        tool_call = responses(json.load(fh))
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
