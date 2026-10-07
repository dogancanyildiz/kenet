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

# CI tek bir iOS runtime'ı taşır; yerelde birden çok olabilir. Referanslar CI ile aynı çizilsin diye
# en eski kurulu iOS runtime'ındaki iPhone seçilir (kimlikle, ad belirsiz kalmasın).
DEVICE=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
preferred = ["iPhone 17", "iPhone 16", "iPhone 15", "iPhone 14"]
runtimes = []
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    phones = [d for d in devices if d.get("isAvailable") and d.get("name", "").startswith("iPhone")]
    if phones:
        runtimes.append(((int(match.group(1)), int(match.group(2))), phones))
if not runtimes:
    print("Uygun iPhone simülatörü yok", file=sys.stderr)
    raise SystemExit(1)
version, phones = sorted(runtimes, key=lambda item: item[0])[0]
by_name = {d["name"]: d for d in phones}
chosen = next((by_name[n] for n in preferred if n in by_name), phones[0])
print(chosen["udid"], chosen["name"], "iOS %d.%d" % version)
')
ID=${DEVICE%% *}
NAME=${DEVICE#* }

# Görüntü test kümeleri ad kuralından bulunur (bkz. snapshot-suites.sh).
ONLY=$(sh .github/scripts/snapshot-suites.sh | sed 's#^#-only-testing:JournalTests_iOS/#' | tr '\n' ' ')
[ -n "$ONLY" ] || { echo "Görüntü test kümesi bulunamadı" >&2; exit 1; }

echo "Simülatör: $NAME"
echo "SNAPSHOT_TESTING_RECORD=$SNAPSHOT_TESTING_RECORD"

# Kayıt modunda ilk koşu referansı yazar; eksik referansta kütüphane bir kez düşer — ikinci koşu doğrular.
set +e
xcodebuild test \
  -project Journal.xcodeproj \
  -scheme Journal_iOS \
  -destination "platform=iOS Simulator,id=$ID" \
  $ONLY \
  -testLanguage tr -testRegion TR \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
status=$?
if [ "$SNAPSHOT_TESTING_RECORD" != "never" ] && [ "$status" -ne 0 ]; then
  echo "İlk kayıt koşusu düştü (beklenen); doğrulama koşusu…"
  unset SNAPSHOT_TESTING_RECORD
  xcodebuild test-without-building \
    -project Journal.xcodeproj \
    -scheme Journal_iOS \
    -destination "platform=iOS Simulator,id=$ID" \
    $ONLY \
    -testLanguage tr -testRegion TR \
  CODE_SIGNING_ALLOWED=NO \
    -quiet
  status=$?
fi
set -e
echo "Referanslar: Tests/JournalTests/Snapshots/__Snapshots__/"
exit "$status"
