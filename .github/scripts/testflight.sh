#!/bin/sh
# TestFlight'a (dahili test) yapı yükler: temiz bir kopyadan arşiv alır ve App Store Connect'e gönderir.
#
# Neden temiz kopya: Xcode açıkken çalışma klasöründeki dosyaları (String Catalog, plist ekleri)
# kendiliğinden yeniden yazabiliyor; arşiv o halleriyle alınırsa yüklenen yapı depodaki kodla
# aynı olmaz. Betik HEAD'i geçici bir worktree'ye çıkarır ve yalnız oradan derler.
# Arşiv ve DerivedData aynı geçici klasörde tutulur; --check dahil başarı ve hata çıkışlarında
# mevcut temizlik tuzağı bunları kaldırır. Kullanıcının Xcode DerivedData klasörlerine dokunulmaz.
#
# Kullanım:
#   sh .github/scripts/testflight.sh            arşivle, özeti göster, onay alınca yükle
#   sh .github/scripts/testflight.sh --yes      onay sormadan yükle
#   sh .github/scripts/testflight.sh --check    imzasız arşivle ve içini denetle; yükleme yok
#
# Koşullar: dal `dev` ve origin/dev ile aynı (TestFlight `dev`'den, mağaza `main`'den çıkar),
# Config/Local.xcconfig içinde takım kimliği var ve Xcode'da aynı Apple hesabıyla oturum açık.
# Çalışma klasöründeki commit'lenmemiş değişiklikler arşive girmez; betik bunları listeler. Yapı numarası commit sayısıdır: aynı commit'ten
# ikinci yükleme aynı numarayı alır ve reddedilir.
set -eu

MODE=upload
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --check) MODE=check ;;
    --yes) ASSUME_YES=1 ;;
    *)
      echo "Bilinmeyen seçenek: $arg" >&2
      exit 2
      ;;
  esac
done

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

fail() {
  echo "Hata: $*" >&2
  exit 1
}

command -v xcodegen >/dev/null 2>&1 || fail "xcodegen bulunamadı (brew install xcodegen)."

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$MODE" = upload ]; then
  [ "$BRANCH" = dev ] || fail "dal '$BRANCH'; TestFlight yüklemesi 'dev' dalından yapılır."
  # İzlenen dosyalardaki değişiklik arşive girmez (temiz kopya HEAD'den çıkar). Xcode açıkken bazı
  # dosyaları sürekli yeniden yazdığı için bu durum yüklemeyi durdurmaz; yalnız söylenir.
  DIRTY=$(git status --porcelain --untracked-files=no)
  if [ -n "$DIRTY" ]; then
    echo "Uyarı: çalışma klasöründe commit'lenmemiş değişiklik var; arşive GİRMEYECEK:" >&2
    echo "$DIRTY" >&2
    echo "Bunlar Xcode'un kendi yazdıkları değilse önce commit'le ve birleştir." >&2
  fi
  git fetch -q origin dev 2>/dev/null || echo "Uyarı: origin/dev alınamadı; yerel dev kullanılıyor." >&2
  if git rev-parse -q --verify origin/dev >/dev/null 2>&1; then
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/dev)" ] ||
      fail "yerel dev, origin/dev ile aynı değil; önce 'git pull --ff-only' (ya da push)."
  fi
  [ -f Config/Local.xcconfig ] || fail "Config/Local.xcconfig yok (örnek: Config/Local.xcconfig.example)."
  TEAM=$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([A-Z0-9]\{10\}\)[[:space:]]*$/\1/p' Config/Local.xcconfig | head -1)
  [ -n "$TEAM" ] || fail "Config/Local.xcconfig içinde 10 karakterlik DEVELOPMENT_TEAM bulunamadı."
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/kenet-testflight.XXXXXX")
TREE="$WORK/kaynak"
cleanup() {
  git -C "$ROOT" worktree remove --force "$TREE" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT INT TERM

git worktree add -q --detach "$TREE" HEAD
[ "$MODE" = check ] || cp Config/Local.xcconfig "$TREE/Config/Local.xcconfig"

cd "$TREE"
xcodegen generate >/dev/null
ARCHIVE="$WORK/Kenet.xcarchive"
LOG="$WORK/arsiv.log"
echo "Arşivleniyor ($(git rev-parse --short HEAD))…"
if [ "$MODE" = check ]; then
  set -- CODE_SIGNING_ALLOWED=NO
else
  set -- -allowProvisioningUpdates
fi
if ! xcodebuild archive -project Journal.xcodeproj -scheme Journal_iOS \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -derivedDataPath "$WORK/DerivedData" "$@" >"$LOG" 2>&1; then
  grep -E "error:|ARCHIVE FAILED" "$LOG" | head -20 >&2
  KEEP="${TMPDIR:-/tmp}/kenet-testflight-arsiv.log"
  cp "$LOG" "$KEEP"
  fail "arşiv alınamadı; günlük: $KEEP"
fi

APP=$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || fail "arşivde uygulama bulunamadı."
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Info.plist" 2>/dev/null || echo "?"; }
EXPECTED_ID=$(sed -n 's/^[[:space:]]*APP_BUNDLE_IDENTIFIER:[[:space:]]*//p' "$TREE/project.yml" | head -1)
BUNDLE_ID=$(plist CFBundleIdentifier)
VERSION=$(plist CFBundleShortVersionString)
BUILD=$(plist CFBundleVersion)
FAMILY=$(plist UIDeviceFamily | tr -d ' \n')

echo "Ad:            $(plist CFBundleDisplayName)"
echo "Kimlik:        $BUNDLE_ID"
echo "Sürüm (yapı):  $VERSION ($BUILD)"
echo "Cihaz ailesi:  $FAMILY"
echo "Şifreleme:     ITSAppUsesNonExemptEncryption=$(plist ITSAppUsesNonExemptEncryption)"
echo "Belge paylaşımı: UIFileSharingEnabled=$(plist UIFileSharingEnabled) LSSupportsOpeningDocumentsInPlace=$(plist LSSupportsOpeningDocumentsInPlace)"

[ "$BUNDLE_ID" = "$EXPECTED_ID" ] || fail "kimlik '$BUNDLE_ID', beklenen '$EXPECTED_ID'."
[ "$VERSION" = "$(cat "$TREE/VERSION")" ] || fail "sürüm '$VERSION', VERSION dosyası '$(cat "$TREE/VERSION")'."
[ "$BUILD" = "$(git rev-list --count HEAD)" ] || fail "yapı numarası '$BUILD', commit sayısı '$(git rev-list --count HEAD)'."
[ "$FAMILY" = "Array{1}" ] || fail "cihaz ailesi yalnız iPhone olmalı, bulunan: $FAMILY."
[ -f "$APP/PrivacyInfo.xcprivacy" ] || fail "PrivacyInfo.xcprivacy pakette yok."
[ "$(plist LSSupportsOpeningDocumentsInPlace)" = true ] || fail "LSSupportsOpeningDocumentsInPlace pakette yok."

if [ "$MODE" = check ]; then
  echo "Denetim geçti (imzasız arşiv; yükleme yapılmadı)."
  exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  printf '%s' "Kenet $VERSION ($BUILD) TestFlight'a (dahili test) yüklensin mi? [e/H] "
  read -r answer
  case "$answer" in
    e | E | evet | Evet) ;;
    *)
      echo "Vazgeçildi; yükleme yapılmadı."
      exit 0
      ;;
  esac
fi

OPTIONS="$WORK/ExportOptions.plist"
cat >"$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>teamID</key>
	<string>$TEAM</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>testFlightInternalTestingOnly</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
EOF

echo "Yükleniyor…"
UPLOAD_LOG="$WORK/yukleme.log"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath "$WORK/cikti" -allowProvisioningUpdates >"$UPLOAD_LOG" 2>&1; then
  grep -E "error:|Error|EXPORT FAILED" "$UPLOAD_LOG" | head -20 >&2
  KEEP="${TMPDIR:-/tmp}/kenet-testflight-yukleme.log"
  cp "$UPLOAD_LOG" "$KEEP"
  fail "yükleme başarısız; günlük: $KEEP"
fi
echo "Yüklendi: Kenet $VERSION ($BUILD). İşlenmesi birkaç dakika sürer; TestFlight kendiliğinden günceller."
