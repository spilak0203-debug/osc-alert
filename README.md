# osc-alert

Scans every KOSPI and KOSDAQ stock after the close and notifies your phone when **three
oscillators match** — all golden-cross (or all dead-cross) together. The app, "매매 시그널 알림",
runs on Android and Windows from one Flutter code base (`app/`). It lets you tune the rule, shows a
dashboard and charts for every stock, and updates itself from this repository's releases.

| | Golden confluence (buy) | Dead confluence (sell) |
|---|---|---|
| Stochastic, Slow 5-3-3 | %K crosses above %D | %K crosses below %D |
| RSI(14), signal(9) | RSI crosses above its signal line | RSI crosses below its signal line |
| CCI(20) | crosses above -100 | crosses below +100 |

These are the app's defaults: any crossing of the two lines counts. In settings you can add a band
condition per indicator (e.g. the stochastic cross only counts after %K was below 20 / above 80,
RSI after 30 / 70 — the rule the scan's `signals/latest.json` still uses), change the levels,
switch to fast stochastic, allow the three crossings to be spread over up to 4 days, and add alerts
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
Every 30 minutes     The app downloads market-v2.json, evaluates the rule with your settings,
                     and notifies when the signal date changes. Optional repeat at 08:00–09:00.
                     (Android: a WorkManager job. Windows: the app keeps running in the tray.)
```

Six days of indicator values are enough to evaluate any crossing, band condition and match window
(0–4 days), so changing settings never needs a new scan. `signal/rule.py` is the reference;
`app/lib/core/rule.dart` and `indicators.dart` are ports, and Dart tests check them against fixtures
produced by Python (`tests/make_fixtures.py`).

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
  window, zone count, indicator rules, per-kind test notifications, font size, update check and the
  version history.
- **Windows**: the same screens with a navigation rail on the left and the selected stock's charts
  in a pane on the right. Mouse wheel zooms a chart, dragging scrolls it, hovering reads a day, a
  double click resets; right click copies a stock's code. Closing the window keeps the app in the
  tray (checking every 30 minutes); it can also start with Windows. Tapping a notification on either
  platform opens the dashboard at that signal group.

Prices shown live come from Naver quote endpoints; pull down to refresh.

## Setup

1. **Workflow permissions**: Settings → Actions → General → Workflow permissions → *Read and write*.
2. **Install the app**: from the latest release, `osc-alert.apk` on Android (allow "install unknown
   apps" once) or `osc-alert-setup.exe` on Windows (installs per user, no administrator rights).
   Later versions install from inside the app.
3. **First signal**: Actions → `daily-signal` → Run workflow, then pull to refresh in the app.

If notifications arrive late or not at all, disable **battery optimization** for the app.

## Releases

Every push to `main` that touches `app/` runs the tests, builds the APK and the Windows installer
(Inno Setup) and publishes release `v<run number>` (version 2.<run number>) with both. The app
compares that number with its own build number. The numbering continues the earlier Java app's,
whose updater installs the Flutter build over it; settings and favourites carry over. The `market-data`
pre-release holds the daily snapshot and never counts as the latest release.

## Running locally

```bash
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python signal/scan.py --limit 50 --dry-run
.venv\Scripts\python -m unittest discover -s tests -v
```

The app needs Flutter (stable) — plus the Android SDK for the APK or Visual Studio's C++ tools for
Windows:

```bash
cd app
flutter test
flutter run -d windows
```

On work branches `flutter-check` runs the tests, then a scripted tour of every screen on an Android
emulator and on Windows (`--smoke=<dir>`) and uploads the screenshots.

## Signing key

`app/android/app/release.keystore` signs every build with the **same key** so updates install over the
existing app (password `oscalert`). Since this repository is public, anyone can sign with it. To use
your own key, add the repository secrets `ANDROID_KEYSTORE_B64` (base64 of the keystore) and
`ANDROID_KEYSTORE_PASSWORD`; the workflow prefers them. Changing the key requires uninstalling and
reinstalling the app once.

## Notes

- Scheduled GitHub runs can start late, so alerts usually arrive between 16:00 and 16:30 KST.
- Uses unofficial Naver endpoints. If they change or block access, `daily-signal` fails and shows
  red in the Actions tab.
- This is a signal notifier, not financial advice.
