#!/bin/sh
# Yalnız bilinen simülatör altyapı hatalarında bir kez yeniden dene.
set -u

if [ "$#" -lt 2 ]; then
  echo "Kullanım: sh $0 <udid> <xcodebuild argümanları...>" >&2
  exit 2
fi
udid=$1
shift

result_bundle=
next_is_bundle=false
for arg do
  if [ "$next_is_bundle" = true ]; then
    result_bundle=$arg
    next_is_bundle=false
  elif [ "$arg" = -resultBundlePath ]; then
    next_is_bundle=true
  fi
done

work=$(mktemp -d "${TMPDIR:-/tmp}/xcodebuild-retry.XXXXXX") || exit 1
trap 'rm -rf -- "$work"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

run_xcodebuild() {
  # POSIX sh'de pipefail yok: tee'nin değil xcodebuild'in durumunu sakla.
  (
    xcodebuild "$@" 2>&1
    echo "$?" > "$work/status"
  ) | tee "$work/output.log"
  status=$(cat "$work/status")
}

run_xcodebuild "$@"
if [ "$status" -eq 0 ]; then
  exit 0
fi
if ! grep -F -e 'Unable to find a device matching the provided destination specifier' \
  -e 'hung before establishing connection' "$work/output.log" >/dev/null; then
  exit "$status"
fi

echo "::warning::Simülatör altyapı hatası (çıkış $status); $udid beklenip test bir kez yeniden denenecek."
sleep 10
xcrun simctl bootstatus "$udid" -b
if [ -n "$result_bundle" ] && [ -d "$result_bundle" ]; then
  rm -rf -- "$result_bundle" || exit 1
fi
run_xcodebuild "$@"
exit "$status"
