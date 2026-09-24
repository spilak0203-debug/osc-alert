# osc-alert

Scans every KOSPI and KOSDAQ stock after the close and sends a phone notification when **three
oscillators cross on the same day**. A test pins the signal dates on real price history.

| | Golden confluence (buy) | Dead confluence (sell) |
|---|---|---|
| Stochastic, Slow 5-3-3 | %K crosses above %D, previous %K < 20 | %K crosses below %D, previous %K > 80 |
| RSI(14), signal(9) | RSI crosses above signal, previous RSI < 30 | RSI crosses below signal, previous RSI > 70 |
| CCI(20) | crosses above -100 | crosses below +100 |

All three must fire **on the same day**. By default, buy alerts only include stocks with a 20-day
average trading value of at least KRW 500M (can be turned off in the app).

## How it works

```
Weekdays 15:50 KST   GitHub Actions runs signal/scan.py
                     → ~200 trading days of Naver daily bars for every stock → confluence check
                     → commits signals/latest.json (runs again at 16:40; no commit if unchanged)
Every 30 minutes     The Android app fetches latest.json → notifies when the signal date (asof) changes
```

If the scan runs before 15:40 KST, today's bar is dropped so signals never come from an unfinished bar.
On market holidays the signal date doesn't change, so no notification is sent.

## Setup

1. **Workflow permissions**: Settings → Actions → General → Workflow permissions → *Read and write*
   (the scan commits the signal file).
2. **Install the app**: Actions → `android` → download the `osc-alert-apk` artifact, unzip, and install
   the APK on the phone. The signal URL for this repository is built in.
3. **First signal**: Actions → `daily-signal` → Run workflow, then tap "지금 확인" (check now) in the app.

If notifications arrive late or not at all, disable **battery optimization** for the app. Android can
defer background work.

## Running locally

```bash
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python signal/scan.py --limit 50 --dry-run
.venv\Scripts\python -m unittest discover -s tests -v
```

## Signing key

`android/app/release.keystore` signs every build with the **same key** so updates install over the
existing app (password `oscalert`). Since this repository is public, anyone can sign with it. To use
your own key, add the repository secrets `ANDROID_KEYSTORE_B64` (base64 of the keystore) and
`ANDROID_KEYSTORE_PASSWORD`; the workflow prefers them. Changing the key requires uninstalling and
reinstalling the app once.

## Notes

- Scheduled GitHub runs can start a few minutes to ~30 minutes late, so alerts usually arrive
  between 16:00 and 16:30 KST.
- Uses unofficial Naver endpoints. If the format changes or access is blocked, the `daily-signal`
  run fails and shows red in the Actions tab.
- This is a signal notifier, not financial advice.
