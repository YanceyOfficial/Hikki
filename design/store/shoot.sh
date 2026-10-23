#!/bin/bash
# Screenshots of Hikki on a simulator, over the demo workspace (demo-workspace.py).
#
#   design/store/shoot.sh <simulator udid> <out.png> [--display=<id>] [--dark] [--landscape] [HIKKI_X=value …]
#
# Installs the app (APP, default: the newest Debug-iphonesimulator build in DerivedData), writes a fresh workspace,
# launches once so it imports the page files, then again with the HIKKI_* hooks given (HIKKI_DEBUG_NAV=<page id>,
# HIKKI_OPEN_PAGE_ACTIONS=1, …), waits (WAIT seconds, default 14) and saves the screen. --display picks one of an
# iPhone Duo's screens (`xcrun simctl io <udid> enumerate`: the folded outer screen is 1398 wide, the inner 2007).
# The status bar reads 9:41 with full bars, as Apple's own screenshots do. --landscape (an iPad, which Hikki lays out
# on its side) takes the picture through the StoreScreenshot UI test instead, which can turn the simulator; it builds
# into DERIVED (default: Derived/StoreShots) — run `tuist generate` first.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
sim=$1 out=$2
shift 2
display=() appearance=light hooks=() landscape= pairs=
for arg in "$@"; do
  case $arg in
    --display=*) display=("$arg") ;;
    --dark) appearance=dark ;;
    --landscape) landscape=1 ;;
    *) hooks+=("SIMCTL_CHILD_$arg") pairs=${pairs:+$pairs|}$arg ;;
  esac
done
app=${APP:-$(ls -dt ~/Library/Developer/Xcode/DerivedData/Hikki-*/Build/Products/Debug-iphonesimulator/Hikki.app | head -1)}
bundle=app.yancey.hikki
data=$(mktemp -d "${TMPDIR:-/tmp}/hikki-shot.XXXXXX")
python3 "$here/demo-workspace.py" "$data" >/dev/null

xcrun simctl bootstatus "$sim" -b >/dev/null
xcrun simctl status_bar "$sim" override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 \
  --cellularBars 4 >/dev/null 2>&1 || true
xcrun simctl ui "$sim" appearance "$appearance"
if [ -n "$landscape" ]; then
  cd "$here/../.."
  TEST_RUNNER_HIKKI_SHOT="$out" TEST_RUNNER_HIKKI_SHOT_DATA="$data" TEST_RUNNER_HIKKI_SHOT_ENV="$pairs" \
    TEST_RUNNER_HIKKI_SHOT_WAIT="${WAIT:-14}" xcodebuild test -workspace Hikki.xcworkspace -scheme Hikki \
    -destination "id=$sim" -derivedDataPath "${DERIVED:-Derived/StoreShots}" \
    -only-testing:HikkiUITests/StoreScreenshot >"${TMPDIR:-/tmp}/hikki-shot.log" 2>&1
  echo "$out"
  exit 0
fi
xcrun simctl install "$sim" "$app"
base=(SIMCTL_CHILD_HIKKI_DATA_DIR="$data" SIMCTL_CHILD_HIKKI_WORKSPACE=Personal SIMCTL_CHILD_HIKKI_FRESH_TABS=1)
# The first launch imports the page files; the hooks need the pages to be there.
env "${base[@]}" xcrun simctl launch --terminate-running-process "$sim" "$bundle" >/dev/null
sleep 8
env "${base[@]}" ${hooks[@]+"${hooks[@]}"} xcrun simctl launch --terminate-running-process "$sim" "$bundle" >/dev/null
sleep "${WAIT:-14}"
xcrun simctl io "$sim" screenshot ${display[@]+"${display[@]}"} "$out" >/dev/null 2>&1
echo "$out"
