#!/bin/sh
# check-snapshot-budget.sh testi: sahte klasörle uygun, sayı aşımı, boyut aşımı ve boş durum.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

run() { # ad beklenen-çıkış kök [ortam...]
  name=$1; want=$2; root=$3; shift 3
  set +e
  out=$(env "$@" sh "$here/check-snapshot-budget.sh" "$root" 2>&1)
  got=$?
  set -e
  if [ "$got" -ne "$want" ]; then
    echo "DÜŞTÜ: $name (çıkış $got, beklenen $want)"; echo "$out"; fails=$((fails + 1))
  else
    echo "geçti: $name"
  fi
  LAST=$out
}

mk() { # kök sayı bayt
  d="$1/Tests/JournalTests/Snapshots/__Snapshots__/FooSnapshotTests"
  mkdir -p "$d"
  i=0
  while [ "$i" -lt "$2" ]; do
    head -c "$3" /dev/zero > "$d/case$i.png"; i=$((i + 1))
  done
}

mkdir -p "$tmp/ok";   mk "$tmp/ok" 3 1000
run "uygun" 0 "$tmp/ok" SNAPSHOT_MAX_COUNT=3 SNAPSHOT_MAX_MB=1

mkdir -p "$tmp/many"; mk "$tmp/many" 4 10
run "sayı aşımı" 1 "$tmp/many" SNAPSHOT_MAX_COUNT=3 SNAPSHOT_MAX_MB=1
case "$LAST" in *"sayısı tavanı aştı"*case0.png*|*"sayısı tavanı aştı"*) ;; *) echo "DÜŞTÜ: sayı iletisi yok"; fails=$((fails + 1));; esac
case "$LAST" in *case3.png*) ;; *) echo "DÜŞTÜ: liste yok"; fails=$((fails + 1));; esac

mkdir -p "$tmp/big";  mk "$tmp/big" 2 1100000
run "boyut aşımı" 1 "$tmp/big" SNAPSHOT_MAX_COUNT=300 SNAPSHOT_MAX_MB=2
case "$LAST" in *"boyutu tavanı aştı"*) ;; *) echo "DÜŞTÜ: boyut iletisi yok"; fails=$((fails + 1));; esac

# __Snapshots__ dışındaki PNG sayılmaz.
mkdir -p "$tmp/other/Tests/Foo"; head -c 10 /dev/zero > "$tmp/other/Tests/Foo/a.png"
run "dışarıdaki png sayılmaz" 0 "$tmp/other" SNAPSHOT_MAX_COUNT=0 SNAPSHOT_MAX_MB=1

mkdir -p "$tmp/none"
run "Tests yok" 1 "$tmp/none"

[ "$fails" -eq 0 ] || { echo "$fails test düştü"; exit 1; }
echo "Hepsi geçti."
