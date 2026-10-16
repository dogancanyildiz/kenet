#!/bin/sh
# Ekran görüntüsü test kümelerini listeler (satır başına bir ad).
# Kural: Tests/JournalTests/Snapshots altında adı "SnapshotTests" ile biten her küme görüntü
# testidir. Adı "MacSnapshotTests" ile bitenler yalnız macOS'ta derlenir. Adı "DuoSnapshotTests"
# ile bitenler iPhone Duo tuvallerini çizer (SnapshotSupport.swift: ShellCanvas). Adı "Pad" ile
# başlayanlar iPad tuvallerini çizer ve yalnız iPad simülatöründe koşar (iPhone'da kendini atlar).
#   sh snapshot-suites.sh        iOS kümeleri (CI'da kapı; kayıt betiği bunları kaydeder)
#   sh snapshot-suites.sh --mac  Mac kümeleri (yalnız yerelde koşar: çizim macOS sürümüne,
#                                ekran ölçeğine ve sistem görünümüne bağlı; CI atlar)
#   sh snapshot-suites.sh --duo  Duo kümeleri (henüz CI kapısı değil; varsayılan listeye girmez;
#                                kayıt: record-screen-snapshots.sh --duo)
#   sh snapshot-suites.sh --pad  iPad kümeleri (CI'da ikinci simülatörde kapı; varsayılan listeye
#                                girmez; kayıt: record-screen-snapshots.sh --pad)
# Yeni küme eklemek için başka dosyaya dokunmak gerekmez.
set -eu
cd "$(dirname "$0")/../.."
all=$(grep -hoE '(struct|class) +[A-Za-z0-9_]+SnapshotTests\b' \
  Tests/JournalTests/Snapshots/*.swift | awk '{print $NF}' | sort -u)
case "${1:-}" in
  --mac) echo "$all" | grep 'MacSnapshotTests$' || true ;;
  --duo) echo "$all" | grep 'DuoSnapshotTests$' || true ;;
  --pad) echo "$all" | grep '^Pad' || true ;;
  *) echo "$all" | grep -v -e 'MacSnapshotTests$' -e 'DuoSnapshotTests$' -e '^Pad' || true ;;
esac
