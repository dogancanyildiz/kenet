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
#   sh .github/scripts/testflight.sh --ci --keychain <yol> --api-key <.p8> --api-key-id <kimlik> \
#     --api-issuer <kimlik>                      CI'da (testflight.yml) onaysız arşivle ve yükle
#
# --ci kipi: Xcode hesabı ve Config/Local.xcconfig yerine App Store Connect API anahtarı ve
# çağıranın kurduğu anahtar zinciri kullanılır. Takım kimliği zincirdeki Apple Distribution
# kimliğinden okunur ve GitHub günlüğünde maskelenir; bırakılan günlüklerde takım, anahtar ve
# yayıncı kimliği yer tutucuyla değiştirilir (repo herkese açık). HEAD origin/dev geçmişinde
# olmalı ve kopya tam olmalı (yapı numarası commit sayısıdır).
#
# Koşullar: dal `dev` ve origin/dev ile aynı (TestFlight `dev`'den, mağaza `main`'den çıkar),
# Config/Local.xcconfig içinde takım kimliği var ve Xcode'da aynı Apple hesabıyla oturum açık.
# Çalışma klasöründeki commit'lenmemiş değişiklikler arşive girmez; betik bunları listeler. Yapı numarası commit sayısıdır: aynı commit'ten
# ikinci yükleme aynı numarayı alır ve reddedilir.
set -eu

MODE=upload
ASSUME_YES=0
CI_MODE=0
KEYCHAIN=
API_KEY=
API_KEY_ID=
API_ISSUER=
usage() {
  echo "$*" >&2
  exit 2
}
while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --yes) ASSUME_YES=1 ;;
    --ci) CI_MODE=1 ;;
    --keychain | --api-key | --api-key-id | --api-issuer)
      [ $# -ge 2 ] || usage "$1 bir değer ister."
      case "$1" in
        --keychain) KEYCHAIN=$2 ;;
        --api-key) API_KEY=$2 ;;
        --api-key-id) API_KEY_ID=$2 ;;
        --api-issuer) API_ISSUER=$2 ;;
      esac
      shift
      ;;
    *) usage "Bilinmeyen seçenek: $1" ;;
  esac
  shift
done

# Değerler hata iletisine yazılmaz: CI günlüğü herkese açıktır.
if [ "$CI_MODE" -eq 1 ]; then
  [ "$MODE" = upload ] || usage "--ci ile --check birlikte kullanılmaz."
  ASSUME_YES=1
  [ -n "$KEYCHAIN" ] && [ -n "$API_KEY" ] && [ -n "$API_KEY_ID" ] && [ -n "$API_ISSUER" ] ||
    usage "--ci için --keychain, --api-key, --api-key-id ve --api-issuer gerekir."
  [ -f "$KEYCHAIN" ] || usage "--keychain dosyası yok."
  [ -f "$API_KEY" ] || usage "--api-key dosyası yok."
  # Biçim denetimi günlük temizliğindeki sed kalıplarını da güvenli kılar.
  printf '%s' "$API_KEY_ID" | grep -Eqx '[A-Z0-9]{10}' || usage "--api-key-id 10 karakterlik büyük harf ve rakam olmalı."
  printf '%s' "$API_ISSUER" | grep -Eqx '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}' ||
    usage "--api-issuer UUID biçiminde olmalı."
elif [ -n "$KEYCHAIN$API_KEY$API_KEY_ID$API_ISSUER" ]; then
  usage "--keychain, --api-key, --api-key-id ve --api-issuer yalnız --ci ile kullanılır."
fi

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
TEAM=
if [ "$MODE" = upload ]; then
  [ "$BRANCH" = dev ] || fail "dal '$BRANCH'; TestFlight yüklemesi 'dev' dalından yapılır."
fi
if [ "$CI_MODE" -eq 1 ]; then
  [ "$(git rev-parse --is-shallow-repository)" = false ] ||
    fail "sığ kopya; yapı numarası commit sayısıdır, tam geçmiş gerekir (actions/checkout fetch-depth: 0)."
  # CI kopyası commit'lenmiş durumdur. Eşitlik değil soy aranır: kuyrukta bekleyen koşu başlarken
  # dev ilerlemiş olabilir; yüklenen commit yine dev'dendir.
  git fetch -q origin dev || fail "origin/dev alınamadı."
  git merge-base --is-ancestor HEAD origin/dev ||
    fail "HEAD origin/dev geçmişinde değil; TestFlight yalnız dev'deki bir commit'ten yüklenir."
  IDENTITIES=$(security find-identity -v -p codesigning "$KEYCHAIN") || fail "anahtar zinciri okunamadı."
  TEAM=$(printf '%s\n' "$IDENTITIES" | sed -n 's/.*"Apple Distribution: .*(\([A-Z0-9]\{10\}\))".*/\1/p' | head -1)
  [ -n "$TEAM" ] || fail "anahtar zincirinde geçerli Apple Distribution kimliği yok (DIST_CERT_P12)."
  # Maske, değer günlüğe ilk kez düşmeden önce verilir.
  [ "${GITHUB_ACTIONS:-}" != true ] || echo "::add-mask::$TEAM"
  printf '%s\n' "$IDENTITIES" | grep -q '"Apple Development: ' ||
    echo "Uyarı: anahtar zincirinde Apple Development kimliği yok; Xcode arşiv imzası için API anahtarıyla yeni bir geliştirme sertifikası oluşturabilir." >&2
elif [ "$MODE" = upload ]; then
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
# CI'da takım Local.xcconfig'den değil, derleme ayarı olarak gelir.
[ "$MODE" = check ] || [ "$CI_MODE" -eq 1 ] || cp Config/Local.xcconfig "$TREE/Config/Local.xcconfig"

# --ci kipinde bırakılan günlüklerden takım, anahtar ve yayıncı kimliği çıkarılır.
redact() {
  if [ "$CI_MODE" -eq 1 ]; then
    sed -e "s/$TEAM/XXXXXXXXXX/g" -e "s/$API_KEY_ID/ASC_KEY_ID/g" -e "s/$API_ISSUER/ASC_ISSUER_ID/g"
  else
    cat
  fi
}

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
if [ "$CI_MODE" -eq 1 ]; then
  set -- "$@" -authenticationKeyPath "$API_KEY" -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER" DEVELOPMENT_TEAM="$TEAM"
fi
if ! xcodebuild archive -project Journal.xcodeproj -scheme Journal_iOS \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -derivedDataPath "$WORK/DerivedData" "$@" >"$LOG" 2>&1; then
  grep -E "error:|ARCHIVE FAILED" "$LOG" | head -20 | redact >&2
  KEEP="${TMPDIR:-/tmp}/kenet-testflight-arsiv.log"
  redact <"$LOG" >"$KEEP"
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
IPAD_ORIENTATIONS=$(plist "UISupportedInterfaceOrientations~ipad" | grep -c UIInterfaceOrientation)

echo "Ad:            $(plist CFBundleDisplayName)"
echo "Kimlik:        $BUNDLE_ID"
echo "Sürüm (yapı):  $VERSION ($BUILD)"
echo "Cihaz ailesi:  $FAMILY (iPad yönü: $IPAD_ORIENTATIONS)"
echo "Şifreleme:     ITSAppUsesNonExemptEncryption=$(plist ITSAppUsesNonExemptEncryption)"
echo "Belge paylaşımı: UIFileSharingEnabled=$(plist UIFileSharingEnabled) LSSupportsOpeningDocumentsInPlace=$(plist LSSupportsOpeningDocumentsInPlace)"

[ "$BUNDLE_ID" = "$EXPECTED_ID" ] || fail "kimlik '$BUNDLE_ID', beklenen '$EXPECTED_ID'."
[ "$VERSION" = "$(cat "$TREE/VERSION")" ] || fail "sürüm '$VERSION', VERSION dosyası '$(cat "$TREE/VERSION")'."
[ "$BUILD" = "$(git rev-list --count HEAD)" ] || fail "yapı numarası '$BUILD', commit sayısı '$(git rev-list --count HEAD)'."
[ "$FAMILY" = "Array{12}" ] || fail "cihaz ailesi iPhone ve iPad olmalı (PlistBuddy çıktısı sıkıştırılmış: Array{12}), bulunan: $FAMILY."
[ "$IPAD_ORIENTATIONS" = 4 ] || fail "iPad dört yöne dönmeli (UISupportedInterfaceOrientations~ipad), bulunan yön sayısı: $IPAD_ORIENTATIONS."
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
set -- -allowProvisioningUpdates
if [ "$CI_MODE" -eq 1 ]; then
  set -- "$@" -authenticationKeyPath "$API_KEY" -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER"
fi
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath "$WORK/cikti" "$@" >"$UPLOAD_LOG" 2>&1; then
  grep -E "error:|Error|EXPORT FAILED" "$UPLOAD_LOG" | head -20 | redact >&2
  KEEP="${TMPDIR:-/tmp}/kenet-testflight-yukleme.log"
  redact <"$UPLOAD_LOG" >"$KEEP"
  fail "yükleme başarısız; günlük: $KEEP"
fi
echo "Yüklendi: Kenet $VERSION ($BUILD). İşlenmesi birkaç dakika sürer; TestFlight kendiliğinden günceller."
if [ "$CI_MODE" -eq 1 ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
  printf 'version=%s\nbuild=%s\n' "$VERSION" "$BUILD" >>"$GITHUB_OUTPUT"
fi
