#!/bin/sh
# Belgeler yalnızca docs/ altında durur (AGENTS.md, belge kuralları). Kök dizindeki üç dosya
# ve Fixtures/ altındaki test verileri dışında izlenen .md dosyası olmamalıdır.
set -eu

unexpected=$(git ls-files '*.md' | grep -vE '^(docs/|Fixtures/|README\.md$|AGENTS\.md$|CLAUDE\.md$)' || true)

if [ -n "$unexpected" ]; then
    echo "docs/ dışında belge bulundu:"
    echo "$unexpected"
    exit 1
fi

echo "Belgelerin yeri uygun."
