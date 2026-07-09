#!/usr/bin/env sh
# release-strip.sh — mechanically strip the BMAD footprint for an OSS release.
#
# BMAD's footprint is confined to EXACTLY three path classes (SPEC NFR8):
#     _bmad/
#     _bmad-output/
#     .claude/skills/bmad-*
# and nothing hand-written ever lives in them, so stripping is a pure removal
# with no judgment calls. This script removes exactly those and nothing else;
# everything else — specs/, skills/, scripts/, config/, .claude-plugin/,
# README.md — is left intact, leaving a complete, functioning plugin.
#
# Usage:
#   release-strip.sh [--dry-run] [--root DIR]
#     --dry-run   list what would be removed; remove nothing
#     --root DIR  operate on DIR (default: git top-level, else cwd)
#
# If git history itself must be excluded from a public release, publish via a
# fresh public repo or a squashed export — this script strips the working tree.

set -eu

dry=0
root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1 ;;
    --root) shift; root=${1:-} ;;
    --root=*) root=${1#--root=} ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) printf 'release-strip: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$root" ]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null) || root=$(pwd)
fi
[ -d "$root" ] || { printf 'release-strip: no such directory: %s\n' "$root" >&2; exit 2; }

# Enumerate the exact removal targets (the three classes only).
targets=""
[ -e "$root/_bmad" ] && targets="$targets $root/_bmad"
[ -e "$root/_bmad-output" ] && targets="$targets $root/_bmad-output"
if [ -d "$root/.claude/skills" ]; then
  for d in "$root"/.claude/skills/bmad-*; do
    [ -e "$d" ] && targets="$targets $d"
  done
fi

if [ -z "${targets# }" ]; then
  printf 'release-strip: nothing to remove (already clean).\n'
  exit 0
fi

for t in $targets; do
  if [ "$dry" -eq 1 ]; then
    printf 'would remove: %s\n' "$t"
  else
    rm -rf "$t"
    printf 'removed: %s\n' "$t"
  fi
done
