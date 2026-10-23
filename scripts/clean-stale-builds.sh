#!/bin/sh
# Clears stale Hikki / Actovia builds off this Mac: the copies Launchpad and Spotlight list beside the installed
# apps, and the build folders they live in.
#   scripts/clean-stale-builds.sh          shows what it would do
#   scripts/clean-stale-builds.sh --yes    does it
# Kept: apps in /Applications, running apps, archives, and DerivedData whose workspace still exists and was
# built in the last $DAYS days. Simulators keep their installed apps (`xcrun simctl uninstall` for those).
set -eu

DAYS=${DAYS:-2}
APPLY=0
[ "${1:-}" = "--yes" ] && APPLY=1
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DD="$HOME/Library/Developer/Xcode/DerivedData"
NAMES='Hikki|Actovia'

run() {
  if [ $APPLY = 1 ]; then "$@"; else echo "  would: $*"; fi
}

running() { ps -axo command | grep -F "$1/" | grep -v grep >/dev/null 2>&1; }

echo "DerivedData (gone workspace, or not built in $DAYS days):"
for dir in "$DD"/Hikki-* "$DD"/ActoviaIos-* "$DD"/Actovia-*; do
  [ -d "$dir" ] || continue
  workspace=$(/usr/libexec/PlistBuddy -c 'Print WorkspacePath' "$dir/info.plist" 2>/dev/null || true)
  fresh=$(find "$dir/Build/Products" -maxdepth 2 -name '*.app' -mtime -"$DAYS" 2>/dev/null | head -1)
  if [ -n "$workspace" ] && [ -e "$workspace" ] && [ -n "$fresh" ]; then continue; fi
  if running "$dir"; then echo "  keep (running): $dir"; continue; fi
  echo "  $(du -sh "$dir" | cut -f1)  $dir  (${workspace:-no workspace})"
  run rm -rf "$dir"
done

echo "Agent and temporary build folders older than $DAYS days:"
for dir in "${TMPDIR:-/tmp}"/dd*mac /private/tmp/claude-*/*/*/scratchpad/dd*; do
  [ -d "$dir" ] || continue
  [ -n "$(find "$dir" -maxdepth 0 -mtime +"$DAYS")" ] || continue
  if running "$dir"; then echo "  keep (running): $dir"; continue; fi
  echo "  $(du -sh "$dir" | cut -f1)  $dir"
  run rm -rf "$dir"
done

echo "Launch Services (Launchpad, Spotlight, Open With) — every copy outside /Applications:"
"$LSR" -dump 2>/dev/null | sed -n 's/^path: *//p' | sed 's/ (0x[0-9a-f]*)$//' | sort -u |
  grep -E "/($NAMES)[^/]*\.app$" | grep -v '^/Applications/' | grep -v '\.xcarchive/' |
  while IFS= read -r app; do
    if [ -e "$app" ] && running "$app"; then echo "  keep (running): $app"; continue; fi
    echo "  $app"
    run "$LSR" -u "$app"
  done

if [ $APPLY = 1 ]; then
  "$LSR" -gc >/dev/null 2>&1 || true
  echo "Done. Launchpad may need a moment (or: killall Dock)."
else
  echo "Nothing changed. Run with --yes to do it."
fi
