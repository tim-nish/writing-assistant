#!/usr/bin/env sh
# dev-link.sh — run this plugin's skills as plain local skills in a host repo,
# before any plugin.json/marketplace.json exists (Story 1.5). POSIX shell only.
#
# Two development modes, both requiring NO manifest (packaging is additive and
# these keep working after Stories 6.1/6.2 add the manifests):
#
#   A. plugin-dir : run `claude --plugin-dir <plugin>` from inside the host repo.
#                   `dev-link.sh plugin-dir-cmd` prints the exact command.
#   B. symlink    : symlink each skills/<name> into <host>/.claude/skills/<name>,
#                   which the host auto-loads with no flag and WITHOUT copying any
#                   file in. `dev-link.sh link|unlink|status <host-repo>`.
#
# Skills must reference their own bundled assets (frameworks/, review-prompts.md,
# scripts/) via ${CLAUDE_SKILL_DIR} so both modes resolve them regardless of the
# current working directory — this harness never assumes the plugin repo is cwd.
#
# The plugin root is auto-detected from this script's location (its git
# top-level); override with $DEV_LINK_PLUGIN_ROOT (used by the tests, and by
# anyone running skills from a checkout elsewhere).

set -eu

plugin_root() {
  if [ -n "${DEV_LINK_PLUGIN_ROOT:-}" ]; then
    (CDPATH= cd -- "$DEV_LINK_PLUGIN_ROOT" && pwd)
    return
  fi
  d=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  (cd "$d" && git rev-parse --show-toplevel 2>/dev/null) || (CDPATH= cd -- "$d/.." && pwd)
}

PLUGIN=$(plugin_root)

skill_dirs() {
  for d in "$PLUGIN"/skills/*/; do
    [ -d "$d" ] || continue
    printf '%s\n' "${d%/}"
  done
}

host_skills_dir() { printf '%s/.claude/skills' "$1"; }

cmd_plugin_dir_cmd() {
  printf 'claude --plugin-dir %s\n' "$PLUGIN"
}

cmd_link() {
  dest=$(host_skills_dir "$1")
  mkdir -p "$dest"
  skill_dirs | while IFS= read -r sd; do
    name=$(basename "$sd")
    link="$dest/$name"
    if [ -e "$link" ] && [ ! -L "$link" ]; then
      printf 'skip: %s exists and is not a symlink (not clobbering)\n' "$link" >&2
      continue
    fi
    rm -f "$link"
    ln -s "$sd" "$link"
    [ -f "$sd/SKILL.md" ] && note="" || note=" (no SKILL.md yet)"
    printf 'linked: %s -> %s%s\n' "$link" "$sd" "$note"
  done
}

cmd_unlink() {
  dest=$(host_skills_dir "$1")
  [ -d "$dest" ] || { printf 'nothing to unlink at %s\n' "$dest"; return 0; }
  for link in "$dest"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$PLUGIN"/skills/*) rm -f "$link"; printf 'unlinked: %s\n' "$link" ;;
    esac
  done
}

cmd_status() {
  dest=$(host_skills_dir "$1")
  skill_dirs | while IFS= read -r sd; do
    name=$(basename "$sd")
    link="$dest/$name"
    if [ -L "$link" ] && [ "$(readlink "$link")" = "$sd" ]; then
      printf 'linked   %s\n' "$name"
    else
      printf 'unlinked %s\n' "$name"
    fi
  done
}

usage() {
  cat >&2 <<'EOF'
usage:
  dev-link.sh plugin-dir-cmd        print the `claude --plugin-dir <plugin>` command
  dev-link.sh link   <host-repo>    symlink skills into <host>/.claude/skills (no copy)
  dev-link.sh unlink <host-repo>    remove only this plugin's symlinks
  dev-link.sh status <host-repo>    show per-skill link state
EOF
  exit 2
}

cmd=${1:-}
[ "$#" -gt 0 ] && shift
case "$cmd" in
  plugin-dir-cmd) cmd_plugin_dir_cmd ;;
  link)   [ "$#" -ge 1 ] || usage; cmd_link "$1" ;;
  unlink) [ "$#" -ge 1 ] || usage; cmd_unlink "$1" ;;
  status) [ "$#" -ge 1 ] || usage; cmd_status "$1" ;;
  *) usage ;;
esac
