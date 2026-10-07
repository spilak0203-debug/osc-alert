#!/usr/bin/env bash
# Signs a release APK with the new key plus the old key's rotation lineage (APK Signature Scheme
# v3), so the app updates over installs signed with the old key, then checks which certificate
# Android sees at each API level. Used by CI and by hand.
#
#   sign-release.sh <in.apk> <out.apk> <new-key.properties> <old-key.properties> <lineage.bin>
#
# The properties files hold storeFile (relative to the file itself), storePassword, keyAlias and
# keyPassword. Passwords go to apksigner through environment variables only.
# apksigner: $APKSIGNER, or the highest build-tools under $ANDROID_HOME (33 or newer).
set -euo pipefail

# Public certificate digests. The old key was leaked, so it only signs for Android 8 (API 26-27),
# which does not know about rotation; Android 9 and newer see the new key.
OLD_SHA256=981c5916850f1a852f1f410ce5c337160165a53b8765849e143a24baca5d726f
NEW_SHA256=e84d4c75c359a806cf72cb335b5fe410293cb72516818d803d35319825efb738

if [ $# -ne 5 ]; then
  echo "usage: $0 <in.apk> <out.apk> <new-key.properties> <old-key.properties> <lineage.bin>" >&2
  exit 2
fi
in_apk=$1 out_apk=$2 new_props=$3 old_props=$4 lineage=$5
for f in "$in_apk" "$new_props" "$old_props" "$lineage"; do
  [ -f "$f" ] || { echo "sign-release: file not found: $f" >&2; exit 1; }
done

apksigner=${APKSIGNER:-}
if [ -z "$apksigner" ]; then
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
  [ -n "$sdk" ] || { echo "sign-release: set APKSIGNER or ANDROID_HOME" >&2; exit 1; }
  # Release candidates (36.1.0-rc1) are skipped.
  latest=$(ls "$sdk/build-tools" | grep -v -- '-' | sort -V | tail -n 1)
  apksigner=$sdk/build-tools/$latest/apksigner
  [ -e "$apksigner" ] || apksigner=$apksigner.bat
fi
[ -e "$apksigner" ] || { echo "sign-release: apksigner not found: $apksigner" >&2; exit 1; }
# The build-tools folder name is the version; an unusual location is left to apksigner itself,
# which rejects --rotation-min-sdk-version when it is too old.
major=$(basename "$(dirname "$apksigner")" | cut -d. -f1)
if [[ "$major" =~ ^[0-9]+$ && "$major" -lt 33 ]]; then
  echo "sign-release: apksigner from build-tools 33 or newer is required (found $major)" >&2
  exit 1
fi

# Reads one key from a properties file.
prop() { sed -n "s/^$2=//p" "$1" | tr -d '\r' | head -n 1; }
# Resolves storeFile against the properties file's folder.
store() { echo "$(dirname "$1")/$(prop "$1" storeFile)"; }

export OSC_NEW_STORE_PASS=$(prop "$new_props" storePassword)
export OSC_NEW_KEY_PASS=$(prop "$new_props" keyPassword)
export OSC_OLD_STORE_PASS=$(prop "$old_props" storePassword)
export OSC_OLD_KEY_PASS=$(prop "$old_props" keyPassword)
new_store=$(store "$new_props")
old_store=$(store "$old_props")
for f in "$new_store" "$old_store"; do
  [ -f "$f" ] || { echo "sign-release: keystore not found: $f" >&2; exit 1; }
done

# --rotation-min-sdk-version 28: without it the rotation is ignored before Android 13.
"$apksigner" sign \
  --ks "$old_store" --ks-key-alias "$(prop "$old_props" keyAlias)" \
  --ks-pass env:OSC_OLD_STORE_PASS --key-pass env:OSC_OLD_KEY_PASS \
  --next-signer \
  --ks "$new_store" --ks-key-alias "$(prop "$new_props" keyAlias)" \
  --ks-pass env:OSC_NEW_STORE_PASS --key-pass env:OSC_NEW_KEY_PASS \
  --lineage "$lineage" --rotation-min-sdk-version 28 \
  --out "$out_apk" "$in_apk"

# Checks the certificate Android sees at one API level.
check() {
  local sdk=$1 want=$2 out got
  # The output only holds public certificate data, so it is shown when the check fails.
  if ! out=$("$apksigner" verify --print-certs --min-sdk-version "$sdk" --max-sdk-version "$sdk" "$out_apk" 2>&1); then
    printf 'sign-release: apksigner verify failed at API %s:\n%s\n' "$sdk" "$out" >&2
    exit 1
  fi
  got=$(printf '%s\n' "$out" | tr -d '\r' | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1)
  if [ "$got" != "$want" ]; then
    printf 'sign-release: API %s sees %s, expected %s\napksigner %s:\n%s\n' \
      "$sdk" "${got:-no signer}" "$want" "$("$apksigner" --version 2>&1)" "$out" >&2
    exit 1
  fi
  echo "API $sdk: $got"
}
check 26 "$OLD_SHA256"
check 28 "$NEW_SHA256"
check 33 "$NEW_SHA256"
# One signer only: the old key alone for v2, the new key with the lineage for v3.
signers=$("$apksigner" verify -v "$out_apk" | tr -d '\r' | sed -n 's/^Number of signers: //p')
if [ "$signers" != 1 ]; then
  echo "sign-release: expected 1 signer, found ${signers:-none}" >&2
  exit 1
fi
echo "signed: $out_apk"
