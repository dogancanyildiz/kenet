#!/bin/sh
# Belge biçim denetimi: karar tablosu, README belge tablosu, String Catalog tamlığı.
# Aşama 8 kapısı; CI "Biçim ve kurallar" işinde koşar.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"

fail=0

# --- Karar tablosu (docs/decisions.md) ---------------------------------------
# Tablo satırları ardışık olmalı (boş satır bölmez); her satırda aynı sütun sayısı;
# hücre ayırıcısı olmayan `|` kaçışlı olmalı (`\|`).
check_decisions() {
    python3 - "$root/docs/decisions.md" <<'PY'
import re
import sys

path = sys.argv[1]
lines = open(path, encoding="utf-8").read().splitlines()

def cells(line: str) -> list[str]:
    parts = re.split(r"(?<!\\)\|", line)
    if parts and parts[0] == "":
        parts = parts[1:]
    if parts and parts[-1] == "":
        parts = parts[:-1]
    return [p.strip() for p in parts]

errors: list[str] = []
i = 0
while i < len(lines):
    if lines[i].strip() == "## Karar günlüğü":
        break
    i += 1
else:
    print("docs/decisions.md: '## Karar günlüğü' bölümü bulunamadı.", file=sys.stderr)
    sys.exit(1)

i += 1
while i < len(lines) and not lines[i].startswith("|"):
    i += 1
if i >= len(lines):
    print("docs/decisions.md: karar tablosu başlığı bulunamadı.", file=sys.stderr)
    sys.exit(1)

header = cells(lines[i])
if header != ["Tarih", "Karar", "Gerekçe"]:
    errors.append(f"L{i + 1}: beklenen başlık | Tarih | Karar | Gerekçe |, görülen: {header}")
expected_cols = len(header)
i += 1
if i >= len(lines) or not re.match(r"^\|\s*-+", lines[i]):
    errors.append(f"L{i + 1}: ayırıcı satır eksik")
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
sep_cols = cells(lines[i])
if len(sep_cols) != expected_cols:
    errors.append(f"L{i + 1}: ayırıcı sütun sayısı {len(sep_cols)}, beklenen {expected_cols}")
i += 1

row_count = 0
while i < len(lines):
    line = lines[i]
    if line.strip() == "":
        j = i + 1
        while j < len(lines) and lines[j].strip() == "":
            j += 1
        if j < len(lines) and lines[j].startswith("|") and not re.match(r"^\|\s*-+", lines[j]):
            errors.append(
                f"L{i + 1}: boş satır karar tablosunu bölüyor (sonraki tablo satırı L{j + 1})"
            )
            i = j
            continue
        break
    if line.startswith("## "):
        break
    if not line.startswith("|"):
        errors.append(f"L{i + 1}: tablo içinde tablo dışı satır: {line[:80]}")
        break
    cols = cells(line)
    if len(cols) != expected_cols:
        errors.append(
            f"L{i + 1}: sütun sayısı {len(cols)}, beklenen {expected_cols} "
            f"(kaçışsız '|' hücreyi böler; kod içinde '\\|' kullan)"
        )
    row_count += 1
    i += 1

if row_count == 0:
    errors.append("Karar tablosunda veri satırı yok.")

if errors:
    print("Karar tablosu hatalı:", file=sys.stderr)
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
print(f"Karar tablosu uygun ({row_count} satır).")
PY
}

# --- README belge tablosu ----------------------------------------------------
# docs/ altındaki her .md README tablosunda listelenmeli; tabloda yazan her yol var olmalı.
check_readme_table() {
    python3 - "$root" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
docs_dir = root / "docs"
readme = root / "README.md"
text = readme.read_text(encoding="utf-8")

m = re.search(r"^\| Belge \| İçerik \|\s*$", text, re.M)
if not m:
    print("README.md: belge tablosu başlığı (| Belge | İçerik |) bulunamadı.", file=sys.stderr)
    sys.exit(1)

rest = text[m.end() :]
listed: list[str] = []
for line in rest.splitlines():
    if line.strip() == "":
        # Başlık ile tablo arasında ya da tablo sonundaki boş satır.
        if listed:
            break
        continue
    if not line.startswith("|"):
        break
    if re.match(r"^\|\s*-+", line):
        continue
    link = re.search(r"\[([^\]]+)\]\((docs/[^)]+\.md)\)", line)
    if link:
        listed.append(link.group(2))

on_disk = sorted(f"docs/{p.name}" for p in docs_dir.glob("*.md") if p.is_file())
listed_set = set(listed)
disk_set = set(on_disk)
errors: list[str] = []
for path in sorted(disk_set - listed_set):
    errors.append(f"Tabloda yok: {path}")
for path in sorted(listed_set - disk_set):
    errors.append(f"Tabloda var, dosya yok: {path}")
seen: set[str] = set()
for path in listed:
    if path in seen:
        errors.append(f"Tabloda yineleniyor: {path}")
    seen.add(path)

if errors:
    print("README belge tablosu hatalı:", file=sys.stderr)
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
print(f"README belge tablosu uygun ({len(on_disk)} dosya).")
PY
}

# --- String Catalog tamlığı --------------------------------------------------
# Her anahtarın tr ve en çevirisi olmalı. stale uyarılır (hata değil).
# Koddaki sabit anahtarların katalogda olmaması uyarıdır (hata değil).
check_string_catalog() {
    python3 - "$root" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
catalog_path = root / "App/Resources/Localizable.xcstrings"
data = json.loads(catalog_path.read_text(encoding="utf-8"))
strings = data.get("strings") or {}
required = ("tr", "en")

# Kataloglar Xcode'un yazdığı biçimde durmalı (iki boşluk girinti, " : " ayırıcı). Başka biçimde
# yazılırsa Xcode ilk derlemede bütün dosyayı yeniden yazar ve çalışma klasörü kirlenir.
misformatted = []
for path in sorted((root / "App/Resources").glob("*.xcstrings")):
    raw = path.read_text(encoding="utf-8")
    canonical = json.dumps(json.loads(raw), indent=2, ensure_ascii=False, separators=(",", " : "))
    if raw.rstrip("\n") != canonical:
        misformatted.append(path.name)
if misformatted:
    print("String Catalog Xcode biçiminde değil: " + ", ".join(misformatted), file=sys.stderr)
    print(
        'Düzeltme: json.dumps(veri, indent=2, ensure_ascii=False, separators=(",", " : ")) ile yaz.',
        file=sys.stderr,
    )
    sys.exit(1)


def localization_has_value(loc: dict) -> bool:
    if not loc:
        return False
    su = loc.get("stringUnit") or {}
    val = su.get("value")
    if isinstance(val, str) and val != "":
        return True
    plural = ((loc.get("variations") or {}).get("plural")) or {}
    for form in plural.values():
        su = (form or {}).get("stringUnit") or {}
        val = su.get("value")
        if isinstance(val, str) and val != "":
            return True
    return False


def unescape_swift(s: str) -> str:
    out: list[str] = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            n = s[i + 1]
            mapping = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
            out.append(mapping.get(n, n))
            i += 2
            continue
        out.append(s[i])
        i += 1
    return "".join(out)


errors: list[str] = []
stale: list[str] = []
for key, entry in sorted(strings.items(), key=lambda kv: kv[0]):
    entry = entry or {}
    if entry.get("extractionState") == "stale":
        stale.append(key)
    locs = entry.get("localizations") or {}
    for lang in required:
        if not localization_has_value(locs.get(lang) or {}):
            errors.append(f"Eksik çeviri ({lang}): {key!r}")

if errors:
    print("String Catalog hatalı:", file=sys.stderr)
    for e in errors:
        print(e, file=sys.stderr)
    if stale:
        print("Uyarı: stale anahtarlar (hata değil):", file=sys.stderr)
        for k in stale:
            print(f"  {k}", file=sys.stderr)
    sys.exit(1)

print(f"String Catalog uygun ({len(strings)} anahtar, tr/en tam).")
if stale:
    print(f"Uyarı: {len(stale)} stale anahtar (hata değil):")
    for k in stale:
        print(f"  {k}")

pat = re.compile(
    r"""(?:String\(\s*localized:\s*|Text\()(?P<q>"(?P<s>(?:\\.|[^"\\])*)")"""
)
code_keys: set[str] = set()
for path in sorted((root / "App").rglob("*.swift")):
    text = path.read_text(encoding="utf-8")
    for m in pat.finditer(text):
        s = m.group("s")
        if "\\(" in s or s == "":
            continue
        code_keys.add(unescape_swift(s))

missing = sorted(k for k in code_keys if k not in strings)
if missing:
    print(f"Uyarı: kodda var, katalogda yok ({len(missing)} anahtar, hata değil):")
    for k in missing[:50]:
        print(f"  {k}")
    if len(missing) > 50:
        print(f"  … ve {len(missing) - 50} tane daha")
PY
}

check_decisions || fail=1
check_readme_table || fail=1
check_string_catalog || fail=1

if [ "$fail" -ne 0 ]; then
    echo "Belge biçim denetimi başarısız."
    exit 1
fi
echo "Belge biçim denetimi geçti."
