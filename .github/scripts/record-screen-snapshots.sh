#!/bin/sh
# Regenerates screen-snapshot reference PNGs under Tests/JournalTests/Snapshots/.
# Local: sh .github/scripts/record-screen-snapshots.sh
# CI: workflow_dispatch on "Ekran görüntüsü referansları" — download the artifact into Tests/.
# Derleme ve koşu ayrıdır: build-for-testing, DerivedData SNAPSHOT_DERIVED_DATA
# (varsayılan .dd/snapshots); kayıt ve doğrulama test-without-building ile aynı yoldadır.
# SNAPSHOT_SUITES doluysa yalnız o kümeler (boşlukla ayrılmış adlar); boşsa bütün iOS kümeleri.
# --duo: yalnız iPhone Duo tuval kümeleri (snapshot-suites.sh --duo). Bu kümeler test konağında
# SNAPSHOT_DUO=1 görmeden koşmaz; betik değişkeni TEST_RUNNER_SNAPSHOT_DUO olarak geçirir.
# --pad: yalnız iPad tuval kümeleri (snapshot-suites.sh --pad), iPad simülatöründe (tercih sırası
# aşağıda; CI ile aynı aygıt). Bu kümeler iPhone'da kendini atlar.
# Kayıt kipi varsayılan "failed": yalnız eşleşmeyen ya da eksik referans yazılır; eşleşen PNG'ler
# bayt düzeyinde aynı kalır ve diff'e girmez. Hepsini yeniden yazmak için SNAPSHOT_TESTING_RECORD=all.
set -eu
cd "$(dirname "$0")/../.."

SUITES_FLAG=""
FAMILY="iPhone"
case "${1:-}" in
  --duo)
    SUITES_FLAG="--duo"
    export TEST_RUNNER_SNAPSHOT_DUO=1
    ;;
  --pad)
    SUITES_FLAG="--pad"
    FAMILY="iPad"
    ;;
esac

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
export SNAPSHOT_TESTING_RECORD="${SNAPSHOT_TESTING_RECORD:-failed}"

command -v xcodegen >/dev/null || { echo "xcodegen gerekli: brew install xcodegen" >&2; exit 1; }
xcodegen generate

# CI tek bir iOS runtime'ı taşır; yerelde birden çok olabilir. Referanslar CI ile aynı çizilsin diye
# en eski kurulu iOS runtime'ındaki aygıt seçilir (kimlikle, ad belirsiz kalmasın). iPad'de yalnız
# tercih listesindeki aygıtlar sayılır: referanslar 13 inçlik ekranda çizilir; liste
# .github/actions/ios-build ile aynıdır.
DEVICE=$(xcrun simctl list devices available -j | FAMILY="$FAMILY" python3 -c '
import json, os, re, sys
data = json.load(sys.stdin)
family = os.environ["FAMILY"]
if family == "iPad":
    preferred = ["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)", "iPad Air 13-inch (M4)",
                 "iPad Air 13-inch (M3)", "iPad Pro 13-inch"]
else:
    preferred = ["iPhone 17", "iPhone 16", "iPhone 15", "iPhone 14"]
runtimes = []
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    found = [d for d in devices if d.get("isAvailable") and d.get("name", "").startswith(family)]
    if family == "iPad":
        found = [d for d in found if d["name"] in preferred]
    if found:
        runtimes.append(((int(match.group(1)), int(match.group(2))), found))
if not runtimes:
    print("Uygun %s simülatörü yok" % family, file=sys.stderr)
    raise SystemExit(1)
version, found = sorted(runtimes, key=lambda item: item[0])[0]
by_name = {d["name"]: d for d in found}
chosen = next((by_name[n] for n in preferred if n in by_name), found[0])
print(chosen["udid"], chosen["name"], "iOS %d.%d" % version)
')
ID=${DEVICE%% *}
NAME=${DEVICE#* }

# Görüntü test kümeleri ad kuralından bulunur (bkz. snapshot-suites.sh).
if [ -n "${SNAPSHOT_SUITES:-}" ]; then
  ONLY=$(printf '%s\n' $SNAPSHOT_SUITES | sed 's#^#-only-testing:JournalTests_iOS/#' | tr '\n' ' ')
else
  ONLY=$(sh .github/scripts/snapshot-suites.sh $SUITES_FLAG | sed 's#^#-only-testing:JournalTests_iOS/#' | tr '\n' ' ')
fi
[ -n "$ONLY" ] || { echo "Görüntü test kümesi bulunamadı" >&2; exit 1; }

# Simülatörde kurulu kalan uygulamanın kayıtlı durumu (arayüz testleri ya da elle açılış sonrası)
# görüntüleri kaydırır; CI temiz simülatörde koşar. Yerelde de temiz durumdan başlanır.
# Kimlik tek yerde durur: project.yml içindeki APP_BUNDLE_IDENTIFIER.
APP=$(sed -n 's/^ *APP_BUNDLE_IDENTIFIER: *//p' project.yml)
[ -n "$APP" ] || { echo "project.yml içinde APP_BUNDLE_IDENTIFIER bulunamadı" >&2; exit 1; }
xcrun simctl uninstall "$ID" "$APP" >/dev/null 2>&1 || true
xcrun simctl uninstall "$ID" "$APP.testhost" >/dev/null 2>&1 || true
xcrun simctl uninstall "$ID" "$APP.uitests.xctrunner" >/dev/null 2>&1 || true

# iPad referansları dik simülatörde çizilir (CI'daki yeni açılmış simülatör gibi): bölünmüş görünüm
# sütunlarını sahnenin yönünden seçer ve birim testi aygıtı döndüremez. Döndürülmüş kalmış bir
# simülatör yeniden başlatılınca dik açılır.
if [ "$FAMILY" = "iPad" ]; then
  xcrun simctl shutdown "$ID" >/dev/null 2>&1 || true
  xcrun simctl boot "$ID"
  xcrun simctl bootstatus "$ID" -b >/dev/null
fi

echo "Simülatör: $NAME"
echo "SNAPSHOT_TESTING_RECORD=$SNAPSHOT_TESTING_RECORD"

DERIVED="${SNAPSHOT_DERIVED_DATA:-.dd/snapshots}"

# Kayıt kipinde yazılan her referans o koşuyu düşürür; ikinci koşu yeni referanslara karşı doğrular.
# Her referans eşleşirse ilk koşu geçer ve ikinci koşu gerekmez.
set +e
xcodebuild build-for-testing \
  -project Journal.xcodeproj \
  -scheme Journal_iOS \
  -destination "platform=iOS Simulator,id=$ID" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
status=$?
if [ "$status" -eq 0 ]; then
  xcodebuild test-without-building \
    -project Journal.xcodeproj \
    -scheme Journal_iOS \
    -destination "platform=iOS Simulator,id=$ID" \
    -derivedDataPath "$DERIVED" \
    $ONLY \
    -testLanguage tr -testRegion TR \
    CODE_SIGNING_ALLOWED=NO \
    -quiet
  status=$?
  # Kayıt kipinde bir referans yazılınca ilk koşu düşer; doğrulama aynı DerivedData ile koşar.
  if [ "$SNAPSHOT_TESTING_RECORD" != "never" ] && [ "$status" -ne 0 ]; then
    echo "İlk kayıt koşusu düştü (beklenen); doğrulama koşusu…"
    unset SNAPSHOT_TESTING_RECORD
    xcodebuild test-without-building \
      -project Journal.xcodeproj \
      -scheme Journal_iOS \
      -destination "platform=iOS Simulator,id=$ID" \
      -derivedDataPath "$DERIVED" \
      $ONLY \
      -testLanguage tr -testRegion TR \
      CODE_SIGNING_ALLOWED=NO \
      -quiet
    status=$?
  fi
fi
set -e
echo "Referanslar: Tests/JournalTests/Snapshots/__Snapshots__/"
exit "$status"
