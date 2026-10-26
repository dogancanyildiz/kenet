#!/usr/bin/env python3
"""Bir xcresult paketindeki vaka sürelerini CI günlüğüne yazar; en uzun vakalar önce.

Girdi: `xcrun xcresulttool get test-results tests --path <paket>` çıktısı (stdin ya da dosya yolu).
Çıktı: her vaka için saniye, sonuç ve kimlik; sonda vaka sayısı ve toplam. GITHUB_STEP_SUMMARY
ortam değişkeni doluysa aynı tablo iş özetine Markdown olarak da eklenir (ilk 25 satır).

Ölçüm içindir; hiçbir eşik koymaz ve her zaman 0 ile çıkar. Girdi okunamazsa uyarır ve yine 0 ile
çıkar: ölçüm adımı test adımının sonucunu değiştirmez.

Kullanım: python3 test-durations.py [<json dosyası>] [--title <başlık>]
"""

import json
import os
import sys

SUMMARY_ROWS = 25


def cases(node):
    """Ağaçtaki "Test Case" düğümleri: (saniye, sonuç, kimlik)."""
    if isinstance(node, dict):
        if node.get("nodeType") == "Test Case":
            seconds = node.get("durationInSeconds")
            if not isinstance(seconds, (int, float)):
                seconds = 0.0
            name = node.get("nodeIdentifier") or node.get("name") or "?"
            yield (float(seconds), str(node.get("result", "?")), str(name))
        for child in node.get("children", []):
            yield from cases(child)
    elif isinstance(node, list):
        for child in node:
            yield from cases(child)


def rows(document):
    """Süreye göre azalan, eşitlikte kimliğe göre artan satırlar."""
    root = document.get("testNodes", document) if isinstance(document, dict) else document
    return sorted(cases(root), key=lambda row: (-row[0], row[2]))


def render(table, title):
    lines = [f"== {title}: vaka süreleri (saniye, en uzun önce)"]
    for seconds, result, name in table:
        lines.append(f"{seconds:8.1f}  {result:<16} {name}")
    total = sum(row[0] for row in table)
    lines.append(f"-- {len(table)} vaka, toplam {total:.1f} sn")
    return "\n".join(lines)


def render_markdown(table, title):
    lines = [f"### {title}", "", "| sn | sonuç | vaka |", "|---:|---|---|"]
    for seconds, result, name in table[:SUMMARY_ROWS]:
        lines.append(f"| {seconds:.1f} | {result} | `{name}` |")
    if len(table) > SUMMARY_ROWS:
        lines.append(f"| … | | {len(table) - SUMMARY_ROWS} vaka daha |")
    total = sum(row[0] for row in table)
    lines.append("")
    lines.append(f"{len(table)} vaka, toplam {total:.1f} sn")
    lines.append("")
    return "\n".join(lines)


def main(argv):
    title = "Testler"
    path = None
    args = list(argv)
    while args:
        arg = args.pop(0)
        if arg == "--title" and args:
            title = args.pop(0)
        else:
            path = arg
    try:
        with (open(path, encoding="utf-8") if path else sys.stdin) as source:
            document = json.load(source)
    except (OSError, ValueError) as error:
        print(f"::warning::Vaka süreleri okunamadı ({title}): {error}")
        return 0
    table = rows(document)
    print(render(table, title))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        try:
            with open(summary, "a", encoding="utf-8") as target:
                target.write(render_markdown(table, title))
        except OSError as error:
            print(f"::warning::İş özeti yazılamadı: {error}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
