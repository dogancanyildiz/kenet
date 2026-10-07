#!/bin/sh
# Yapı numarası (CFBundleVersion): HEAD'e kadar olan commit sayısı. Derlemedeki "Sürümü yaz" betiği
# çağırır (project.yml). Git yoksa, klasör depo değilse ya da kopya sığsa (sayı eksik çıkar) hiçbir
# şey yazmaz ve 1 ile çıkar; çağıran yedek değeri korur.
# Kullanım: sh .github/scripts/build-number.sh [depo kökü]
set -eu
root=${1:-$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)}
command -v git >/dev/null 2>&1 || exit 1
[ "$(git -C "$root" rev-parse --is-shallow-repository 2>/dev/null || echo true)" = false ] || exit 1
count=$(git -C "$root" rev-list --count HEAD 2>/dev/null) || exit 1
case "$count" in
  '' | *[!0-9]*) exit 1 ;;
esac
echo "$count"
