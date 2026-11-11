#!/usr/bin/env python3
"""Düşen arayüz denetimi vakalarının "A11Y" bulgularını bir xcresult paketinden CI günlüğüne yazar.

Denetim adımı `-quiet` koşar; bulgu satırları yalnız sonuç paketindedir. Paket artifact olarak
yüklenemediğinde (koşu 43019150702: `Failed to CreateArtifact: ENOTFOUND`) kanıt günlükte kalır.

Her düşen vaka için yazılanlar:
- "A11Y issue (<ekran>): <tür> — '<kimlik>' '<etiket>' <çerçeve>" etkinlik başlıkları
  (AccessibilityAuditPolicy.handle), öğe ve çerçeveyle.
- Vakanın hata iletileri (dokunma hedefi denetimi, zaman aşımı ve öteki hatalar).
GITHUB_STEP_SUMMARY ortam değişkeni doluysa aynı satırlar iş özetine de eklenir.

Tanılama içindir: her zaman 0 ile çıkar; xcresulttool düşerse ya da şema tanınmazsa uyarır.

Kullanım: python3 -I a11y-issues.py <paket.xcresult> [--title <başlık>]
"""

import json
import os
import subprocess
import sys

ISSUE_PREFIX = "A11Y issue"
MESSAGE_LIMIT = 600


def failed_cases(document):
    """Düşen "Test Case" düğümleri: (kimlik, hata iletileri)."""
    found = []

    def messages(node):
        result = []
        for child in node.get("children") or []:
            if child.get("nodeType") == "Failure Message":
                result.append(str(child.get("name", ""))[:MESSAGE_LIMIT])
            result += messages(child)
        return result

    def walk(node):
        if not isinstance(node, dict):
            return
        if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
            found.append((node.get("nodeIdentifier") or node.get("name", "?"), messages(node)))
            return
        for child in node.get("children") or []:
            walk(child)

    for node in document.get("testNodes") or []:
        walk(node)
    return found


def issue_titles(activities):
    """Bir vakanın etkinlik ağacındaki "A11Y issue" başlıkları, sırasıyla."""
    titles = []

    def walk(activity):
        title = activity.get("title", "")
        if title.startswith(ISSUE_PREFIX):
            titles.append(title)
        for child in activity.get("childActivities") or []:
            walk(child)

    for run in activities.get("testRuns") or []:
        for activity in run.get("activities") or []:
            walk(activity)
    return titles


def xcresult(path, *arguments):
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", *arguments, "--path", path],
        check=True, capture_output=True, text=True).stdout
    return json.loads(output)


def report(path, title):
    try:
        cases = failed_cases(xcresult(path, "tests"))
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"::warning::{title}: {path} okunamadı ({error})")
        return []
    lines = [f"== {title}: düşen vakaların A11Y bulguları ({len(cases)} vaka)"]
    for identifier, messages in cases:
        lines.append(f"-- {identifier}")
        try:
            titles = issue_titles(xcresult(path, "activities", "--test-id", identifier))
        except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
            titles = [f"(etkinlikler okunamadı: {error})"]
        lines += [f"   {line}" for line in titles]
        lines += [f"   hata: {message}" for message in messages]
    return lines


def main(argv):
    arguments = list(argv)
    title = "Arayüz denetimi"
    if "--title" in arguments:
        index = arguments.index("--title")
        title = arguments[index + 1] if index + 1 < len(arguments) else title
        del arguments[index : index + 2]
    if len(arguments) != 1:
        print("kullanım: a11y-issues.py <paket.xcresult> [--title <başlık>]", file=sys.stderr)
        return 0
    path = arguments[0]
    if not os.path.isdir(path):
        print(f"::warning::{title}: {path} yok, A11Y bulguları atlandı")
        return 0
    lines = report(path, title)
    print("\n".join(lines))
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary and lines:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(f"### {lines[0].lstrip('= ')}\n\n```\n" + "\n".join(lines[1:]) + "\n```\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
