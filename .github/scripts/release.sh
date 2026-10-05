#!/bin/sh
# Sürüm kararı: VERSION dosyasındaki numarayla vX.Y.Z etiketini ve GitHub Release'i oluşturur.
# Etiket zaten varsa atlar; etiket başka bir commit'teyse (VERSION yükseltilmemiş) bunu uyarıyla söyler.
# DRY_RUN=1 ise yalnız kararı yazar, hiçbir şey oluşturmaz.
set -eu

version=$(tr -d '[:space:]' < VERSION)
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
  echo "VERSION geçersiz: '$version'"
  exit 1
}
tag="v$version"
sha=${GITHUB_SHA:-$(git rev-parse HEAD)}

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  tagged=$(git rev-parse "refs/tags/$tag^{commit}")
  if [ "$tagged" != "$sha" ]; then
    echo "::warning::$tag başka bir commit'te ($tagged) zaten var. VERSION yükseltilmediği için bu birleştirme sürümsüz kaldı."
  fi
  echo "karar: atla ($tag zaten var)"
  exit 0
fi

# Etiketi olmayan bir Release (taslak) kalmış olabilir; yalnız GitHub'a erişim varken bakılır.
if [ -n "${GH_TOKEN:-}" ] && gh release view "$tag" >/dev/null 2>&1; then
  echo "karar: atla ($tag için Release zaten var)"
  exit 0
fi

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "karar: oluştur ($tag, hedef $sha); kuru koşu, hiçbir şey oluşturulmadı"
  exit 0
fi

gh release create "$tag" --target "$sha" --title "$tag" --generate-notes
echo "$tag oluşturuldu."
