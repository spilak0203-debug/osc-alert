#!/usr/bin/env bash
# Runs the in-app smoke tour on a running emulator and pulls its screenshots.
#   bash app/tool/android_smoke.sh <apk> <output dir>
# Installs over whatever is already there.
set -u
APK=$1
OUT=$2
PKG=kr.personal.oscalert
DIR=/sdcard/Android/data/$PKG/files/smoke
mkdir -p "$OUT"

adb install -r "$APK" || adb install -r -d "$APK" || exit 1
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb shell rm -rf "$DIR"
adb logcat -c
adb shell am force-stop $PKG
adb shell am start -n $PKG/.MainActivity --ez smoke true

for i in $(seq 1 180); do
  if adb shell ls "$DIR/done" >/dev/null 2>&1; then break; fi
  sleep 3
done
sleep 2
adb shell screencap -p /sdcard/last.png && adb pull /sdcard/last.png "$OUT/z-device-last.png" >/dev/null
adb pull "$DIR/." "$OUT/" >/dev/null
adb logcat -d > "$OUT/logcat.txt"
ls -la "$OUT"
if grep -E "FATAL EXCEPTION|AndroidRuntime: Process: $PKG" "$OUT/logcat.txt"; then exit 1; fi
test -f "$OUT/done" || { echo "tour did not finish"; exit 1; }
if [ -f "$OUT/error.txt" ]; then cat "$OUT/error.txt"; exit 1; fi
