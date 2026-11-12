#!/bin/sh
# Yapı numarası (CFBundleVersion): HEAD commit'inin UTC işlenme zamanı, "YYAAGG.SSDDss" biçiminde
# iki tamsayı (örnek: 261111.153012 = 2026-11-11 15:30:12 UTC; ikinci parça baştaki sıfırsız).
# Derlemedeki "Sürümü yaz" betiği çağırır (project.yml).
# Neden zaman, commit sayısı değil: main dev'in atası değildir; sürüm birleşmesinin commit sayısına
# dev birkaç commit sonra yine ulaşır ve aynı VERSION'da iki yapı aynı numarayı alır. GitHub'daki
# birleşmeler (squash ve merge commit) işlenme zamanını birleşme anı yapar: iki daldaki her yeni
# commit öncekilerden büyük numara alır. Eski sayı en çok 385'ti; bu numaranın ilk parçası
# 261002'den (deponun ilk günü) küçük olamaz. Sığ kopyada da çalışır.
# Git yoksa ya da klasör depo değilse hiçbir şey yazmaz ve 1 ile çıkar; çağıran yedek değeri korur.
# Kullanım: sh .github/scripts/build-number.sh [depo kökü]
set -eu
root=${1:-$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)}
command -v git >/dev/null 2>&1 || exit 1
stamp=$(TZ=UTC0 git -C "$root" log -1 --date='format-local:%y%m%d %H%M%S' --format=%cd HEAD 2>/dev/null) || exit 1
day=${stamp% *}
time=${stamp#* }
case "$day$time" in
  '' | *[!0-9]*) exit 1 ;;
esac
[ ${#day} -eq 6 ] && [ ${#time} -eq 6 ] || exit 1
# Baştaki sıfırlar atılır: bileşen düz tamsayı olsun (000501 -> 501, 000000 -> 0).
time=$(printf '%s\n' "$time" | sed 's/^0*//')
echo "$day.${time:-0}"
