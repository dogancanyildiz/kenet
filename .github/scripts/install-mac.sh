#!/bin/sh
# Mac uygulamasını bu makineye kurar: HEAD'in temiz bir kopyasından Release derler ve
# /Applications/Kenet.app olarak kopyalar.
#
# Mac için TestFlight ya da mağaza yolu yok (uygulama mağazada yalnız iPhone); Mac sürümü bu
# betikle, derlendiği makineye kurulur. Geliştirici imzasıyla imzalanır ve Apple onayından
# (notarization) geçmez: başka bir Mac'e kopyalanırsa Gatekeeper engeller.
#
# Neden temiz kopya: testflight.sh ile aynı gerekçe (Xcode açıkken çalışma klasöründeki dosyaları
# yeniden yazabiliyor). Commit'lenmemiş değişiklikler kurulan uygulamaya girmez; betik listeler.
# Derleme çıktıları geçici klasörde tutulur ve çıkışta silinir.
#
# Kullanım:
#   sh .github/scripts/install-mac.sh
#
# Koşullar: Config/Local.xcconfig içinde takım kimliği var ve Xcode'da aynı Apple hesabıyla oturum
# açık. Kenet açıksa önce kapatılır (betik kapatmaz, durur).
set -eu

[ "$#" -eq 0 ] || {
  echo "Bilinmeyen seçenek: $1" >&2
  exit 2
}

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
TARGET=/Applications/Kenet.app

fail() {
  echo "Hata: $*" >&2
  exit 1
}

command -v xcodegen >/dev/null 2>&1 || fail "xcodegen bulunamadı (brew install xcodegen)."
[ -f Config/Local.xcconfig ] || fail "Config/Local.xcconfig yok (örnek: Config/Local.xcconfig.example)."
EXPECTED_ID=$(sed -n 's/^[[:space:]]*APP_BUNDLE_IDENTIFIER:[[:space:]]*//p' project.yml | head -1)
[ -n "$EXPECTED_ID" ] || fail "project.yml içinde APP_BUNDLE_IDENTIFIER bulunamadı."

bundle_id() { /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true; }

# Yerinde başka bir uygulama duruyorsa üstüne yazılmaz.
if [ -e "$TARGET" ]; then
  [ "$(bundle_id "$TARGET")" = "$EXPECTED_ID" ] ||
    fail "$TARGET başka bir uygulama (kimlik '$(bundle_id "$TARGET")'); üstüne yazılmadı."
fi
if lsappinfo list 2>/dev/null | grep -q "bundleID=\"$EXPECTED_ID\""; then
  fail "Kenet açık; kapatıp yeniden çalıştır."
fi

DIRTY=$(git status --porcelain --untracked-files=no)
if [ -n "$DIRTY" ]; then
  echo "Uyarı: çalışma klasöründe commit'lenmemiş değişiklik var; kurulan uygulamaya GİRMEYECEK:" >&2
  echo "$DIRTY" >&2
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/kenet-mac.XXXXXX")
TREE="$WORK/kaynak"
cleanup() {
  git -C "$ROOT" worktree remove --force "$TREE" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

git worktree add -q --detach "$TREE" HEAD
cp Config/Local.xcconfig "$TREE/Config/Local.xcconfig"

cd "$TREE"
xcodegen generate >/dev/null
LOG="$WORK/derleme.log"
echo "Derleniyor ($(git rev-parse --short HEAD))…"
if ! xcodebuild build -project Journal.xcodeproj -scheme Journal_macOS -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$WORK/DerivedData" \
  -allowProvisioningUpdates >"$LOG" 2>&1; then
  grep -E "error:|BUILD FAILED" "$LOG" | head -20 >&2
  KEEP="${TMPDIR:-/tmp}/kenet-mac-derleme.log"
  cp "$LOG" "$KEEP"
  fail "derlenemedi; günlük: $KEEP"
fi

APP=$(find "$WORK/DerivedData/Build/Products/Release" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || fail "derleme çıktısında uygulama bulunamadı."
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || echo "?"; }
VERSION=$(plist CFBundleShortVersionString)
BUILD=$(plist CFBundleVersion)

[ "$(bundle_id "$APP")" = "$EXPECTED_ID" ] || fail "kimlik '$(bundle_id "$APP")', beklenen '$EXPECTED_ID'."
[ "$VERSION" = "$(cat "$TREE/VERSION")" ] || fail "sürüm '$VERSION', VERSION dosyası '$(cat "$TREE/VERSION")'."
codesign --verify --deep --strict "$APP" 2>/dev/null || fail "imza doğrulanamadı."

rm -rf "$TARGET"
ditto "$APP" "$TARGET"
codesign --verify --deep --strict "$TARGET" 2>/dev/null || fail "kopyalanan uygulamanın imzası doğrulanamadı."
echo "Kuruldu: Kenet $VERSION ($BUILD) → $TARGET"
