#!/usr/bin/env bash
# Fails when a signing key or a password is about to be committed. This is a public repository and
# the original release key was once committed to it, so the check runs in two places:
#
#   tool/check-secrets.sh --staged   only the staged files (pre-commit hook, .githooks/pre-commit)
#   tool/check-secrets.sh            every tracked file (CI, .github/workflows/secret-check.yml)
#
# Files are read from the index, not the working tree: what is checked is what gets committed.
# A violation prints the file and the reason (never the matching text, CI logs are public) and
# the exit status is 1.
#
# Rules:
#   a. key file extensions: .jks .keystore .p12 .pfx .pem .key
#   b. a PEM private key block in the content
#   c. the Java keystore magic bytes FE ED FE ED at the start of any file, whatever its name
#   d. a storePassword / keyPassword line (name immediately followed by =) that has a value: the
#      character after = is not whitespace, %, $ or ". The checked-in code only writes the name
#      without = (build.gradle.kts, README), greps for it as `^(name)=` (android.yml), or builds the
#      line from a printf format / shell variable (flutter-check.yml), so none of it matches.
# Binary files (a NUL byte) only get rules a and c; their content is not searched.
#
# Exceptions: none. app/android/signing-lineage.bin is public data, but it is binary and does not
# start with the keystore magic, so it passes without an exemption. Add one here, with the reason,
# only if a file really cannot pass.
set -euo pipefail

mode=all
case "${1:-}" in
  '') ;;
  --staged) mode=staged ;;
  *) echo "usage: $0 [--staged]" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "usage: $0 [--staged]" >&2; exit 2; }

cd "$(git rev-parse --show-toplevel)"

# Written so that this file does not match its own patterns.
pem_re='-----BEGIN [A-Z ]*PRIVATE KEY-----'
pass_re='(storePassword|keyPassword)=[^[:space:]%$"]'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

bad=0
fail() { echo "$1: $2"; bad=1; }

check() {
  local f=$1
  case "${f,,}" in
    *.jks|*.keystore|*.p12|*.pfx|*.pem|*.key) fail "$f" "key file extension" ;;
  esac
  if ! git show ":$f" > "$tmp" 2>/dev/null; then
    echo "check-secrets: skipped $f (not a regular file in the index)" >&2
    return
  fi
  if [ "$(head -c 4 "$tmp" | od -An -tx1 | tr -d ' \n')" = feedfeed ]; then
    fail "$f" "Java keystore (FE ED FE ED magic)"
  fi
  # -I: a file with a NUL byte counts as binary and never matches.
  if LC_ALL=C grep -Iq '' "$tmp"; then
    LC_ALL=C grep -Eq -- "$pem_re" "$tmp" && fail "$f" "PEM private key block"
    n=$(LC_ALL=C grep -En -- "$pass_re" "$tmp" | cut -d: -f1 | paste -sd, -) || true
    [ -z "$n" ] || fail "$f" "storePassword/keyPassword with a value (line $n)"
  fi
}

if [ "$mode" = staged ]; then
  list=(git diff --cached --name-only --diff-filter=ACMR -z)
else
  list=(git ls-files -z)
fi
while IFS= read -r -d '' f; do
  check "$f"
done < <("${list[@]}")

if [ "$bad" -ne 0 ]; then
  echo "check-secrets: signing keys and passwords belong in ~/.secrets/osc-alert and the GitHub Environment 'release', not in the repository." >&2
  exit 1
fi
