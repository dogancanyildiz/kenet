#!/bin/sh
# Ekran turu: uygulamayı kurgusal örnek kasayla simülatörde gezer, her ekranın PNG'sini verilen
# klasöre yazar (Tests/JournalUITests/ScreenTourUITests.swift). Tasarım işinde önce / sonra
# karşılaştırması içindir; CI'da koşmaz.
#
#   sh .github/scripts/screen-tour.sh <çıktı klasörü> [simülatör kimliği]
#   sh .github/scripts/screen-tour.sh --mac <çıktı klasörü>
#
# --mac (ya da SCREEN_TOUR_PLATFORM=mac) Mac uygulamasını gezer ve her ekranın pencere görüntüsünü
# yazar (Tests/JournalMacUITests/ScreenTourMacUITests.swift). Tur sürerken fare ve klavye testin
# elindedir; bitene kadar bilgisayara dokunma. Gerçek kasaya ve ayarlara dokunulmaz: uygulama ayrı
# bir bundle kimliğiyle (….screentour) derlenir, ev klasörü olarak geçici bir klasör görür ve
# koşu bitince o kimliğin ayarları silinir. Sistem görünümü değiştirilmez. Pencere ana ekranda
# 1280x800 açılır. SCREEN_TOUR_ONLY=ayarlar,koyu turun yalnız adı verilen bölümlerini koşar
# (bölüm adları test dosyasında).
#
# Çıktı klasörü depo dışında olmalıdır: görüntüler depoya ve PR'a girmez (Kasa ayar sayfası
# makine yolunu gösterir). Simülatör kimliği ikinci argümanla ya da SCREEN_TOUR_SIMULATOR ile
# verilir; verilmezse görüntü kaydı betiğiyle aynı cihaz seçilir. SCREEN_TOUR_TREE=1 her
# görüntünün yanına erişilebilirlik ağacını da yazar (<çıktı>/agac/): atlanan adımı ayıklamak için.
set -eu

PLATFORM="${SCREEN_TOUR_PLATFORM:-ios}"
if [ "${1:-}" = "--mac" ]; then
  PLATFORM=mac
  shift
fi
[ $# -ge 1 ] || { echo "Kullanım: sh .github/scripts/screen-tour.sh [--mac] <çıktı klasörü> [simülatör kimliği]" >&2; exit 2; }
mkdir -p "$1"
OUT=$(cd "$1" && pwd -P)
ID="${2:-${SCREEN_TOUR_SIMULATOR:-}}"

cd "$(dirname "$0")/../.."
ROOT=$(pwd -P)
case "$OUT/" in
  "$ROOT"/*) echo "Çıktı klasörü depo dışında olmalı: $OUT" >&2; exit 2 ;;
esac

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

command -v xcodegen >/dev/null || { echo "xcodegen gerekli: brew install xcodegen" >&2; exit 1; }
xcodegen generate

# Kimlik tek yerde durur: project.yml içindeki APP_BUNDLE_IDENTIFIER.
APP=$(sed -n 's/^ *APP_BUNDLE_IDENTIFIER: *//p' project.yml)
[ -n "$APP" ] || { echo "project.yml içinde APP_BUNDLE_IDENTIFIER bulunamadı" >&2; exit 1; }
WORK=$(mktemp -d)
RESULT="$WORK/tour.xcresult"
trap 'rm -rf "$WORK"' EXIT
echo "Çıktı: $OUT"

# Önceki koşunun görüntüleri yeni koşunun atladığı adımı gizlemesin.
clear_output() {
  find "$OUT" -maxdepth 1 -type f \( -name '[0-9][0-9]-*.png' -o -name 'atlananlar.txt' \) -delete
  rm -rf "$OUT/agac"
}

if [ "$PLATFORM" = "mac" ]; then
  # Ayrı kimlik: UserDefaults (pencere konumu, kısayol, kasa yer imi) gerçek uygulamanınkine karışmaz.
  TOUR_APP="$APP.screentour"
  # Ayrı derleme klasörü: olağan derlemenin ürünü tur kimliğiyle ezilmez.
  DERIVED="$HOME/Library/Developer/Xcode/DerivedData/Journal-mac-screen-tour"
  WATCH=""
  cleanup() {
    if [ -n "$WATCH" ]; then
      kill "$WATCH" >/dev/null 2>&1 || true
      wait "$WATCH" 2>/dev/null || true
    fi
    defaults delete "$TOUR_APP" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$TOUR_APP.plist"
    # Test koşucusunun kum havuzu (geçici ev klasörü ve kasa kopyası burada durur).
    rm -rf "$HOME/Library/Containers/$TOUR_APP.uitests.xctrunner" >/dev/null 2>&1 || true
    rm -rf "$WORK"
  }
  trap cleanup EXIT
  # Pencere boyutu başlatma argümanıyla verilir (1280x800), ama uygulama kendi kaydettiği pencere
  # durumunu bulursa onu kullanır ve en küçük boyutta açılır. Tur sürerken tur kimliğinin ayarları
  # sürekli silinir: her açılış ilk açılış gibi olur.
  ( while :; do defaults delete "$TOUR_APP" >/dev/null 2>&1 || true; sleep 0.3; done ) &
  WATCH=$!
  clear_output
  # İmza: takımsız (ad hoc) ve yetkisiz. İmzasız koşucu açılmaz; kum havuzlu uygulama ise koşucunun
  # hazırladığı kasa kopyasını okuyamaz. Koşucu kum havuzludur ve çıktı klasörüne yazamaz;
  # görüntüler sonuç paketinden çıkarılır (aşağıda).
  set +e
  TEST_RUNNER_JOURNAL_SCREEN_TOUR_DIR="$OUT" \
  TEST_RUNNER_JOURNAL_SCREEN_TOUR_TREE="${SCREEN_TOUR_TREE:-}" \
  TEST_RUNNER_JOURNAL_SCREEN_TOUR_ONLY="${SCREEN_TOUR_ONLY:-}" \
  xcodebuild test \
    -project Journal.xcodeproj \
    -scheme Journal_macOS_ScreenTour \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$DERIVED" \
    -resultBundlePath "$RESULT" \
    APP_BUNDLE_IDENTIFIER="$TOUR_APP" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS= \
    -quiet
  status=$?
  set -e
else

# Cihaz seçimi record-screen-snapshots.sh ile aynıdır: en eski kurulu iOS runtime'ındaki iPhone 17.
if [ -z "$ID" ]; then
  ID=$(xcrun simctl list devices available -j | python3 -c '
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
print(next((by_name[n] for n in preferred if n in by_name), phones[0])["udid"])
')
fi
echo "Simülatör: $ID"

uninstall() {
  xcrun simctl uninstall "$ID" "$APP" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$ID" "$APP.testhost" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$ID" "$APP.uitests.xctrunner" >/dev/null 2>&1 || true
}
# Ne olursa olsun simülatör bulunduğu gibi bırakılır: açık görünüm, gerçek saat, uygulama kaldırılmış.
cleanup() {
  xcrun simctl ui "$ID" appearance light >/dev/null 2>&1 || true
  xcrun simctl status_bar "$ID" clear >/dev/null 2>&1 || true
  uninstall
  rm -rf "$WORK"
}
trap cleanup EXIT

xcrun simctl bootstatus "$ID" -b >/dev/null
# Kurulu kalan uygulamanın kayıtlı durumu (son Görevler görünümü, arama geçmişi) görüntüleri kaydırır.
uninstall
xcrun simctl ui "$ID" appearance light
# Saat ve pil koşudan koşuya aynı görünsün.
xcrun simctl status_bar "$ID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularBars 4 >/dev/null 2>&1 || true

clear_output

# TEST_RUNNER_ önekli değişkenler test koşucusuna öneksiz iletilir; şemaya eklemek gerekmez.
set +e
TEST_RUNNER_JOURNAL_SCREEN_TOUR_DIR="$OUT" \
TEST_RUNNER_JOURNAL_SCREEN_TOUR_TREE="${SCREEN_TOUR_TREE:-}" \
xcodebuild test \
  -project Journal.xcodeproj \
  -scheme Journal_iOS \
  -destination "platform=iOS Simulator,id=$ID" \
  -only-testing:JournalUITests/ScreenTourUITests \
  -resultBundlePath "$RESULT" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
status=$?
set -e

fi

# Tur bir ekrana ulaşamayınca düşmez; düştüyse neden (uygulama açılmadı, simülatör yanıt vermedi) buradadır.
if [ "$status" -ne 0 ] && [ -d "$RESULT" ]; then
  xcrun xcresulttool get test-results summary --path "$RESULT" 2>/dev/null | python3 -c '
import json, sys
for failure in json.load(sys.stdin).get("testFailures", []):
    print("Hata:", failure.get("testName", ""), "-", failure.get("failureText", ""))
' >&2 || true
fi

# Koşucu ana makine yoluna yazamadıysa görüntüler sonuç paketine eklenmiştir: oradan çıkar.
if [ -d "$RESULT" ] && ! ls "$OUT"/[0-9][0-9]-*.png >/dev/null 2>&1; then
  if xcrun xcresulttool export attachments --path "$RESULT" --output-path "$WORK/ekler" >/dev/null 2>&1; then
    python3 - "$WORK/ekler" "$OUT" <<'PY'
import json, os, re, shutil, sys
source, target = sys.argv[1], sys.argv[2]
with open(os.path.join(source, "manifest.json")) as handle:
    manifest = json.load(handle)
for test in manifest:
    for item in test.get("attachments", []):
        # "06-gorevler-kanban_0_<UUID>.png" -> "06-gorevler-kanban.png"
        name = re.sub(r"_\d+_[0-9A-Fa-f-]{36}(\.\w+)$", r"\1", item.get("suggestedHumanReadableName", ""))
        if re.match(r"\d\d-.*\.png$", name) or name == "atlananlar.txt":
            shutil.copyfile(os.path.join(source, item["exportedFileName"]), os.path.join(target, name))
        elif name.startswith("agac-") and name.endswith(".txt"):
            os.makedirs(os.path.join(target, "agac"), exist_ok=True)
            shutil.copyfile(os.path.join(source, item["exportedFileName"]), os.path.join(target, "agac", name[5:]))
PY
  fi
fi

count=$(find "$OUT" -maxdepth 1 -type f -name '[0-9][0-9]-*.png' | wc -l | tr -d ' ')
echo "Görüntü: $count"
if [ -s "$OUT/atlananlar.txt" ]; then
  echo "Atlanan: $(wc -l < "$OUT/atlananlar.txt" | tr -d ' ')"
  sed 's/^/  /' "$OUT/atlananlar.txt"
elif [ -f "$OUT/atlananlar.txt" ]; then
  echo "Atlanan: 0"
else
  echo "Tur tamamlanmadı: atlananlar.txt yazılmadı (xcodebuild çıkış kodu $status)" >&2
  [ "$status" -ne 0 ] || status=1
fi
[ "$count" -gt 0 ] || { echo "Hiç görüntü alınamadı" >&2; [ "$status" -ne 0 ] || status=1; }
exit "$status"
