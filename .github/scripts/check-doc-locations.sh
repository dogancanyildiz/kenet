#!/bin/sh
# Belgeler yalnızca docs/ altında durur (AGENTS.md, belge kuralları). Kök dizindeki üç dosya
# ve Fixtures/ altındaki test verileri dışında izlenen .md dosyası olmamalıdır.
set -eu

# git başarısız olursa betik burada durur; sessizce "uygun" demez.
# core.quotepath kapalı: ASCII dışı dosya adları tırnaklanmadan yazılır.
files=$(git -c core.quotepath=off ls-files '*.md')

if [ -z "$files" ]; then
    echo "İzlenen .md dosyası bulunamadı; git çıktısı boş."
    exit 1
fi

unexpected=$(printf '%s\n' "$files" | grep -vE '^(docs/|Fixtures/|README\.md$|AGENTS\.md$|CLAUDE\.md$)' || true)

if [ -n "$unexpected" ]; then
    echo "docs/ dışında belge bulundu:"
    echo "$unexpected"
    exit 1
fi

echo "Belgelerin yeri uygun ($(printf '%s\n' "$files" | wc -l | tr -d ' ') dosya denetlendi)."
