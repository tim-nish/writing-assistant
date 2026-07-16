#!/usr/bin/env sh
# check-generic-engine.sh — prove no owner identity is baked into shipped
# skill/command/template files (CAP-6, Story 1.4). POSIX shell only.
#
# Scope: the plugin's shipped surface — skills/ and commands/ (SKILL.md,
# framework templates, prompts). Deliberately EXCLUDED: config/ (the legitimate
# home for identity) and specs/ (adopted design contracts that reference the
# site by name). Helper scripts under scripts/ are tests/tools, not shipped
# skill content, and may name the proxy as a guard string.
#
# Two sweeps:
#   A. static  — the documented proxy literal `tim-nish.dev` must not appear.
#   B. derived — every concrete identity value in the resolved config (site
#                host, site name, owner name, focus areas) must not appear;
#                treats `tim-nish.dev` as a proxy and catches other literals a
#                single grep would miss. Skipped-with-note if no config resolves.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# Shipped skill/command/template files tracked in git (never scan config/,
# specs/, scripts/, or untracked/ignored paths). Written once for reuse.
git ls-files -- skills commands 2>/dev/null | grep -vE '(^|/)\.gitkeep$' > "$work/surface" || true

# grep_absent LITERAL LABEL — fail if LITERAL appears in any surface file.
grep_absent() {
  literal=$1; label=$2
  if [ ! -s "$work/surface" ]; then
    ok "$label — no shipped skill/command files yet (vacuously clean)"
    return
  fi
  if hits=$(xargs -r grep -Fl -- "$literal" < "$work/surface" 2>/dev/null) && [ -n "$hits" ]; then
    err "$label — '$literal' found in: $(printf '%s' "$hits" | tr '\n' ' ')"
  else
    ok "$label — '$literal' absent from shipped skill/command files"
  fi
}

# A. Static proxy sweep (the AC's literal).
grep_absent "tim-nish.dev" "static proxy"

# A2. Publication boundary (#291, repo-onboarding C8): the shipped surface
# describes the policy-seam mechanism generically — the owner hub's name and
# its internal layout never appear; the real pointer lives only in generated
# machine-global config.
grep_absent "product-lab" "owner hub name"
grep_absent "q_a/" "hub-layout detail (history/staging paths)"

# B. Config-derived sweep.
if python3 scripts/resolve-user-config.py resolved > "$work/cfg.json" 2>/dev/null; then
  python3 - "$work/cfg.json" > "$work/vals" <<'PY'
import json, re, sys
c = json.load(open(sys.argv[1]))
o = c.get("owner", {})
site = o.get("site_url")
out = []
for key in ("site_url", "site_name", "name", "focus_areas"):
    v = o.get(key)
    if not v:
        continue
    if key == "site_url":
        v = re.sub(r"^https?://", "", v).rstrip("/")  # compare on the bare host
    out.append(v)
print("\n".join(dict.fromkeys(out)))  # de-dupe, preserve order
PY
  if [ ! -s "$work/vals" ]; then
    ok "config-derived sweep — resolved config carried no identity literals"
  else
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      grep_absent "$v" "config-derived ($v)"
    done < "$work/vals"
  fi
else
  ok "config-derived sweep — skipped (no user-config resolved in this environment)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll generic-engine checks passed.\n'; exit 0
else
  printf '\ngeneric-engine checks FAILED.\n' >&2; exit 1
fi
