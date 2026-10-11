#!/bin/sh
# iOS test adımı asıldığında nerede beklediğini kayda geçirir: süreç listesi, simülatör durumu,
# test konağının (Journal) ve xcodebuild'in yığın örnekleri, simülatörün son günlükleri.
# CI iki kez çağırır: adımın içinde arka planda (adım zaman aşımından ÖNCE, süreçler hâlâ asılıyken)
# ve adım düştükten sonra. Hiçbir sürece sinyal göndermez; her komut en iyi çabadır, betik hep 0 döner.
# Kullanım: sh .github/scripts/ios-test-diagnostics.sh <çıktı klasörü> <simülatör UDID> [bekleme sn]
#   bekleme verilirse önce o kadar uyur; adım o sürede biterse çağıran betiği sonlandırır.
set -u
out=${1:?çıktı klasörü gerekli}
udid=${2:?simülatör UDID gerekli}
delay=${3:-0}

[ "$delay" -gt 0 ] && sleep "$delay"

stamp=$(date -u +%H%M%S)
dir="$out/$stamp"
mkdir -p "$dir"
echo "iOS test tanılaması: $dir ($(date -u +%Y-%m-%dT%H:%M:%SZ))"

ps -Ao pid,ppid,etime,pcpu,rss,state,command >"$dir/ps.txt" 2>&1 || true
xcrun simctl list devices >"$dir/simctl-devices.txt" 2>&1 || true
xcrun simctl spawn "$udid" launchctl list >"$dir/sim-launchctl.txt" 2>&1 || true

# Test konağı simülatörde koşsa da macOS'ta sıradan bir süreçtir; yığını asılan testi adlandırır.
# xcodebuild ve testmanagerd örnekleri asılma testten ÖNCEyse (kurulum, başlatma) nerede olduğunu gösterir.
for pattern in 'Journal\.app/Journal' 'JournalUITests-Runner' '/xcodebuild ' 'testmanagerd'; do
  for pid in $(pgrep -f "$pattern" 2>/dev/null); do
    name=$(ps -o comm= -p "$pid" 2>/dev/null | awk -F/ '{print $NF}')
    [ -e "$dir/sample-$name-$pid.txt" ] && continue
    sample "$pid" 3 -file "$dir/sample-$name-$pid.txt" >/dev/null 2>&1 || true
  done
done

# Simülatörün birleşik günlüğü: test konağı, test hizmeti ve uygulamayı başlatan süreçler.
xcrun simctl spawn "$udid" log show --last 15m --style compact \
  --predicate 'process == "Journal" OR process == "testmanagerd" OR process == "SpringBoard" OR process == "runningboardd"' \
  2>&1 | tail -n 4000 >"$dir/sim-log.txt" || true

ls -l "$dir" 2>/dev/null || true
exit 0
