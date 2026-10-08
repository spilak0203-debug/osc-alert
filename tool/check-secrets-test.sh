#!/usr/bin/env bash
# Self-test of tool/check-secrets.sh: builds throwaway repositories, puts violating and clean
# fixtures into an index (git hash-object + update-index, no work tree files) and checks the exit
# status and the report of the script for each.
#
#   bash tool/check-secrets-test.sh
#
# The script holds no key or password literal: names and key markers are assembled from pieces, so
# check-secrets.sh does not flag this file. The only password text is "hunter2", an example value
# that must never show up in the output of the checked script.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
script=$here/check-secrets.sh
[ -f "$script" ] || { echo "check-secrets-test: $script not found" >&2; exit 2; }

# A hook or CI step may export these; the throwaway repositories must not see them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

t=$(mktemp -d "${TMPDIR:-/tmp}/check-secrets-test.XXXXXX")
trap 'rm -rf "$t"' EXIT
export GIT_CEILING_DIRECTORIES=$t
mkdir "$t/outside"
git init -q "$t/repo"
cd "$t/repo"

# Pieces. Each is split so that the assembled text exists only at run time.
SP=store''Password
KP=key''Password
V=hunter2
pem() { printf '%s%s%s\n%s\n%s%s%s\n' '-----BEGIN ' "$1" ' KEY-----' 'MIIEvQIBADANBgkqhkiG9w0BAQEFAASC' '-----END ' "$1" ' KEY-----'; }
b64_jks() { printf 'data: %s%s\n' '/u3+' '7QAAAAIAAAAB'; }
b64_jceks() { printf 'data: %s%s\n' 'zs7O' 'zgAAAAIAAAAB'; }
b64_p12() { printf 'data: %s%s%s\n' 'MIIJ6A' 'IBAzCC' 'Ca4GCSqGSIb3DQEHAaCCCZ8EggmbMII'; }
# bytes <printf escapes>: the bytes a key format starts with, then filler text.
bytes() { printf "$1"; printf 'filler filler filler\n'; }

n_ok=0
n_bad=0
ok() { n_ok=$((n_ok + 1)); }
bad() { n_bad=$((n_bad + 1)); echo "FAIL: $1"; }

put() { # put <path>, content on stdin; goes into the index $GIT_INDEX_FILE
  local sha
  sha=$(git hash-object -w --stdin)
  git update-index --add --cacheinfo "100644,$sha,$1"
}

out=
rc=0
run() { # run <script args...>: sets $out and $rc
  if out=$(bash "$script" "$@" 2>&1); then rc=0; else rc=$?; fi
  case "$out" in *"$V"*) bad "output of '$*' contains the password text" ;; esac
}

want_rc() { # want_rc <label> <exit status> <script args...>
  local label=$1 want=$2
  shift 2
  run "$@"
  if [ "$rc" -eq "$want" ]; then ok; else bad "$label: exit $rc, wanted $want"; echo "$out" | sed 's/^/    /'; fi
}

want_error() { # want_error <label> <script args...>: exit 1 or 2, never 0 (the fail-open cases)
  local label=$1
  shift
  run "$@"
  if [ "$rc" -eq 1 ] || [ "$rc" -eq 2 ]; then ok; else bad "$label: exit $rc, wanted 1 or 2"; echo "$out" | sed 's/^/    /'; fi
}

# Two batches: every violating fixture goes into one index and every clean one into another. One
# run per mode has to flag every violating file with its reason, and report nothing for the clean ones.
exp_bad=()
exp_why=()
bad_file() { put "$1"; exp_bad+=("$1"); exp_why+=("$2"); } # bad_file <path> <reason fragment>, content on stdin
ok_file() { put "$1"; }

export GIT_INDEX_FILE=$t/bad-index

K='key file extension'
# a. key file extensions, any case, any directory
for ext in jks keystore jceks bks p12 pfx pem key p8 pk8 JKS Pem; do
  bad_file "ext/secret.$ext" "$K" <<<"x"
done
bad_file "ext/two.dots.key" "$K" <<<"x"

# b. PEM private key blocks
for kind in RSA EC DSA OPENSSH ENCRYPTED; do
  bad_file "pem/$kind.txt" "PEM private key block" < <(pem "$kind PRIVATE")
done
bad_file "pem/plain.txt" "PEM private key block" < <(pem "PRIVATE")
# A NUL far below the start does not make the file binary; the block must still be found (grep -a).
bad_file "pem/late-nul.txt" "PEM private key block" < <(yes 'filler line of text' | head -c 200000 || true; printf '\n\0\n'; pem "RSA PRIVATE")

# c. magic bytes, whatever the name
bad_file "magic/jks.bin" "Java keystore" < <(bytes '\xfe\xed\xfe\xed\x00\x00\x00\x02')
bad_file "magic/jceks.dat" "JCEKS keystore" < <(bytes '\xce\xce\xce\xce\x00\x00\x00\x02')
bad_file "magic/pkcs12" "PKCS12" < <(bytes '\x30\x82\x09\xe8\x02\x01\x03\x30\x82')
bad_file "magic/pkcs12.png" "PKCS12" < <(bytes '\x30\x82\x00\x10\x02\x01\x03\x30')
bad_file "magic/pkcs8.bin" 'PKCS#8' < <(bytes '\x30\x82\x04\xbd\x02\x01\x00\x30\x0d')
bad_file "magic/pkcs8-short.bin" 'PKCS#8' < <(bytes '\x30\x81\x87\x02\x01\x00\x30\x13')
bad_file "magic/exactly-7-bytes.bin" "PKCS12" < <(printf '\x30\x82\x09\xe8\x02\x01\x03')

# d. base64 text of a keystore
bad_file "b64/jks.txt" "base64" < <(b64_jks)
bad_file "b64/jceks.txt" "base64" < <(b64_jceks)
bad_file "b64/pkcs12.txt" "base64" < <(b64_p12)
bad_file "b64/inside-a-line.txt" "base64" < <(printf 'KEYSTORE: '; b64_jks)

W='with a value'
# e. passwords in .properties, with the three separators Java accepts
bad_file "pw/eq.properties" "$W" <<<"$SP=$V"
bad_file "pw/eq-spaced.properties" "$W" <<<"$SP = $V"
bad_file "pw/colon.properties" "$W" <<<"$KP: $V"
bad_file "pw/colon-nospace.properties" "$W" <<<"$KP:$V"
bad_file "pw/space.properties" "$W" <<<"$SP $V"
bad_file "pw/tab.properties" "$W" < <(printf '%s\t%s\n' "$KP" "$V")
bad_file "pw/indented.properties" "$W" <<<"   $SP=$V"
bad_file "pw/second-line.properties" "(line 3)" < <(printf 'storeFile=a.jks\nkeyAlias=x\n%s %s\n' "$KP" "$V")
bad_file "pw/UPPER.PROPERTIES" "$W" <<<"$SP=$V"
bad_file "pw/late-nul.properties" "(line 100" < <(yes 'filler line of text' | head -c 200000 || true; printf '\n\0\n%s=%s\n' "$SP" "$V")

# e. passwords in gradle files (Groovy and Kotlin)
bad_file "gradle/legacy/build.gradle" "$W" <<<"            $SP project.findProperty('$SP') ?: '$V'"
bad_file "gradle/legacy2/build.gradle" "$W" <<<"            $KP project.findProperty(\"$KP\") ?: \"$V\""
bad_file "gradle/groovy-eq/build.gradle" "$W" <<<"    $SP = \"$V\""
bad_file "gradle/groovy-space/build.gradle" "$W" <<<"    $SP '$V'"
bad_file "gradle/groovy-call/build.gradle" "$W" <<<"    $KP('$V')"
bad_file "gradle/kts-eq/build.gradle.kts" "$W" <<<"    $SP = \"$V\""
bad_file "gradle/kts-single/build.gradle.kts" "$W" <<<"    $KP = '$V'"
bad_file "gradle/kts-nospace/build.gradle.kts" "$W" <<<"    $SP=\"$V\""
bad_file "gradle/kts-member/build.gradle.kts" "$W" <<<"    signingConfig.$SP = \"$V\""
bad_file "gradle/kts-elvis/build.gradle.kts" "$W" <<<"    $SP = props.getProperty(\"$SP\") ?: \"$V\""
bad_file "gradle/UPPER/BUILD.GRADLE" "$W" <<<"    $SP = \"$V\""

# e. passwords as env / shell assignments
bad_file "env/dotenv.env" "$W" <<<"$SP=\"$V\""
bad_file "env/bare.env" "$W" <<<"$SP=$V"
bad_file "env/export.sh" "$W" <<<"export $KP=\"$V\""
bad_file "env/single.sh" "$W" <<<"$KP='$V'"
bad_file "env/in-readme.md" "$W" < <(printf 'Set it:\n\n    %s="%s"\n' "$SP" "$V")

# h. passwords in YAML and JSON
bad_file "yaml/plain.yml" "$W" <<<"$SP: $V"
bad_file "yaml/list.yaml" "$W" <<<"  - $KP: $V"
bad_file "yaml/quoted.yml" "$W" <<<"  $SP: \"$V\""
bad_file "json/pretty.json" "$W" <<<"  \"$SP\": \"$V\","
bad_file "json/compact.json" "$W" <<<"{\"a\":1,\"$KP\":\"$V\"}"

# file names with spaces and Hangul
bad_file "space dir/key file.pem" "$K" <<<"x"
bad_file "비밀 키.jks" "$K" <<<"x"
bad_file "한글 폴더/설정 파일.properties" "$W" <<<"$SP=$V"
bad_file "dir with space/keystore data.bin" "Java keystore" < <(bytes '\xfe\xed\xfe\xed\x00\x00\x00\x02')
bad_file "한글 폴더/키스토어 base64.txt" "base64" < <(b64_jks)

export GIT_INDEX_FILE=$t/ok-index

ok_file "ok/readme.md" <<<"Put $SP and $KP into the properties file, never into the repository."
ok_file "ok/words.txt" <<<"keyboard monkey keys pem.txt key"
ok_file "ok/key" <<<"a file named key with no extension"
ok_file "ok/names-only.properties" < <(printf 'storeFile=a.jks\nkeyAlias=x\n%s\n' "$SP")
ok_file "ok/empty-values.properties" < <(printf '%s=\n%s =\n%s:\n' "$SP" "$KP" "$SP")
ok_file "ok/other.properties" <<<"org.gradle.jvmargs=-Xmx4G"
ok_file "ok/build.gradle.kts" < <(cat <<EOF
    val missing = listOf("storeFile", "$SP", "keyAlias", "$KP")
    $SP = signingProps.getProperty("$SP")
    $KP = signingProps.getProperty("$KP")
    $SP = System.getenv("STORE_PASSWORD")
    $KP = System.getenv("KEY_PASSWORD") ?: error("no key password")
    val s = props["$KP"]
    // $SP, $KP and keyAlias come from the properties file
EOF
)
ok_file "ok/groovy/build.gradle" < <(cat <<EOF
            $SP project.findProperty('$SP') ?: System.getenv('STORE_PASSWORD')
            $KP = findProperty("$KP")
            $SP = ""
            $KP = "\${keyPw}"
EOF
)
ok_file "ok/env.sh" < <(printf 'printf "k=%%s" "$pass"\n%s="$X"\n%s=%%s\n%s=""\n%s=${X}\n%s=\n' "$SP" "$KP" "$SP" "$KP" "$SP")
ok_file "ok/workflow.yml" < <(cat <<EOF
env:
  $SP: \${{ secrets.STORE }}
  $KP:
  other: "$SP"
names: ["$SP", "$KP"]
description: the $SP of the key
EOF
)
ok_file "ok/empty.json" <<<"{\"$SP\": \"\", \"$KP\": \"\${X}\"}"
ok_file "ok/cert.txt" < <(printf '%s\n%s\n%s\n' '-----BEGIN CERTIFICATE-----' 'MIIDdzCCAl+gAwIBAgIEAgAAuTANBgkqhkiG9w0BAQUFADBa' '-----END CERTIFICATE-----')
ok_file "ok/base64.txt" <<<"aGVsbG8gd29ybGQ= ZnJvbSB0aGUgdGVzdA=="
ok_file "ok/png.bin" < <(printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR')
ok_file "ok/der-cert.bin" < <(bytes '\x30\x82\x09\xe8\x30\x82\x07\xd0')
ok_file "ok/der-other-version.bin" < <(bytes '\x30\x82\x09\xe8\x02\x01\x04\x30')
ok_file "ok/six-bytes.bin" < <(printf '\x30\x82\x09\xe8\x02\x01')
ok_file "ok/empty" < /dev/null
ok_file "ok/한글 폴더/정상 파일.txt" <<<"안녕하세요"
ok_file "ok/dir with space/plain file.properties" <<<"storeFile=a.jks"

# ---------------------------------------------------------------- batches

check_bad_batch() { # <label> <script args...>
  local label=$1 i line found
  shift
  export GIT_INDEX_FILE=$t/bad-index
  run "$@"
  if [ "$rc" -eq 1 ]; then ok; else bad "$label: exit $rc, wanted 1"; fi
  for i in "${!exp_bad[@]}"; do
    found=0
    while IFS= read -r line; do
      case "$line" in "${exp_bad[$i]}: "*"${exp_why[$i]}"*) found=1 ;; esac
    done <<<"$out"
    if [ "$found" -eq 1 ]; then ok; else bad "$label: expected '${exp_bad[$i]}' reported as '${exp_why[$i]}'"; fi
  done
}

check_ok_batch() { # <label> <script args...>
  local label=$1
  shift
  export GIT_INDEX_FILE=$t/ok-index
  run "$@"
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok; else bad "$label: exit $rc, wanted 0 and no output"; echo "$out" | sed 's/^/    /'; fi
}

check_bad_batch "violations --staged" --staged
check_bad_batch "violations (all tracked)"
check_ok_batch "clean files --staged" --staged
check_ok_batch "clean files (all tracked)"

# ---------------------------------------------------------------- fail-open cases

export GIT_INDEX_FILE=$t/ok-index
cd "$t/outside"
want_error "outside a repository --staged" --staged
want_error "outside a repository"
want_error "outside a repository --range" --range HEAD HEAD
cd "$t/repo"

export GIT_DIR=/nonexistent
want_error "GIT_DIR=/nonexistent --staged" --staged
want_error "GIT_DIR=/nonexistent"
unset GIT_DIR

printf 'garbage' > "$t/garbage-index"
export GIT_INDEX_FILE=$t/garbage-index
want_error "corrupt index --staged" --staged
want_error "corrupt index"

# An index entry whose blob is not in the object database: unreadable, not skipped.
export GIT_INDEX_FILE=$t/missing-index
git update-index --add --info-only --cacheinfo "100644,0000000000000000000000000000000000000001,gone.txt"
want_error "missing blob --staged" --staged
want_error "missing blob"

export GIT_INDEX_FILE=$t/ok-index
want_rc "unknown option" 2 --bogus
want_rc "--range without commits" 2 --range one
want_rc "--staged with an extra argument" 2 --staged extra
want_error "unknown base commit" --range 0123456789012345678901234567890123456789 HEAD

# ---------------------------------------------------------------- --range

unset GIT_INDEX_FILE
git init -q "$t/range"
cd "$t/range"

commit() { # commit <message>: commits the index on top of HEAD (plumbing, so no hooks run)
  local tree c
  tree=$(git write-tree)
  if git rev-parse -q --verify HEAD > /dev/null; then
    c=$(git commit-tree "$tree" -p HEAD -m "$1")
  else
    c=$(git commit-tree "$tree" -m "$1")
  fi
  git update-ref HEAD "$c"
  git rev-parse HEAD
}

put a.txt <<<"hello"
C0=$(commit "clean")
bytes '\x30\x82\x09\xe8\x02\x01\x03\x30' | put k.dat
C1=$(commit "adds a keystore under a harmless name")
git update-index --force-remove k.dat
C2=$(commit "removes it again")
put a.txt <<<"$SP=$V"
C3=$(commit "adds a password")
put a.txt <<<"hello again"
C4=$(commit "removes the password")
put b.txt <<<"clean"
C5=$(commit "clean")

# a commit without a parent (an unrelated history) and a merge whose result holds a new key file
export GIT_INDEX_FILE=$t/root-index
put orphan.pem <<<"x"
ROOT=$(git commit-tree "$(git write-tree)" -m "unrelated root")
export GIT_INDEX_FILE=$t/side-index
git read-tree "$C0"
put side.txt <<<"side"
S=$(git commit-tree "$(git write-tree)" -p "$C0" -m "side")
git read-tree "$C5"
put side.txt <<<"side"
put res.pem <<<"x"
M=$(git commit-tree "$(git write-tree)" -p "$C5" -p "$S" -m "merge")
unset GIT_INDEX_FILE

want_rc "tree at HEAD is clean although history is not" 0
want_rc "range C0..C5 sees the keystore and the password" 1 --range "$C0" "$C5"
case "$out" in *"${C1:0:12}:k.dat: "*) ok ;; *) bad "range C0..C5: report lacks the keystore commit and path"; echo "$out" ;; esac
case "$out" in *"${C3:0:12}:a.txt: "*) ok ;; *) bad "range C0..C5: report lacks the password commit and path"; echo "$out" ;; esac
want_rc "range C0..C1" 1 --range "$C0" "$C1"
want_rc "range C1..C2 (only a deletion)" 0 --range "$C1" "$C2"
want_rc "range C2..C3 (password added)" 1 --range "$C2" "$C3"
want_rc "range C3..C5" 0 --range "$C3" "$C5"
want_rc "range C5..C5 (empty)" 0 --range "$C5" "$C5"
want_rc "range C5..C0 (reversed, empty)" 0 --range "$C5" "$C0"
want_rc "range with a root commit" 1 --range "$C5" "$ROOT"
case "$out" in *"${ROOT:0:12}:orphan.pem: "*) ok ;; *) bad "root commit: report lacks the path"; echo "$out" ;; esac
want_rc "range with a merge commit" 1 --range "$C5" "$M"
case "$out" in *"${M:0:12}:res.pem: "*) ok ;; *) bad "merge commit: report lacks the path"; echo "$out" ;; esac
want_error "range with an unknown head" --range "$C0" 0123456789012345678901234567890123456789

# --staged does not look at deleted files: HEAD holds the keystore, the index is emptied
git update-ref HEAD "$C1"
git read-tree --empty
want_rc "staged deletion of a keystore" 0 --staged

# ---------------------------------------------------------------- result

if [ "$n_bad" -ne 0 ]; then
  echo "check-secrets-test: $n_bad failed, $n_ok passed" >&2
  exit 1
fi
echo "check-secrets-test: all $n_ok checks passed"
