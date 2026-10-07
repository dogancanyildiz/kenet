#!/bin/sh
# release.sh kararlarını geçici bir depoda kuru koşuyla sınar: yeni sürüm oluşturulur,
# var olan etiket atlanır, yükseltilmemiş VERSION uyarı verir, geçersiz VERSION düşer.
set -eu

script="$(cd "$(dirname "$0")" && pwd)/release.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

git init -q .
commit() {
  git add -A
  git -c user.name=test -c user.email=test@example.invalid commit -q -m "$1"
}
decide() {
  env -u GH_TOKEN DRY_RUN=1 GITHUB_SHA="$(git rev-parse HEAD)" sh "$script" 2>&1
}
expect() {
  # $1: ad, $2: beklenen parça, $3: çıktı
  case "$3" in
    *"$2"*) echo "geçti: $1" ;;
    *)
      echo "DÜŞTÜ: $1"
      echo "  beklenen parça: $2"
      echo "  çıktı: $3"
      exit 1
      ;;
  esac
}

echo "0.1.0" > VERSION
commit "ilk sürüm"
expect "yeni sürüm oluşturulur" "karar: oluştur (v0.1.0" "$(decide)"
[ -z "$(git tag)" ] || { echo "DÜŞTÜ: kuru koşu etiket oluşturdu"; exit 1; }

git tag v0.1.0
out=$(decide)
expect "aynı commit'teki etiket atlanır" "karar: atla (v0.1.0 zaten var)" "$out"
case "$out" in *"::warning::"*) echo "DÜŞTÜ: aynı commit'te uyarı verildi"; exit 1 ;; esac

echo "değişiklik" > note.txt
commit "VERSION yükseltilmeden birleştirme"
out=$(decide)
expect "yükseltilmemiş VERSION uyarı verir" "::warning::v0.1.0 başka bir commit'te" "$out"
expect "yükseltilmemiş VERSION atlanır" "karar: atla (v0.1.0 zaten var)" "$out"

echo "0.1.1" > VERSION
commit "yama sürümü"
expect "yükseltilen VERSION oluşturulur" "karar: oluştur (v0.1.1" "$(decide)"

echo "1.0" > VERSION
if out=$(decide); then
  echo "DÜŞTÜ: geçersiz VERSION kabul edildi: $out"
  exit 1
fi
expect "geçersiz VERSION düşer" "VERSION geçersiz" "$out"
