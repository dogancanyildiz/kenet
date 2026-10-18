#!/bin/sh
# Gerçek Xcode ve simülatör olmadan yeniden deneme sözleşmesini sına.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/xcodebuild-retry.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/test-xcodebuild-retry.XXXXXX")
trap 'rm -rf -- "$work"' 0
mkdir "$work/bin"
cat > "$work/bin/xcodebuild" <<'EOF'
#!/bin/sh
set -eu
count=$(cat "$CASE_ROOT/count")
count=$((count + 1))
echo "$count" > "$CASE_ROOT/count"
# Argüman sınırları (boşluklu paket yolu dahil) iki çağrıda da korunmalı.
[ "$#" -eq 4 ] && [ "$1" = test-without-building ] &&
  [ "$2" = -resultBundlePath ] && [ "$3" = "$CASE_ROOT/Test Results.xcresult" ] &&
  [ "$4" = -quiet ] || exit 99
if [ "$count" -eq 2 ]; then
  [ ! -e "$3" ] || exit 98
fi
mkdir "$3"
echo 'xcodebuild stdout'
if [ "$count" -eq 1 ]; then
  echo "$FIRST_MESSAGE" >&2
  exit "$FIRST_STATUS"
fi
echo 'second attempt' >&2
exit "$SECOND_STATUS"
EOF
cat > "$work/bin/xcrun" <<'EOF'
#!/bin/sh
set -eu
[ "$#" -eq 4 ] && [ "$1" = simctl ] && [ "$2" = bootstatus ] &&
  [ "$3" = test-udid ] && [ "$4" = -b ] || exit 99
echo bootstatus >> "$CASE_ROOT/boot"
EOF
cat > "$work/bin/sleep" <<'EOF'
#!/bin/sh
[ "$#" -eq 1 ] && [ "$1" = 10 ] || exit 99
echo sleep >> "$CASE_ROOT/sleep"
EOF
chmod +x "$work/bin/xcodebuild" "$work/bin/xcrun" "$work/bin/sleep"
PATH="$work/bin:$PATH"
export PATH

run_case() {
  name=$1
  FIRST_MESSAGE=$2 FIRST_STATUS=$3 SECOND_STATUS=$4
  expected_calls=$5 expected_status=$6
  CASE_ROOT="$work/$name"
  export FIRST_MESSAGE FIRST_STATUS SECOND_STATUS CASE_ROOT
  mkdir "$CASE_ROOT" "$CASE_ROOT/tmp"
  echo 0 > "$CASE_ROOT/count"
  actual_status=0
  TMPDIR="$CASE_ROOT/tmp" sh "$script" test-udid test-without-building \
    -resultBundlePath "$CASE_ROOT/Test Results.xcresult" -quiet > "$CASE_ROOT/output" 2>&1 || actual_status=$?
  if [ "$actual_status" -ne "$expected_status" ] ||
    [ "$(cat "$CASE_ROOT/count")" -ne "$expected_calls" ]; then
    echo "DÜŞTÜ: $name (çıkış $actual_status, çağrı $(cat "$CASE_ROOT/count"))"
    cat "$CASE_ROOT/output"
    exit 1
  fi
  grep -F 'xcodebuild stdout' "$CASE_ROOT/output" >/dev/null
  grep -F "$FIRST_MESSAGE" "$CASE_ROOT/output" >/dev/null
  if [ "$expected_calls" -eq 2 ]; then
    grep -F '::warning::' "$CASE_ROOT/output" >/dev/null
    [ "$(cat "$CASE_ROOT/boot")" = bootstatus ]
    [ "$(cat "$CASE_ROOT/sleep")" = sleep ]
    grep -F 'second attempt' "$CASE_ROOT/output" >/dev/null
  else
    [ ! -e "$CASE_ROOT/boot" ] && [ ! -e "$CASE_ROOT/sleep" ]
    if grep -F '::warning::' "$CASE_ROOT/output" >/dev/null; then
      echo "DÜŞTÜ: $name beklenmeyen yeniden deneme uyarısı"
      exit 1
    fi
  fi
  [ -d "$CASE_ROOT/Test Results.xcresult" ]
  [ -z "$(ls -A "$CASE_ROOT/tmp")" ]
  echo "geçti: $name ($expected_calls çağrı, çıkış $expected_status)"
}

run_case ilk-kosu-gecer 'TEST SUCCEEDED' 0 0 1 0
run_case aygit-bulunamadi 'xcodebuild: error: Unable to find a device matching the provided destination specifier' 70 0 2 0
run_case kosucu-asildi 'test() encountered an error (The test runner hung before establishing connection.)' 65 65 2 65
run_case test-dususu 'Test Case failed: snapshot difference' 65 0 1 65
