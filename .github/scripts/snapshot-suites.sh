#!/bin/sh
# iOS'ta koşan ekran görüntüsü test kümelerini listeler (satır başına bir ad).
# Kural: Tests/JournalTests/Snapshots altında adı "SnapshotTests" ile biten her küme görüntü
# testidir; adı "MacSnapshotTests" ile bitenler yalnız macOS'ta derlenir ve burada sayılmaz.
# CI ve kayıt betiği bu listeyi kullanır; yeni küme eklemek için başka dosyaya dokunmak gerekmez.
set -eu
cd "$(dirname "$0")/../.."
grep -hoE '(struct|class) +[A-Za-z0-9_]+SnapshotTests\b' \
  Tests/JournalTests/Snapshots/*.swift \
  | awk '{print $NF}' | grep -v 'MacSnapshotTests$' | sort -u
