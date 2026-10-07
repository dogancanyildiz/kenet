#!/bin/sh
# Ekran görüntüsü test kümelerini listeler (satır başına bir ad).
# Kural: Tests/JournalTests/Snapshots altında adı "SnapshotTests" ile biten her küme görüntü
# testidir. Adı "MacSnapshotTests" ile bitenler yalnız macOS'ta derlenir.
#   sh snapshot-suites.sh        iOS kümeleri (CI'da kapı; kayıt betiği bunları kaydeder)
#   sh snapshot-suites.sh --mac  Mac kümeleri (yalnız yerelde koşar: çizim macOS sürümüne,
#                                ekran ölçeğine ve sistem görünümüne bağlı; CI atlar)
# Yeni küme eklemek için başka dosyaya dokunmak gerekmez.
set -eu
cd "$(dirname "$0")/../.."
all=$(grep -hoE '(struct|class) +[A-Za-z0-9_]+SnapshotTests\b' \
  Tests/JournalTests/Snapshots/*.swift | awk '{print $NF}' | sort -u)
if [ "${1:-}" = "--mac" ]; then
  echo "$all" | grep 'MacSnapshotTests$' || true
else
  echo "$all" | grep -v 'MacSnapshotTests$' || true
fi
