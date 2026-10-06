#!/bin/sh
# Regenerates screen-snapshot reference PNGs under Tests/JournalTests/Snapshots/.
# Local: sh .github/scripts/record-screen-snapshots.sh
# CI: workflow_dispatch on "Ekran görüntüsü referansları" — download the artifact into Tests/.
set -eu
cd "$(dirname "$0")/../.."

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export SNAPSHOT_TESTING_RECORD="${SNAPSHOT_TESTING_RECORD:-all}"

command -v xcodegen >/dev/null || { echo "xcodegen gerekli: brew install xcodegen" >&2; exit 1; }
xcodegen generate

NAME=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
preferred = ["iPhone 17", "iPhone 16", "iPhone 15", "iPhone 14"]
names = []
for runtime, devices in data.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
            names.append(device["name"])
for name in preferred:
    if name in names:
        print(name)
        raise SystemExit(0)
if names:
    print(names[0])
    raise SystemExit(0)
print("Uygun iPhone simülatörü yok", file=sys.stderr)
raise SystemExit(1)
')

echo "Simülatör: $NAME"
echo "SNAPSHOT_TESTING_RECORD=$SNAPSHOT_TESTING_RECORD"

# Kayıt modunda ilk koşu referansı yazar; eksik referansta kütüphane bir kez düşer — ikinci koşu doğrular.
set +e
xcodebuild test \
  -project Journal.xcodeproj \
  -scheme Journal_iOS \
  -destination "platform=iOS Simulator,name=$NAME" \
  -only-testing:JournalTests_iOS/ScreenSnapshotTests \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
status=$?
if [ "$SNAPSHOT_TESTING_RECORD" != "never" ] && [ "$status" -ne 0 ]; then
  echo "İlk kayıt koşusu düştü (beklenen); doğrulama koşusu…"
  unset SNAPSHOT_TESTING_RECORD
  xcodebuild test-without-building \
    -project Journal.xcodeproj \
    -scheme Journal_iOS \
    -destination "platform=iOS Simulator,name=$NAME" \
    -only-testing:JournalTests_iOS/ScreenSnapshotTests \
    CODE_SIGNING_ALLOWED=NO \
    -quiet
  status=$?
fi
set -e
echo "Referanslar: Tests/JournalTests/Snapshots/__Snapshots__/ScreenSnapshotTests/"
exit "$status"
