#!/bin/sh
# Saat dilimine duyarlı uygulama test kümelerini listeler (satır başına bir ad).
# Kural: Tests/JournalTests altında saat dilimi, takvim ya da "bugün" hesabına dokunan her dosyanın
# üst düzey kümesi listeye girer; iç içe kümeler üst kümeyle koşar. PR'daki ikinci saat dilimi
# koşusu (TZ=Pacific/Auckland) yalnız bu kümeleri koşar; dev'e itmede bütün kümeler koşar.
# Yeni küme eklemek için başka dosyaya dokunmak gerekmez.
set -eu
cd "$(dirname "$0")/../.."
pattern='TimeZone|Calendar\.current|Calendar\(identifier|startOfDay|CalendarDate\.today|\.today\('
list=$(grep -lE "$pattern" Tests/JournalTests/*.swift \
  | xargs grep -hoE '^(struct|final class|class) +[A-Za-z0-9_]+' | awk '{print $NF}' | sort -u)
[ -n "$list" ] || { echo "saat dilimi kümesi bulunamadı" >&2; exit 1; }
echo "$list"
