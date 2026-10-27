#!/bin/sh
# ui-audit-suites.sh testi: sahte depoda ad kuralı, üç kip ve boş liste; gerçek depoda listenin
# geçerliliği; ci.yml'deki üç denetim adımının listeyi nasıl kullandığı.
# Korunan şey: denetim işleri yalnız var olan kümeleri koşar, akış işi boş kalmaz ve uygulamayı açan
# her denetim kümesi bir denetim işine gider (adında Accessibility ya da Audit geçen, uygulamayı açan
# sınıf ad kuralına uymuyorsa düşer). Üç adım birbirini tamamlar: iPhone denetim adımı listeyi ortak
# küme hariç (--iphone) yalnız -only-testing ile, iPad denetim adımı yalnız ortak kümeyi (--shared)
# -only-testing ile, akış adımı bütün JournalUITests'i tam liste -skip-testing ile koşar; her adım
# kendi listesi boşsa xcodebuild'i çağırmadan düşer (boş -only-testing her şeyi koşturur, var olmayan
# ad hiçbir şey koşturmaz).
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
final class AccessibilityAuditUITests: XCTestCase {}
@available(iOS 26, *) final class CAvailableAccessibilityUITests: XCTestCase {}
@MainActor @objc(Named) final class NamedAuditUITests: XCTestCase {}
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
mkdir -p "$ui/Sub/Deeper"
echo 'final class DSubAuditUITests: XCTestCase {}' > "$ui/Sub/D.swift"
echo 'final class EDeeperAccessibilityUITests: XCTestCase {}' > "$ui/Sub/Deeper/E.swift"
echo 'final class NotSwiftAuditUITests: XCTestCase {}' > "$ui/Sub/F.txt"
echo 'final class OtherAccessibilityUITests: XCTestCase {}' > "$tmp/fake/Tests/JournalTests/C.swift"
want="AccessibilityAuditUITests
BarAuditUITests
BazAccessibilityUITests
CAvailableAccessibilityUITests
DSubAuditUITests
EDeeperAccessibilityUITests
FooAccessibilityUITests
NamedAuditUITests"
got=$(sh "$script" "$tmp/fake") || fail "sahte depoda çıkış sıfır değil"
[ "$got" = "$want" ] || { fail "ad kuralı"; printf 'beklenen:\n%s\nalınan:\n%s\n' "$want" "$got"; }
# Kipler: --shared yalnız ortak kümeyi, --iphone geri kalanı verir; ikisi birlikte tam listedir.
got=$(sh "$script" --shared "$tmp/fake") || fail "sahte depoda --shared çıkış sıfır değil"
[ "$got" = "AccessibilityAuditUITests" ] || fail "--shared: beklenen AccessibilityAuditUITests, alınan: $got"
got=$(sh "$script" --iphone "$tmp/fake") || fail "sahte depoda --iphone çıkış sıfır değil"
[ "$got" = "$(printf '%s\n' "$want" | grep -vx AccessibilityAuditUITests)" ] || fail "--iphone: ortak küme dışındakiler; alınan: $got"
if out=$(sh "$script" --iphone --shared "$tmp/fake" 2>&1); then fail "iki kip birden kabul edildi: $out"; fi
if out=$(sh "$script" --bogus "$tmp/fake" 2>&1); then fail "bilinmeyen kip kabul edildi: $out"; fi

# 2. Boş liste düşer: boş -only-testing xcodebuild'e her şeyi koşturur.
mkdir -p "$tmp/empty/Tests/JournalUITests"
echo 'final class SmokeUITests: XCTestCase {}' > "$tmp/empty/Tests/JournalUITests/A.swift"
if out=$(sh "$script" "$tmp/empty" 2>&1); then fail "eşleşme yokken çıkış sıfır: $out"; fi
if out=$(sh "$script" "$tmp/yok" 2>&1); then fail "klasör yokken çıkış sıfır: $out"; fi
# Ortak küme yoksa --shared düşer (iPad adımı var olmayan adla hiçbir şey koşturmasın); yalnız ortak
# küme varsa --iphone düşer.
mkdir -p "$tmp/noshared/Tests/JournalUITests" "$tmp/sharedonly/Tests/JournalUITests"
echo 'final class FooAuditUITests: XCTestCase {}' > "$tmp/noshared/Tests/JournalUITests/A.swift"
echo 'final class AccessibilityAuditUITests: XCTestCase {}' > "$tmp/sharedonly/Tests/JournalUITests/A.swift"
if out=$(sh "$script" --shared "$tmp/noshared" 2>&1); then fail "ortak küme yokken --shared çıkış sıfır: $out"; fi
if out=$(sh "$script" --iphone "$tmp/sharedonly" 2>&1); then fail "yalnız ortak küme varken --iphone çıkış sıfır: $out"; fi
[ "$(sh "$script" --iphone "$tmp/noshared")" = "FooAuditUITests" ] || fail "ortak küme yokken --iphone tam listeyi vermeli"
[ "$(sh "$script" --shared "$tmp/sharedonly")" = "AccessibilityAuditUITests" ] || fail "--shared yalnız ortak kümeyle"

# 3. Gerçek depo.
list=$(sh "$script") || fail "gerçek depoda çıkış sıfır değil"
[ -n "$list" ] || fail "gerçek depoda liste boş"
classes=$(find "$repo/Tests/JournalUITests" -type f -name '*.swift' -exec cat {} + \
  | grep -oE '^[[:space:]]*((@[A-Za-z]+(\([^)]*\))?|[A-Za-z]+)[[:space:]]+)*class[[:space:]]+[A-Za-z0-9_]+[[:space:]]*:[[:space:]]*XCTestCase' \
  | sed -E 's/[[:space:]]*:.*//' | awk '{print $NF}' | sort -u)
for name in $list; do
  printf '%s\n' "$classes" | grep -qx "$name" || fail "$name Tests/JournalUITests içinde XCTestCase sınıfı değil"
done
flow=$(printf '%s\n' "$classes" | grep -vxF "$list" || true)
[ -n "$flow" ] || fail "akış işine küme kalmadı"
shared=$(sh "$script" --shared) || fail "gerçek depoda ortak küme yok"
iphone=$(sh "$script" --iphone) || fail "gerçek depoda iPhone denetim listesi boş"
[ "$(printf '%s\n%s\n' "$shared" "$iphone" | sort -u)" = "$list" ] || fail "--shared ve --iphone birlikte tam liste değil"
# Adında Accessibility ya da Audit geçen ve uygulamayı açan sınıf denetim listesinde olmalı.
for name in $(printf '%s\n' "$classes" | grep -E 'Accessibility|Audit' || true); do
  file=$(grep -rlE --include='*.swift' "class[[:space:]]+$name[[:space:]]*:" "$repo/Tests/JournalUITests" | head -n 1)
  grep -qE 'launchApp\(|XCUIApplication\(\)' "$file" || continue
  printf '%s\n' "$list" | grep -qx "$name" \
    || fail "$name uygulamayı açan bir denetim kümesi ama listede yok (ad AccessibilityUITests ya da AuditUITests ile bitmeli)"
done

# 4. ci.yml bağlantısı: iki adımın run bloğu sahte depoda çalıştırılır; xcodebuild-retry.sh yerine
# argümanlarını yazan bir betik konur. Ölçülen, adımın xcodebuild'e gerçekten verdiği seçimdir.
workflow="$repo/.github/workflows/ci.yml"
# Adım kimliğinden sonraki "run: |" bloğu, girintisi atılmış ve UDID ifadesi sabitlenmiş olarak.
step_script() {
  awk -v id="$1" '
    !found && $0 ~ "^[[:space:]]+id: " id "[[:space:]]*$" { found = 1; next }
    found && !inrun && /^[[:space:]]+run: \|[[:space:]]*$/ { inrun = 1; match($0, /^[[:space:]]+/); indent = RLENGTH; next }
    found && !inrun && /^[[:space:]]+- / { exit }
    inrun {
      if ($0 ~ /^[[:space:]]*$/) { print ""; next }
      match($0, /^[[:space:]]*/)
      if (RLENGTH <= indent) exit
      print substr($0, indent + 3)
    }' "$workflow" | sed 's/\${{ steps\.build\.outputs\.udid }}/FAKE-UDID/g'
}
# Sahte depoda adımı koşar; xcodebuild argümanları "$2/args" dosyasına satır satır yazılır.
run_step() {
  rm -f "$2/args"
  (cd "$2" && bash -e "$tmp/$1.step" >/dev/null 2>&1)
}
make_repo() {
  mkdir -p "$1/.github/scripts" "$1/Tests/JournalUITests"
  cp "$script" "$1/.github/scripts/ui-audit-suites.sh"
  printf '#!/bin/sh\nfor arg do printf "%%s\\n" "$arg"; done > "%s/args"\n' "$1" > "$1/.github/scripts/xcodebuild-retry.sh"
}
make_repo "$tmp/steps"
printf 'final class SmokeUITests: XCTestCase {}\nfinal class OneAuditUITests: XCTestCase {}\nfinal class TwoAccessibilityUITests: XCTestCase {}\nfinal class AccessibilityAuditUITests: XCTestCase {}\n' \
  > "$tmp/steps/Tests/JournalUITests/A.swift"
make_repo "$tmp/nosuites"
echo 'final class SmokeUITests: XCTestCase {}' > "$tmp/nosuites/Tests/JournalUITests/A.swift"
# Yalnız ortak küme: akış ve iPad adımları koşar, iPhone denetim adımı listesi boş diye düşer.
make_repo "$tmp/sharedsteps"
printf 'final class SmokeUITests: XCTestCase {}\nfinal class AccessibilityAuditUITests: XCTestCase {}\n' \
  > "$tmp/sharedsteps/Tests/JournalUITests/A.swift"
suites=$(sh "$script" "$tmp/steps")
only_iphone=$(sh "$script" --iphone "$tmp/steps" | sed 's#^#-only-testing:JournalUITests/#')
only_shared=$(sh "$script" --shared "$tmp/steps" | sed 's#^#-only-testing:JournalUITests/#')
skip_suites=$(printf '%s\n' $suites | sed 's#^#-skip-testing:JournalUITests/#')
for step in ios_audit ios_ui pad_a11y; do
  step_script "$step" > "$tmp/$step.step"
  grep -q 'ui-audit-suites\.sh' "$tmp/$step.step" || { fail "ci.yml: $step adımı ui-audit-suites.sh çağırmıyor"; continue; }
  if run_step "$step" "$tmp/steps" && [ -f "$tmp/steps/args" ]; then
    selection=$(grep -E '^-(only|skip)-testing' "$tmp/steps/args" | sort)
    case $step in
      ios_audit) want_selection=$(printf '%s\n' "$only_iphone" | sort) ;;
      pad_a11y) want_selection=$(printf '%s\n' "$only_shared" | sort) ;;
      ios_ui) want_selection=$(printf '%s\n%s\n' "-only-testing:JournalUITests" "$skip_suites" | sort) ;;
    esac
    [ "$selection" = "$want_selection" ] \
      || { fail "ci.yml: $step adımının test seçimi"; printf 'beklenen:\n%s\nalınan:\n%s\n' "$want_selection" "$selection"; }
    sed -n 2p "$tmp/steps/args" | grep -qx test-without-building || fail "ci.yml: $step adımı test-without-building koşmuyor"
  else
    fail "ci.yml: $step adımı sahte depoda koşmadı"
  fi
  # Liste boşsa adım xcodebuild'i çağırmadan düşmeli: boş -only-testing her şeyi koşturur.
  if run_step "$step" "$tmp/nosuites" || [ -f "$tmp/nosuites/args" ]; then
    fail "ci.yml: $step adımı denetim listesi boşken xcodebuild'i çağırdı ya da geçti"
  fi
  case $step in
    ios_audit)
      if run_step "$step" "$tmp/sharedsteps" || [ -f "$tmp/sharedsteps/args" ]; then
        fail "ci.yml: $step adımı yalnız ortak küme varken xcodebuild'i çağırdı ya da geçti"
      fi ;;
    *)
      run_step "$step" "$tmp/sharedsteps" && [ -f "$tmp/sharedsteps/args" ] \
        || fail "ci.yml: $step adımı yalnız ortak küme varken koşmadı" ;;
  esac
done

echo "Denetim (iPhone): $(echo $iphone)"
echo "Denetim (ortak, iPad): $(echo $shared)"
echo "Akış: $(echo $flow)"
[ "$fails" -eq 0 ] || { echo "$fails test düştü"; exit 1; }
echo "Hepsi geçti."
