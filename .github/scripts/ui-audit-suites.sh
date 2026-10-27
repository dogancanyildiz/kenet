#!/bin/sh
# Arayüz testlerinde erişilebilirlik denetimi kümelerini listeler (satır başına bir ad).
# Kural: Tests/JournalUITests altında (alt klasörler dahil) adı "AccessibilityUITests" ya da
# "AuditUITests" ile biten her sınıf denetim kümesidir. Sınıf bildirimi satır başında olur; önünde
# değiştiriciler ve parantezli öznitelikler (`@available(iOS 26, *) final class …`) bulunabilir.
# Üç kip:
#   (kipsiz)   bütün denetim kümeleri; akış işi (app-iphone-ui) bu listeyi -skip-testing ile koşar.
#   --iphone   ortak küme dışındakiler; iPhone denetim işi (app-iphone-audit) -only-testing ile koşar.
#   --shared   iPad işinin (app-ipad) de koştuğu ortak küme; iPhone denetim işi onu atlar, iPad işi
#              -only-testing ile koşar. Aynı ekranlar iPad'de bölünmüş kabukta denetlenir; iPhone'da
#              yinelemek denetim işine ~6 dk ekliyordu (koşu 40427534859: 6 vaka 370 sn).
# Ad kuralına uymayan yeni küme akış işine düşer, hiçbir küme kaybolmaz. Bölme bir süre dengesidir,
# anlam ayrımı değil: denetim çağıran ama adı kurala uymayan kümeler (WeeklyReviewUITests,
# CloseDayUITests) akış işinde koşar. Kuralı test-ui-audit-suites.sh sınar.
# Yeni küme eklemek için başka dosyaya dokunmak gerekmez. Liste boşsa betik düşer: boş
# -only-testing listesi xcodebuild'e bütün testleri koşturur, var olmayan ad hiçbir şey koşturmaz.
#   sh ui-audit-suites.sh [--iphone|--shared] [depo kökü]
set -eu
mode=all
case ${1:-} in
  --iphone | --shared) mode=${1#--}; shift ;;
  --*) echo "bilinmeyen kip: $1 (--iphone ya da --shared)" >&2; exit 2 ;;
esac
root=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
# iPad işinin de koştuğu ortak kümeler (boşlukla ayrılır).
shared="AccessibilityAuditUITests"
list=$(find "$root/Tests/JournalUITests" -type f -name '*.swift' -exec cat {} + 2>/dev/null \
  | grep -oE '^[[:space:]]*((@[A-Za-z]+(\([^)]*\))?|[A-Za-z]+)[[:space:]]+)*class[[:space:]]+[A-Za-z0-9_]+' \
  | awk '{print $NF}' | grep -E '(Accessibility|Audit)UITests$' | sort -u) || true
[ -n "$list" ] || { echo "arayüz denetim kümesi bulunamadı ($root/Tests/JournalUITests)" >&2; exit 1; }
shared_patterns=
for name in $shared; do shared_patterns="$shared_patterns -e $name"; done
case $mode in
  shared) list=$(printf '%s\n' "$list" | grep -xF $shared_patterns) \
    || { echo "ortak denetim kümesi yok ($shared; $root/Tests/JournalUITests)" >&2; exit 1; } ;;
  iphone) list=$(printf '%s\n' "$list" | grep -vxF $shared_patterns) \
    || { echo "ortak küme dışında denetim kümesi yok ($root/Tests/JournalUITests)" >&2; exit 1; } ;;
esac
echo "$list"
