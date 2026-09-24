# osc-alert

Scans every KOSPI and KOSDAQ stock after the close and notifies your phone when **three
oscillators match** — all golden-cross (or all dead-cross) together. The Android app,
"매매 시그널 알림", lets you tune the rule, shows a dashboard and charts for every stock, and
updates itself from this repository's releases.

| | Golden confluence (buy) | Dead confluence (sell) |
|---|---|---|
| Stochastic, Slow 5-3-3 | %K crosses above %D, previous %K < 20 | %K crosses below %D, previous %K > 80 |
| RSI(14), signal(9) | RSI crosses above signal, previous RSI < 30 | RSI crosses below signal, previous RSI > 70 |
| CCI(20) | crosses above -100 | crosses below +100 |

These are the defaults. In the app you can switch to fast stochastic, turn each band condition
off or change its levels, allow the three crossings to be spread over up to 4 days, and add alerts
for 2-of-3 matches and for entering or leaving oversold/overbought zones.

## How it works

```
Weekdays 15:50 KST   GitHub Actions runs signal/scan.py
                     → ~200 trading days of Naver daily bars for every stock
                     → market-v2.json: each stock's indicators for the last 6 trading days
                       (uploaded to the `market-data` pre-release; not committed)
                     → market.json: the same, last 2 days only, for app 2.9 and older
                     → signals/latest.json: default-rule confluences (committed, with history)
                     Runs again at 16:40 in case the first run is late.
Every 30 minutes     The app downloads market.json, evaluates the rule with your settings,
                     and notifies when the signal date changes. Optional repeat at 08:00–09:00.
```

Six days of indicator values are enough to evaluate any crossing, band condition and match window
(0–4 days), so changing settings never needs a new scan. `signal/rule.py` is the reference; `Rule.java` and
`Indicators.java` are ports, and JVM tests check them against fixtures produced by Python
(`tests/make_java_fixtures.py`).

If the scan runs before 15:40 KST, today's bar is dropped. On market holidays the signal date
doesn't change, so nothing is sent.

## App

- **Top bar**: the close the signals are from and the market session (open, closed, holiday — on
  holidays the latest trading day is shown), plus a refresh button.
- **요약 (Dashboard)**: KOSPI and KOSDAQ charts, a tally per signal kind (3- and 2-indicator
  matches, oversold/overbought entry and exit), and the stocks of each kind.
- **종목 (Stocks)**: every stock, searchable.
- Tap any stock to expand: per-indicator state, candles with 5/20/60/120-day moving averages,
  and stochastic, RSI and CCI panels (each can be toggled). Matching spans are shaded, crosses are
  dotted, band crossings are ringed. Pinch to zoom, drag sideways to scroll, tap or long-press to
  read a day, double tap to reset. Long press a row to copy its code (or name).
- **설정 (Settings)**: which alerts to send, sound/vibration/both/silent, pre-market repeat, match
  window, zone count, indicator rules, per-kind test notifications, font size, and update check.

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
