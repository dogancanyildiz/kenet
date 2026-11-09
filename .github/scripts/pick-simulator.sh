#!/bin/sh
# Tek simülatör seçimi: record-screen-snapshots.sh, screen-tour.sh ve CI'daki
# .github/actions/ios-build aynı aygıtı alsın.
#
#   sh .github/scripts/pick-simulator.sh <iPhone|iPad>
#
# Tek satır yazar: "<udid> <ad> iOS <sürüm>". Hem CI imajı (macos-26: iOS 26.2 ve 26.5) hem yerel
# makine birden çok runtime taşıyabilir. Referanslar kapının çizdiği runtime'da kaydedilsin diye
# en eski kurulu iOS runtime'ındaki aygıt seçilir (kimlikle, ad belirsiz kalmasın). iPad'de yalnız
# tercih listesindeki aygıtlar sayılır: iPad referansları 13 inçlik ekranda çizilir.
set -eu

FAMILY="${1:-}"
case "$FAMILY" in
  iPhone | iPad) ;;
  *) echo "Kullanım: sh .github/scripts/pick-simulator.sh <iPhone|iPad>" >&2; exit 2 ;;
esac

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

xcrun simctl list devices available -j | FAMILY="$FAMILY" python3 -c '
import json, os, re, sys
data = json.load(sys.stdin)
family = os.environ["FAMILY"]
if family == "iPad":
    preferred = ["iPad Pro 13-inch (M5)", "iPad Pro 13-inch (M4)", "iPad Air 13-inch (M4)",
                 "iPad Air 13-inch (M3)", "iPad Pro 13-inch"]
else:
    preferred = ["iPhone 17", "iPhone 16", "iPhone 15", "iPhone 14"]
runtimes = []
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    found = [d for d in devices if d.get("isAvailable") and d.get("name", "").startswith(family)]
    if family == "iPad":
        found = [d for d in found if d["name"] in preferred]
    if found:
        runtimes.append(((int(match.group(1)), int(match.group(2))), found))
if not runtimes:
    print("Uygun %s simülatörü yok" % family, file=sys.stderr)
    raise SystemExit(1)
version, found = sorted(runtimes, key=lambda item: item[0])[0]
by_name = {d["name"]: d for d in found}
chosen = next((by_name[n] for n in preferred if n in by_name), found[0])
print(chosen["udid"], chosen["name"], "iOS %d.%d" % version)
'
