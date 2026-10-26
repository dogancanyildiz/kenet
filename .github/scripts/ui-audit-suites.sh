#!/bin/sh
# iPhone arayüz testlerinde erişilebilirlik denetimi kümelerini listeler (satır başına bir ad).
# Kural: Tests/JournalUITests altında adı "AccessibilityUITests" ya da "AuditUITests" ile biten her
# sınıf denetim kümesidir. CI iki işte kullanır: denetim işi (app-iphone-audit) bu kümeleri
# -only-testing ile, akış işi (app-iphone-ui) aynı listeyi -skip-testing ile koşar; ad kuralına
# uymayan yeni küme akış işine düşer, hiçbir küme kaybolmaz. Bölme bir süre dengesidir, anlam
# ayrımı değil: denetim çağıran ama adı kurala uymayan kümeler (WeeklyReviewUITests,
# CloseDayUITests) akış işinde koşar. Kuralı test-ui-audit-suites.sh sınar.
# Yeni küme eklemek için başka dosyaya dokunmak gerekmez. Liste boşsa betik düşer: boş
# -only-testing listesi xcodebuild'e bütün testleri koşturur.
#   sh ui-audit-suites.sh [depo kökü]
set -eu
root=${1:-$(cd "$(dirname "$0")/../.." && pwd)}
list=$(cat "$root"/Tests/JournalUITests/*.swift 2>/dev/null \
  | grep -oE '^[[:space:]]*([A-Za-z@]+[[:space:]]+)*class[[:space:]]+[A-Za-z0-9_]+' \
  | awk '{print $NF}' | grep -E '(Accessibility|Audit)UITests$' | sort -u) || true
[ -n "$list" ] || { echo "arayüz denetim kümesi bulunamadı ($root/Tests/JournalUITests)" >&2; exit 1; }
echo "$list"
