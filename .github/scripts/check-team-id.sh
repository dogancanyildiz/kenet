#!/bin/sh
# Belgelerde gerçek takım kimliği (DEVELOPMENT_TEAM) olmamalı. Aynı kuralı uygulama testi de
# sınar (ReleaseConfigurationTests.teamIdentifierStaysOutOfTheRepository); bu betik, yalnız belge
# değiştiren PR'larda uygulama işleri atlandığı için kuralı "Biçim ve kurallar" işinde de tutar.
# Kapsam: CI'ın belge saydığı dosyalar (.github/scripts/ci-changes.py ile aynı liste).
set -eu
cd "$(dirname "$0")/../.."

files=$(git -c core.quotepath=off ls-files -- docs LICENSE ':(glob)*.md')
if [ -z "$files" ]; then
    echo "Denetlenecek belge bulunamadı; git çıktısı boş."
    exit 1
fi

pattern='DEVELOPMENT_TEAM[[:space:]]*[=:][[:space:]]*"?[A-Za-z0-9]{10}([^A-Za-z0-9_]|$)'
# -o: her eşleşme ayrı satır; yer tutucu (Config/Local.xcconfig.example ile aynı) serbesttir.
hits=$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -onE "$pattern" /dev/null \
    | grep -vE '[=:][[:space:]]*"?XXXXXXXXXX([^A-Za-z0-9_]|$)' || true)

if [ -n "$hits" ]; then
    echo "Belgede gerçek takım kimliği var:"
    printf '%s\n' "$hits" | cut -d: -f1,2
    exit 1
fi

echo "Belgelerde takım kimliği yok ($(printf '%s\n' "$files" | wc -l | tr -d ' ') dosya denetlendi)."
