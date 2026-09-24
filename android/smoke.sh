#!/usr/bin/env bash
# Smoke test on a running emulator: install, open each tab, expand a stock, screenshot.
#   bash android/smoke.sh <apk> <output dir>
set -u
APK=$1
OUT=$2
PKG=kr.personal.oscalert
mkdir -p "$OUT"

shot() { dismiss_anr; adb exec-out screencap -p > "$OUT/$1.png"; }

# Center of the first on-screen node whose text or description matches $1.
# The emulator's own launcher sometimes shows "isn't responding"; answer "Wait" and move on.
dismiss_anr() {
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml "$OUT/ui.xml" >/dev/null 2>&1
  if grep -q "isn't responding" "$OUT/ui.xml" 2>/dev/null; then
    local b
    b=$(python3 -c "
import re, xml.etree.ElementTree as ET
for n in ET.parse('$OUT/ui.xml').iter('node'):
    if (n.get('text') or '') == 'Wait':
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', n.get('bounds'))); print((x1+x2)//2, (y1+y2)//2); break
")
    [ -n "$b" ] && adb shell input tap $b && sleep 2
  fi
}

tap_text() {
  dismiss_anr
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
  adb pull /sdcard/ui.xml "$OUT/ui.xml" >/dev/null 2>&1
  local b
  b=$(python3 - "$1" "$OUT/ui.xml" <<'EOF'
import re, sys, xml.etree.ElementTree as ET
want, path = sys.argv[1], sys.argv[2]
nodes = list(ET.parse(path).iter('node'))
label = lambda n: [(n.get('text') or '').strip(), (n.get('content-desc') or '').strip()]
# Exact match first (tab titles), then substring.
hit = next((n for n in nodes if want in label(n)), None) \
    or next((n for n in nodes if any(want in s for s in label(n))), None)
if hit is not None:
    x1, y1, x2, y2 = map(int, re.findall(r'\d+', hit.get('bounds')))
    print((x1 + x2) // 2, (y1 + y2) // 2)
EOF
)
  if [ -z "$b" ]; then echo "not found: $1"; return 1; fi
  adb shell input tap $b
}

crashed() {
  adb logcat -d | grep -E "FATAL EXCEPTION|AndroidRuntime: Process: $PKG" && return 0
  return 1
}

adb install -r "$APK"
adb shell pm grant $PKG android.permission.POST_NOTIFICATIONS || true
adb logcat -c
sleep 30
adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1
adb shell am start -n $PKG/.MainActivity
sleep 20
shot 1-summary
adb shell input swipe 540 1800 540 700 600 && sleep 2
shot 1b-summary-lower
tap_text "제이앤티씨" && sleep 12
shot 1c-summary-expanded
adb shell input swipe 540 1800 540 1000 800 && sleep 2
shot 1d-summary-oscillators

tap_text "종목" && sleep 25
shot 2-stocks
tap_text "즐겨찾기" && sleep 3
shot 2b-favorite
tap_text "삼성전자" && sleep 12
shot 3-stock-expanded
# Vertical drags that start on a chart must scroll the list.
adb shell input swipe 540 1700 540 1100 800 && sleep 2
shot 4-stock-charts
adb shell input swipe 540 1700 540 1100 800 && sleep 2
shot 4b-stock-oscillators
# A sideways drag on a chart moves the crosshair.
adb shell input swipe 200 1400 700 1400 800 && sleep 1
shot 4c-crosshair

tap_text "설정" && sleep 3
shot 5-settings
adb shell input swipe 540 1800 540 900 400 && sleep 1
shot 5b-settings-sound
tap_text "테스트 알림" && sleep 3
adb shell cmd statusbar expand-notifications && sleep 2
shot 6-notification
adb shell cmd statusbar collapse && sleep 1
adb shell input swipe 540 1800 540 600 400 && sleep 1
shot 5c-settings-indicators
adb shell input swipe 540 1800 540 600 400 && sleep 1
adb shell input swipe 540 1800 540 600 400 && sleep 1
shot 5d-settings-bottom

tap_text "가+" && sleep 3
tap_text "가+" && sleep 3
shot 7-larger-font

adb logcat -d > "$OUT/logcat.txt"
if crashed; then echo "APP CRASHED"; exit 1; fi
echo "no crash"
