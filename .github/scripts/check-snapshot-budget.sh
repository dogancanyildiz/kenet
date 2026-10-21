#!/bin/sh
# Görüntü referansı tavanı (karar 61): Tests/**/__Snapshots__/**/*.png en çok MAX_COUNT dosya ve
# MAX_MB MiB olabilir. Her referans git geçmişine ebediyen girer (815 blob, 132 MB ölçüldü);
# tavan, yeni vakanın bedelini görünür kılar. Tavan 2026-10-21 ölçümü: 261 dosya, 50,8 MiB;
# dosya 300, boyut bugünkü +%20 (61 MiB). Aşınca listeyle düşer.
# Kullanım: sh .github/scripts/check-snapshot-budget.sh [kök]   (SNAPSHOT_MAX_COUNT, SNAPSHOT_MAX_MB)
set -eu
ROOT="${1:-$(dirname "$0")/../..}"
MAX_COUNT="${SNAPSHOT_MAX_COUNT:-300}"
MAX_MB="${SNAPSHOT_MAX_MB:-61}"

[ -d "$ROOT/Tests" ] || { echo "Tests klasörü bulunamadı: $ROOT" >&2; exit 1; }

list=$(find "$ROOT/Tests" -type f -name '*.png' -path '*/__Snapshots__/*' | sort)
if [ -z "$list" ]; then
  count=0
  bytes=0
else
  count=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
  bytes=$(printf '%s\n' "$list" | while IFS= read -r f; do wc -c < "$f"; done | awk '{s+=$1} END {print s+0}')
fi
max_bytes=$((MAX_MB * 1024 * 1024))
mb=$(awk -v b="$bytes" 'BEGIN {printf "%.1f", b/1048576}')

fail=0
if [ "$count" -gt "$MAX_COUNT" ]; then
  echo "Görüntü referansı sayısı tavanı aştı: $count > $MAX_COUNT"
  fail=1
fi
if [ "$bytes" -gt "$max_bytes" ]; then
  echo "Görüntü referansı boyutu tavanı aştı: $mb MiB > $MAX_MB MiB"
  fail=1
fi
if [ "$fail" -ne 0 ]; then
  echo "Referanslar (boyut bayt, büyükten küçüğe, ilk 30):"
  printf '%s\n' "$list" | while IFS= read -r f; do printf '%s %s\n' "$(wc -c < "$f" | tr -d ' ')" "$f"; done | sort -rn | head -30
  echo "Yeni vaka eklerken açık/koyu/AX3 üçlüsünü yalnız temsilci kümelerde tut (docs/architecture.md)."
  exit 1
fi
echo "Görüntü referansı tavanı uygun ($count/$MAX_COUNT dosya, $mb/$MAX_MB MiB)."
