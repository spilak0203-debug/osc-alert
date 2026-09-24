# osc-alert

Scans every KOSPI and KOSDAQ stock after the close and notifies your phone when **three
oscillators cross on the same day**. The Android app lets you tune the rule, browse every stock
with candle and oscillator charts, and updates itself from this repository's releases.

| | Golden confluence (buy) | Dead confluence (sell) |
|---|---|---|
| Stochastic, Slow 5-3-3 | %K crosses above %D, previous %K < 20 | %K crosses below %D, previous %K > 80 |
| RSI(14), signal(9) | RSI crosses above signal, previous RSI < 30 | RSI crosses below signal, previous RSI > 70 |
| CCI(20) | crosses above -100 | crosses below +100 |

These are the defaults. In the app you can switch to fast stochastic, turn each band condition
off or change its levels, and add alerts for 2-of-3 matches and for entering oversold/overbought zones.

## How it works

```
Weekdays 15:50 KST   GitHub Actions runs signal/scan.py
                     → ~200 trading days of Naver daily bars for every stock
                     → market.json: each stock's indicators on the signal day and the day before
                       (uploaded to the `market-data` pre-release; not committed)
                     → signals/latest.json: default-rule confluences (committed, with history)
                     Runs again at 16:40 in case the first run is late.
Every 30 minutes     The app downloads market.json, evaluates the rule with your settings,
                     and notifies when the signal date changes. Optional repeat at 08:00–09:00.
```

Two days of indicator values are enough to evaluate any crossing and band condition, so changing
settings never needs a new scan. `signal/rule.py` is the reference; `Rule.java` and
`Indicators.java` are ports, and JVM tests check them against fixtures produced by Python
(`tests/make_java_fixtures.py`).

If the scan runs before 15:40 KST, today's bar is dropped. On market holidays the signal date
doesn't change, so nothing is sent.

## App

- **요약 (Summary)**: stocks that signal today by kind, with price, change and volume. Tap to open
  the Naver chart.
- **종목 (Stocks)**: every stock, searchable. Tap to expand: candles with 5/20/60/120-day moving
  averages, signal markers, and stochastic, RSI and CCI panels, each of which can be toggled.
  Drag sideways on a chart to inspect a day.
- **설정 (Settings)**: which alerts to send, sound/vibration/both, pre-market repeat, indicator
  rules, a test notification, font size, and update check.
- **가− / 가+** in the top bar change the font size.

Prices shown live come from Naver quote endpoints; pull down to refresh.

## Setup

1. **Workflow permissions**: Settings → Actions → General → Workflow permissions → *Read and write*.
2. **Install the app**: download `osc-alert.apk` from the latest release and install it. Later
   versions install from inside the app (allow "install unknown apps" for it once).
3. **First signal**: Actions → `daily-signal` → Run workflow, then pull to refresh in the app.

If notifications arrive late or not at all, disable **battery optimization** for the app.

## Releases

Every push to `main` that touches `android/` builds, tests and publishes release `v<run number>`
with the APK. The app compares that number with its own version code. The `market-data`
pre-release holds the daily snapshot and never counts as the latest release.

## Running locally

```bash
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python signal/scan.py --limit 50 --dry-run
.venv\Scripts\python -m unittest discover -s tests -v
```

The Android build needs JDK 17 and the Android SDK; CI builds it with Gradle 8.9. The
`android-smoke` workflow runs the app on an emulator and saves screenshots.

## Signing key

`android/app/release.keystore` signs every build with the **same key** so updates install over the
existing app (password `oscalert`). Since this repository is public, anyone can sign with it. To use
your own key, add the repository secrets `ANDROID_KEYSTORE_B64` (base64 of the keystore) and
`ANDROID_KEYSTORE_PASSWORD`; the workflow prefers them. Changing the key requires uninstalling and
reinstalling the app once.

## Notes

- Scheduled GitHub runs can start late, so alerts usually arrive between 16:00 and 16:30 KST.
- Uses unofficial Naver endpoints. If they change or block access, `daily-signal` fails and shows
  red in the Actions tab.
- This is a signal notifier, not financial advice.
