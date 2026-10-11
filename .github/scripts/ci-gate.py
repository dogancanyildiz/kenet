#!/usr/bin/env python3
"""CI'ın birleştirici kararı: dal korumasının beklediği "ci" denetimi yeşil mi olmalı.

Kural:
- Her iş "success" ise geçer.
- "skipped" yalnız şu durumda başarı sayılır: PR yalnız belge değiştiriyor (DOCS_ONLY tam
  olarak "true") VE iş, atlanmasına hiçbir zaman izin verilmeyenlerden değil.
- "failure", "cancelled" ve tanınmayan her sonuç hiçbir koşulda başarı sayılmaz.
- Atlanamayan işler (argümanlar) eksikse ya da girdi okunamıyorsa düşer.

Kullanım: NEEDS='<toJSON(needs)>' DOCS_ONLY=<true|false> python3 ci-gate.py <atlanamayan iş>...
Çıkış kodu: 0 geçti, 1 düştü.
"""

import json
import os
import sys


def evaluate(needs, docs_only, never_skipped):
    """Düşme nedenlerinin listesi; boşsa geçti.

    needs: {iş kimliği: {"result": ...}} (GitHub'ın `needs` bağlamı), docs_only: dizgi.
    """
    if not isinstance(needs, dict) or not needs:
        return ["iş sonuçları okunamadı ya da boş"]
    problems = []
    for job in sorted(never_skipped):
        if job not in needs:
            problems.append(f"{job}: beklenen iş sonuçlarda yok")
    skip_allowed = docs_only == "true"
    for job in sorted(needs):
        entry = needs[job]
        result = entry.get("result") if isinstance(entry, dict) else None
        if result == "success":
            continue
        if result == "skipped" and skip_allowed and job not in never_skipped:
            continue
        problems.append(f"{job}: {result}")
    return problems


def main(argv, environ):
    never_skipped = set(argv[1:])
    docs_only = environ.get("DOCS_ONLY", "")
    try:
        needs = json.loads(environ.get("NEEDS", ""))
    except ValueError:
        needs = None
    if isinstance(needs, dict):
        for job in sorted(needs):
            entry = needs[job]
            print(f"{job}: {entry.get('result') if isinstance(entry, dict) else entry}")
    print(f"Yalnız belge: {docs_only!r}; atlanamayan işler: {sorted(never_skipped)}")
    if not never_skipped:
        print("Atlanamayan iş listesi boş; karar verilemez.")
        return 1
    problems = evaluate(needs, docs_only, never_skipped)
    if problems:
        print("Başarısız, iptal edilmiş ya da izinsiz atlanmış iş var:")
        for problem in problems:
            print("  " + problem)
        return 1
    print("Tüm işler başarılı (belge PR'ında atlananlar dahil).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv, os.environ))
