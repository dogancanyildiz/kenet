#!/bin/sh
# ui-audit-suites.sh testi: sahte depoda ad kuralı ve boş liste; gerçek depoda listenin geçerliliği.
# Korunan şey: denetim işi yalnız var olan kümeleri koşar, akış işi boş kalmaz ve uygulamayı açan
# her denetim kümesi denetim işine gider (adında Accessibility ya da Audit geçen, uygulamayı açan
# sınıf ad kuralına uymuyorsa düşer).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
script="$here/ui-audit-suites.sh"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/test-ui-audit-suites.XXXXXX")
trap 'rm -rf -- "$tmp"' 0
fails=0
fail() { echo "DÜŞTÜ: $1"; fails=$((fails + 1)); }

# 1. Ad kuralı: yalnız JournalUITests içinde, yalnız sınıf bildirimi, yalnız iki son ek.
ui="$tmp/fake/Tests/JournalUITests"
mkdir -p "$ui" "$tmp/fake/Tests/JournalTests"
cat > "$ui/A.swift" <<'SWIFT'
import XCTest
final class FooAccessibilityUITests: XCTestCase {}
@MainActor final class BarAuditUITests: XCTestCase {}
final class SmokeUITests: XCTestCase {}
final class AccessibilityAuditExemptionTests: XCTestCase {}
SWIFT
cat > "$ui/B.swift" <<'SWIFT'
// final class GhostAccessibilityUITests: XCTestCase {}
/// Ayrıntı: class CommentAuditUITests
struct ValueAccessibilityUITests {}
class BazAccessibilityUITests: XCTestCase {
    class func helperAuditUITests() {}
}
SWIFT
echo 'final class OtherAccessibilityUITests: XCTestCase {}' > "$tmp/fake/Tests/JournalTests/C.swift"
want="BarAuditUITests
BazAccessibilityUITests
FooAccessibilityUITests"
got=$(sh "$script" "$tmp/fake") || fail "sahte depoda çıkış sıfır değil"
[ "$got" = "$want" ] || { fail "ad kuralı"; printf 'beklenen:\n%s\nalınan:\n%s\n' "$want" "$got"; }

# 2. Boş liste düşer: boş -only-testing xcodebuild'e her şeyi koşturur.
mkdir -p "$tmp/empty/Tests/JournalUITests"
echo 'final class SmokeUITests: XCTestCase {}' > "$tmp/empty/Tests/JournalUITests/A.swift"
if out=$(sh "$script" "$tmp/empty" 2>&1); then fail "eşleşme yokken çıkış sıfır: $out"; fi
if out=$(sh "$script" "$tmp/yok" 2>&1); then fail "klasör yokken çıkış sıfır: $out"; fi

# 3. Gerçek depo.
list=$(sh "$script") || fail "gerçek depoda çıkış sıfır değil"
[ -n "$list" ] || fail "gerçek depoda liste boş"
classes=$(cat "$repo"/Tests/JournalUITests/*.swift \
  | grep -oE '^[[:space:]]*([A-Za-z@]+[[:space:]]+)*class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*XCTestCase' \
  | sed -E 's/[[:space:]]*:.*//' | awk '{print $NF}' | sort -u)
for name in $list; do
  printf '%s\n' "$classes" | grep -qx "$name" || fail "$name Tests/JournalUITests içinde XCTestCase sınıfı değil"
done
flow=$(printf '%s\n' "$classes" | grep -vxF "$list" || true)
[ -n "$flow" ] || fail "akış işine küme kalmadı"
# Adında Accessibility ya da Audit geçen ve uygulamayı açan sınıf denetim listesinde olmalı.
for name in $(printf '%s\n' "$classes" | grep -E 'Accessibility|Audit' || true); do
  file=$(grep -lE "class[[:space:]]+$name[[:space:]]*:" "$repo"/Tests/JournalUITests/*.swift | head -n 1)
  grep -qE 'launchApp\(|XCUIApplication\(\)' "$file" || continue
  printf '%s\n' "$list" | grep -qx "$name" \
    || fail "$name uygulamayı açan bir denetim kümesi ama listede yok (ad AccessibilityUITests ya da AuditUITests ile bitmeli)"
done

echo "Denetim: $(echo $list)"
echo "Akış: $(echo $flow)"
[ "$fails" -eq 0 ] || { echo "$fails test düştü"; exit 1; }
echo "Hepsi geçti."
