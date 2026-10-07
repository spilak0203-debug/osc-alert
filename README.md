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
                     → corporate actions from DART (bonus/rights issues, reductions, splits,
                       merges under way) added to market-v2.json — needs the repository secret
                       DART_API_KEY (free at opendart.fss.or.kr); skipped without it
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

The version is `version: <name>+<build>` in `app/pubspec.yaml`, e.g. `2.55.0+55`.

| Change | Name | Build |
|---|---|---|
| New feature or a visible change | minor + 1, patch 0 (2.55.0 → 2.56.0) | + 1 |
| Bug fixes only | patch + 1 (2.56.0 → 2.56.1) | + 1 |
| A redesign, or a break with old data or settings | major + 1 (→ 3.0.0) | + 1 |
| Refactoring, tests, docs | unchanged — no release | unchanged |

- The build number only goes up, by one per release. It is what the apps compare (release tag
  `v<build>`), and it continues the earlier numbering (`v1`–`v54`, whose names were 2.1–2.54), so
  installed apps, the Java one included, update over it with settings and favourites kept.
- The name is shown without a zero patch: 2.55.0 is "2.55", 2.55.1 is "2.55.1".
- `app/assets/changelog.json` lists the user-visible changes per version, newest first. Changes
  not released yet go in a top entry with `"version": null`; the release gives that entry the new
  name in the same commit that raises the version, and it becomes the release notes.
  `test/version_test.dart` checks that the newest named entry matches `pubspec.yaml`.

A push to `main` that touches `app/` releases when its build number has no release yet: the
tests, the APK and the Windows installer (Inno Setup), then release `v<build>` with both. Any other
push to `main` only runs the analyzer and the tests. The `market-data` pre-release holds the daily
snapshot and never counts as the latest release.

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

The Android keys live outside the repository, in `~/.secrets/osc-alert/` (`android-release.jks` and
`android-release.properties` for the current key, `old-release.*` for the original one). A
properties file has `storeFile` (relative to the file itself), `storePassword`, `keyAlias` and
`keyPassword`. The release build reads `OSC_SIGNING_PROPERTIES`, or
`~/.secrets/osc-alert/android-release.properties` by default, and fails without it; debug builds,
`flutter analyze` and `flutter test` need no key.

The original key was committed to this public repository, so it is leaked. Updates must still
install over the existing app, so `app/android/sign-release.sh` signs the release APK with the new
key plus a v3 rotation lineage (`app/android/signing-lineage.bin`, public data) that links it to the
old key. In the lineage the old key keeps installed data and permission rights and has no rollback,
shared UID or auth rights: without the permission right the update fails with
`INSTALL_FAILED_DUPLICATE_PERMISSION`, because the app declares a signature permission (AndroidX's
`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`); without rollback, a device that has the rotated app
refuses updates signed only with the old key. The old key also signs the v2 block for Android 8,
which has no rotation support; Android 9 and newer see the new key. The script then
verifies the certificate at API 26 (old), 28 and 33 (new).

```bash
cd app
OSC_SIGNING_PROPERTIES=~/.secrets/osc-alert/android-release.properties flutter build apk --release
APKSIGNER=<sdk>/build-tools/36.0.0/apksigner bash android/sign-release.sh \
  build/app/outputs/flutter-apk/app-release.apk ../osc-alert.apk \
  ~/.secrets/osc-alert/android-release.properties ~/.secrets/osc-alert/old-release.properties \
  android/signing-lineage.bin
```

The release workflow needs four secrets, with no fallback: `ANDROID_KEYSTORE_BASE64` and
`ANDROID_KEY_PROPERTIES` (new key), `ANDROID_OLD_KEYSTORE_BASE64` and `ANDROID_OLD_KEY_PROPERTIES`
(old key), each the content of the matching file above (the keystores base64-encoded). They exist
only as secrets of the GitHub Environment `release` (Settings → Environments), not as repository
secrets. Set the environment up with a required reviewer and, under deployment branches, *Selected
branches* → `main` only. The `android` job of the release workflow uses that environment, so it
waits after the tests of a new build number: open the run in the Actions tab, press **Review
deployments** and approve `release`; the signing starts only then. If the new key is lost, the app
can only be updated after uninstalling and reinstalling it once.

### Keeping keys out of the repository

`tool/check-secrets.sh` fails when a tracked file looks like a signing key: a key file extension
(`.jks`, `.keystore`, `.jceks`, `.bks`, `.p12`, `.pfx`, `.pem`, `.key`, `.p8`), a PEM private key block, JKS or JCEKS keystore
magic bytes, or a `storePassword`/`keyPassword` line that has a value. It prints the file and the
reason, never the matching text. It runs in two places:

- **pre-commit hook**: `.githooks/pre-commit` checks the staged files (`tool/check-secrets.sh
  --staged`). Enable it once per clone:

  ```bash
  git config core.hooksPath .githooks
  ```

- **`secret-check` workflow**: on every push and pull request, with no path filter, it runs
  `bash tool/check-secrets.sh` over all tracked files. The hook can be skipped or never enabled;
  this check cannot.

## Notes

- Scheduled GitHub runs can start late, so alerts usually arrive between 16:00 and 16:30 KST.
- Uses unofficial Naver endpoints. If they change or block access, `daily-signal` fails and shows
  red in the Actions tab.
- This is a signal notifier, not financial advice.
