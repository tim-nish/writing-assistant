#!/usr/bin/env sh
# check-marketplace.sh — verify the repo-as-marketplace manifest (Story 6.2):
# .claude-plugin/marketplace.json is valid JSON with name/owner/plugins, the
# single self-referential plugin entry points at this repo (source "./"), and it
# is consistent with .claude-plugin/plugin.json so `/plugin marketplace add
# <owner>/writing-assistant` + `/plugin install` resolve. POSIX shell + stdlib
# Python (json).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

MKT=".claude-plugin/marketplace.json"
PLUGIN=".claude-plugin/plugin.json"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

[ -f "$MKT" ] && ok "marketplace.json exists" || { err "marketplace.json missing"; printf '\nFAILED.\n' >&2; exit 1; }
[ -f "$PLUGIN" ] && ok "plugin.json present (marketplace target)" || err "plugin.json missing (needed by source ./)"

python3 - "$MKT" "$PLUGIN" <<'PY'
import json, re, sys
mkt = json.load(open(sys.argv[1]))
plugin = json.load(open(sys.argv[2]))

RESERVED = {"claude-plugins-official", "claude-plugins-community", "claude-community",
            "anthropic-plugins", "anthropic-marketplace"}

assert re.fullmatch(r"[a-z0-9][a-z0-9-]*", mkt.get("name", "")), f'name={mkt.get("name")!r}'
assert mkt["name"] not in RESERVED, f'marketplace name {mkt["name"]!r} is reserved'
assert isinstance(mkt.get("owner"), dict) and mkt["owner"].get("name"), "owner.name missing"
plugins = mkt.get("plugins")
assert isinstance(plugins, list) and plugins, "plugins must be a non-empty array"

entry = next((p for p in plugins if p.get("name") == "writing-assistant"), None)
assert entry is not None, "no plugin entry named writing-assistant"
src = entry.get("source")
assert src == "./", f'self-referential source must be "./", got {src!r}'
assert isinstance(entry.get("description"), str) and entry["description"].strip(), "entry description missing"
# Consistency: the entry names the same plugin the manifest declares.
assert entry["name"] == plugin.get("name"), \
    f'entry name {entry["name"]!r} != plugin.json name {plugin.get("name")!r}'
# Avoid the silent-override pitfall: don't pin version in both files.
if "version" in entry and "version" in plugin:
    assert entry["version"] == plugin["version"], "version pinned in both and disagrees"
assert "tim-nish.dev" not in json.dumps(mkt), "site-identity proxy leaked into marketplace.json"
print("marketplace-consistency-ok")
PY
if [ $? -eq 0 ]; then
  ok "valid marketplace with a self-referential (source ./) writing-assistant entry, consistent with plugin.json"
else
  err "marketplace.json failed validation/consistency"
fi

# source "./" must resolve to a directory carrying the plugin manifest.
[ -f ".claude-plugin/plugin.json" ] && ok "source ./ resolves to a plugin (.claude-plugin/plugin.json)" \
  || err "source ./ does not resolve to a plugin manifest"

if [ "$fail" -eq 0 ]; then
  printf '\nAll marketplace checks passed.\n'; exit 0
else
  printf '\nmarketplace checks FAILED.\n' >&2; exit 1
fi
