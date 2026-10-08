#!/usr/bin/env bash
# Fails when a signing key or a password is about to be committed. This is a public repository and
# the original release key was once committed to it, so the check runs in three places:
#
#   tool/check-secrets.sh --staged          only the staged files (pre-commit hook, .githooks/pre-commit)
#   tool/check-secrets.sh --range <b> <h>   every file added or changed by a commit in b..h (CI)
#   tool/check-secrets.sh                   every tracked file (CI, .github/workflows/secret-check.yml)
#
# Files are read from the index (or, for --range, from the commit), not the working tree: what is
# checked is what gets committed. A violation prints the file and the reason (never the matching
# text, CI logs are public) and the exit status is 1. Anything that keeps the check from running
# (not a git work tree, git failing, an unreadable blob) is exit status 2, never a pass.
#
# Rules:
#   a. key file extensions: .jks .keystore .jceks .bks .p12 .pfx .pem .key .p8 .pk8
#   b. a PEM private key block in the content
#   c. magic bytes at the start of any file, whatever its name: FE ED FE ED (JKS), CE CE CE CE
#      (JCEKS), 30 82 ?? ?? 02 01 03 (PKCS12) and 30 82 ?? ?? 02 01 00 (PKCS#8 DER). The short
#      length form 30 81 ?? is covered too (an EC key in PKCS#8 is that small).
#   d. base64 text of a keystore: the encoding of the JKS / JCEKS magic or of a PKCS12 header
#   e. a storePassword / keyPassword assignment with a value, in any text file: the name directly
#      followed by =, then a value that does not start with whitespace, %, $ or a quote that is
#      closed at once. The checked-in code only writes the name without = (build.gradle.kts, README),
#      greps for it as `^(name)=` (android.yml), or builds the line from a printf format / shell
#      variable (flutter-check.yml), so none of it matches.
#   f. *.gradle / *.gradle.kts: the name followed by = or whitespace or ( and a quoted literal, or
#      by `?:` and a quoted literal later on the line (the old `findProperty(..) ?: '<literal>'`).
#      An argument such as getProperty("name") or listOf("name", ..) is not a violation.
#   g. *.properties: also `name = value`, `name: value` and `name value`, which Java properties accept.
#   h. *.yml *.yaml *.json: `name: value` and `"name": "value"`.
# Binary files (a NUL byte near the start) only get rules a and c; their content is not searched.
# Once a file counts as text, the content is searched with grep -a, so a NUL further down hides nothing.
#
# Exceptions: none. app/android/signing-lineage.bin is public data, but it is binary and does not
# start with a keystore or key magic, so it passes without an exemption. Add one here, with the
# reason, only if a file really cannot pass.
#
# Runs with bash 3.2 (macOS): no ${var,,}, mapfile or associative arrays.
set -euo pipefail

usage() { echo "usage: $0 [--staged | --range <base> <head>]" >&2; exit 2; }
die() { echo "check-secrets: $*" >&2; exit 2; }

mode=all
base=
head=
case "${1:-}" in
  '') [ $# -eq 0 ] || usage ;;
  --staged) [ $# -eq 1 ] || usage; mode=staged ;;
  --range) [ $# -eq 3 ] || usage; mode=range; base=$2; head=$3 ;;
  *) usage ;;
esac

# Not inside a work tree (or GIT_DIR is wrong): stop here instead of checking nothing.
top=$(git rev-parse --show-toplevel) || die "not inside a git work tree"
cd "$top"

# Written so that this file does not match its own patterns.
q="'"
dq='"'
names='(storePassword|keyPassword)'
pem_re='-----BEGIN [A-Z ]*PRIVATE KEY-----'
b64_re='/u3\+7Q|zs7[O]zg|MII[A-Za-z0-9+/]{3}IBAzCC'
pass_re="$names=\"?[^[:space:]%\$\"]"
# Not preceded by a quote, so the argument of getProperty("name") and listOf("name", ..) never counts.
gradle_re="(^|[^[:alnum:]_$q$dq])$names[[:space:]]*[=(]?[[:space:]]*[$q$dq][^$q$dq\$]"
gradle_re="$gradle_re|(^|[^[:alnum:]_$q$dq])$names[^#]*\\?:[[:space:]]*[$q$dq][^$q$dq\$]"
props_re="^[[:space:]]*$names([[:space:]]*[=:][[:space:]]*[^[:space:]]|[[:space:]]+[^[:space:]=:])"
yaml_re="(^|[{,[:space:]])[$q$dq]?$names[$q$dq]?[[:space:]]*:[[:space:]]*[$q$dq]?[^[:space:]\$%$q$dq{#]"

work=$(mktemp -d "${TMPDIR:-/tmp}/check-secrets.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$work"' EXIT
blob=$work/blob
list=$work/list

bad=0
fail() { printf '%s: %s\n' "$(printf '%s' "$1" | tr '\r\n' '??')" "$2"; bad=1; }

# check <label> <path> <git object that holds the content>
check() {
  local label=$1 f=$2 rev=$3 lc magic n re
  # tr instead of ${f,,}; the x keeps a trailing newline of the name.
  lc=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<<"${f}x")
  lc=${lc%x}
  case "$lc" in
    *.jks|*.keystore|*.jceks|*.bks|*.p12|*.pfx|*.pem|*.key|*.p8|*.pk8) fail "$label" "key file extension" ;;
  esac
  re=$pass_re
  case "$lc" in
    *.gradle|*.gradle.kts) re="$re|$gradle_re" ;;
    *.properties) re="$re|$props_re" ;;
    *.yml|*.yaml|*.json) re="$re|$yaml_re" ;;
  esac
  git show --no-textconv "$rev" > "$blob" 2>/dev/null || die "cannot read $label from git ($rev)"
  magic=$(od -An -tx1 -N7 "$blob")
  magic=${magic//[[:space:]]/}
  case "$magic" in
    feedfeed*) fail "$label" "Java keystore (FE ED FE ED magic)" ;;
    cececece*) fail "$label" "JCEKS keystore (CE CE CE CE magic)" ;;
    3082????020103*|3081??020103*) fail "$label" "PKCS12 keystore (30 82 .. .. 02 01 03 magic)" ;;
    3082????020100*|3081??020100*) fail "$label" "PKCS#8 private key (30 82 .. .. 02 01 00 magic)" ;;
  esac
  # -I: a NUL byte near the start makes it binary. Later NULs do not, so the searches use -a.
  if LC_ALL=C grep -Iq '' "$blob"; then
    # One grep per kind in the common case (no match); only a hit costs more.
    if LC_ALL=C grep -aEq -- "$pem_re|$b64_re" "$blob"; then
      if LC_ALL=C grep -aEq -- "$pem_re" "$blob"; then fail "$label" "PEM private key block"; fi
      if LC_ALL=C grep -aEq -- "$b64_re" "$blob"; then fail "$label" "base64 text of a keystore"; fi
    fi
    if LC_ALL=C grep -aEq -- "$re" "$blob"; then
      n=$(LC_ALL=C grep -aEn -- "$re" "$blob" | cut -d: -f1 | paste -sd, -)
      fail "$label" "storePassword/keyPassword with a value (line $n)"
    fi
  fi
}

# scan_raw <file with `git diff --raw -z` output> <index|commit> <label prefix>
scan_raw() {
  local meta path om nm osha nsha st rev
  while IFS= read -r -d '' meta; do
    IFS= read -r -d '' path || die "truncated git output"
    read -r om nm osha nsha st <<<"$meta"
    [ "$nm" != 160000 ] || continue # submodule: no content here
    if [ "$2" = index ]; then rev=":0:$path"; else rev=$nsha; fi
    check "$3$path" "$path" "$rev"
  done < "$1"
}

case "$mode" in
  staged)
    git diff --cached --raw --no-renames --diff-filter=d -z > "$list" || die "git diff --cached failed"
    scan_raw "$list" index ""
    ;;
  range)
    git rev-parse --verify --quiet "$base^{commit}" > /dev/null || die "unknown base commit: $base"
    git rev-parse --verify --quiet "$head^{commit}" > /dev/null || die "unknown head commit: $head"
    git rev-list "$base..$head" > "$work/commits" || die "git rev-list $base..$head failed"
    while IFS= read -r c; do
      # -m: a merge commit is compared with each parent, so a conflict resolution is checked too.
      git diff-tree -r -m --root --no-commit-id --no-renames --diff-filter=d -z "$c" > "$list" \
        || die "git diff-tree failed for $c"
      scan_raw "$list" commit "$(printf '%.12s' "$c"):"
    done < "$work/commits"
    ;;
  all)
    git ls-files -s -z > "$list" || die "git ls-files failed"
    while IFS= read -r -d '' rec; do
      meta=${rec%%$'\t'*}
      path=${rec#*$'\t'}
      read -r fmode sha stage <<<"$meta"
      [ "$fmode" != 160000 ] || continue
      check "$path" "$path" ":$stage:$path"
    done < "$list"
    ;;
esac

if [ "$bad" -ne 0 ]; then
  echo "check-secrets: signing keys and passwords belong in ~/.secrets/osc-alert and the GitHub Environment 'release', not in the repository." >&2
  exit 1
fi
