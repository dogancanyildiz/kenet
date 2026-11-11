#!/usr/bin/env python3
"""Koddaki sabit arayüz metinlerinin String Catalog'da olduğunu denetler.

Kullanım: check-catalog-keys.py [kök]   (varsayılan: deponun kökü)

`App/**/*.swift`, `Widgets/**/*.swift`, `ShareExtension/**/*.swift` ve `Shared/**/*.swift` içinde
yerelleştirilen çağrıların ilk sabit metin argümanı çıkarılır
(`Text("…")`, `Button("…")`, `Label("…", …)`, `String(localized: "…")`, `LocalizedStringKey("…")`, …)
ve `App/Resources/Localizable.xcstrings` anahtar kümesiyle karşılaştırılır. Eksik anahtar hatadır.
Widget ve paylaşım uzantısı hedefleri aynı kataloğu derler (`project.yml`, `JournalWidgets`, `JournalShare`).

İkinci kural: `locale:` alıp `bundle:` almayan `String(localized:)` çağrısı hatadır. Bu çağrı dili
süreçten seçer, `locale` yalnız biçimi etkiler. Yerine `PresentationLocalization.string(localized:locale:)`
kullanılır (fark3 Y8).

Sayılmaz: `verbatim:` girdileri, değişken argümanlar (`Text(copy.copy)`), enterpolasyonlu
metinler (anahtar biçimi `%@` / `%lld` Xcode'a bağlıdır), yorum satırları ve `EXCEPTIONS` listesi.
"""

import json
import re
import sys
from pathlib import Path

# Sabit metni ilk argüman olarak yerelleştiren SwiftUI çağrıları ve `.değiştirici("…")` biçimleri.
INITIALIZERS = (
    "Text", "Button", "Label", "Toggle", "Section", "Menu", "NavigationLink", "Link",
    "LabeledContent", "TextField", "TextEditor", "SecureField", "Picker", "DisclosureGroup",
    "ProgressView", "ShareLink", "Stepper", "DatePicker", "ContentUnavailableView", "Tab",
    "GroupBox", "Gauge", "InkTabItem", "LocalizedStringKey", "LocalizedStringResource",
)
MODIFIERS = (
    "navigationTitle", "help", "accessibilityLabel", "accessibilityHint", "accessibilityValue",
    "confirmationDialog", "alert", "badge", "navigationSubtitle", "accessibilityIdentifierLabel",
    "configurationDisplayName", "description",
)

# Açık istisnalar: anahtar -> gerekçe. Boş tutmak yeğdir.
EXCEPTIONS: dict[str, str] = {}

STRING = r'"(?P<s>(?:\\.|[^"\\])*)"'
CALLS = (
    re.compile(r"(?<![\w.])(?:" + "|".join(INITIALIZERS) + r")\(\s*" + STRING),
    re.compile(r"\.(?:" + "|".join(MODIFIERS) + r")\(\s*" + STRING),
    re.compile(r"String\(\s*localized:\s*" + STRING),
)


def unescape_swift(s: str) -> str:
    mapping = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\"}
    out: list[str] = []
    i = 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append(mapping.get(s[i + 1], s[i + 1]))
            i += 2
            continue
        out.append(s[i])
        i += 1
    return "".join(out)


def strip_comments(text: str) -> str:
    """Yorumları boşlukla değiştirir (satır numaraları korunur); metin sabitlerine dokunmaz."""
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i : j + 1])
            i = j + 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def extract_keys(text: str) -> list[tuple[int, str]]:
    """(satır, anahtar) çiftleri; enterpolasyonlu ve boş metinler dışarıda."""
    text = strip_comments(text)
    found: list[tuple[int, str]] = []
    for pattern in CALLS:
        for m in pattern.finditer(text):
            s = m.group("s")
            if s == "" or "\\(" in s:
                continue
            found.append((text.count("\n", 0, m.start()) + 1, unescape_swift(s)))
    return sorted(found)


LOCALIZED_CALL = re.compile(r"(?<![\w.])String\(\s*localized:")


def _skip_string(text: str, i: int) -> int:
    """`i` bir metin sabitinin açılış tırnağında; kapanıştan sonraki konumu döndürür."""
    multi = text.startswith('"""', i)
    i += 3 if multi else 1
    n = len(text)
    while i < n:
        if text.startswith("\\(", i):
            i = _call_end(text, i + 2)[0] + 1
            continue
        if text[i] == "\\":
            i += 2
            continue
        if multi and text.startswith('"""', i):
            return i + 3
        if not multi and text[i] == '"':
            return i + 1
        i += 1
    return n


def _call_end(text: str, i: int) -> tuple[int, str]:
    """`i` açılış parantezinden sonra; (kapanış konumu, metinsiz üst düzey argüman metni)."""
    depth, top, n = 1, [], len(text)
    while i < n:
        c = text[i]
        if c == '"':
            i = _skip_string(text, i)
            top.append('""')
            continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i, "".join(top)
        if depth == 1:
            top.append(c)
        i += 1
    return n, "".join(top)


def locale_without_bundle(text: str) -> list[int]:
    """`locale:` alıp `bundle:` almayan `String(localized:)` çağrılarının satırları."""
    text = strip_comments(text)
    lines: list[int] = []
    for m in LOCALIZED_CALL.finditer(text):
        _, top = _call_end(text, text.index("(", m.start()) + 1)
        if re.search(r"\blocale:", top) and not re.search(r"\bbundle:", top):
            lines.append(text.count("\n", 0, m.start()) + 1)
    return lines


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parents[2]
    catalog = json.loads((root / "App/Resources/Localizable.xcstrings").read_text(encoding="utf-8"))
    keys = set(catalog.get("strings") or {})
    missing: list[str] = []
    process_language: list[str] = []
    for path in sorted(p for folder in ("App", "Widgets", "ShareExtension", "Shared") for p in (root / folder).rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        for line, key in extract_keys(source):
            if key not in keys and key not in EXCEPTIONS:
                missing.append(f"{path.relative_to(root)}:{line}: {key!r}")
        process_language += [f"{path.relative_to(root)}:{line}" for line in locale_without_bundle(source)]
    if process_language:
        print("String(localized:) locale: alıyor ama bundle: almıyor (dil süreçten seçilir):", file=sys.stderr)
        for m in process_language:
            print(f"  {m}", file=sys.stderr)
        print(
            "Düzeltme: PresentationLocalization.string(localized:locale:) kullan "
            "ya da bundle: PresentationLocalization.bundle(locale) ver.",
            file=sys.stderr,
        )
    if missing:
        print("Kodda var, String Catalog'da yok:", file=sys.stderr)
        for m in missing:
            print(f"  {m}", file=sys.stderr)
        print(
            "Düzeltme: anahtarı App/Resources/Localizable.xcstrings dosyasına tr ve en ile ekle; "
            "metin kullanıcıya görünmüyorsa Text(verbatim:) kullan.",
            file=sys.stderr,
        )
        return 1
    if process_language:
        return 1
    print(f"Koddaki sabit metinler katalogda ({len(keys)} anahtar).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
