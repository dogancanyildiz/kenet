#!/usr/bin/env python3
"""İki commit arasında değişen dosyaların TAMAMI belge mi, onu söyler.

CI bunu yalnız belge değiştiren PR'larda Core ve uygulama işlerini atlamak için kullanır
(.github/workflows/ci.yml, "changes" işi). Kural tek yönlüdür: yalnız aşağıdaki dar listeye
uyan yollar belgedir, bilinmeyen her yol koddur. Emin olunamayan her durumda (eksik ya da
geçersiz commit, sığ kopya, ortak ata yok, boş fark, git hatası) yanıt "kod değişti"dir.

Kullanım: python3 ci-changes.py <taban sha> <uç sha>
Çıktı (stdout, tek satır): docs_only=true | docs_only=false. Gerekçe stderr'e yazılır.
Çıkış kodu hep 0'dır.
"""

import re
import subprocess
import sys

# Belge sayılan yollar. Genişletmeden önce: Fixtures/, project.yml, VERSION, .github/, Config/,
# .gitignore ve String Catalog testlerin girdisidir, buraya girmez.
DOCUMENT_FILES = {"LICENSE"}
DOCUMENT_DIRECTORY = "docs/"

FULL_SHA = re.compile(r"[0-9a-f]{40}(?:[0-9a-f]{24})?")


def is_document(path):
    if path in DOCUMENT_FILES:
        return True
    if path.startswith(DOCUMENT_DIRECTORY):
        return True
    # Kökteki Markdown dosyaları (README.md, AGENTS.md, CLAUDE.md).
    return "/" not in path and path.endswith(".md")


def git(repo, *args):
    done = subprocess.run(["git", "-C", repo, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if done.returncode != 0:
        raise RuntimeError("git " + " ".join(args) + ": " + done.stderr.decode(errors="replace").strip())
    return done.stdout


def changed_paths(repo, base, head):
    """Ortak atadan uca değişen yollar. Belirlenemiyorsa RuntimeError."""
    for name, sha in (("taban", base), ("uç", head)):
        if not FULL_SHA.fullmatch(sha or ""):
            raise RuntimeError(f"{name} commit'i tam bir sha değil: {sha!r}")
        if set(sha) == {"0"}:
            raise RuntimeError(f"{name} commit'i yok (sıfır sha: yeni dal ya da ilk itme)")
    if git(repo, "rev-parse", "--is-shallow-repository").strip() != b"false":
        raise RuntimeError("sığ kopya: geçmiş eksik, fark güvenilmez")
    for sha in (base, head):
        git(repo, "cat-file", "-e", sha + "^{commit}")
    ancestor = git(repo, "merge-base", base, head).decode().strip()
    if not FULL_SHA.fullmatch(ancestor):
        raise RuntimeError("ortak ata bulunamadı")
    # --no-renames: yeniden adlandırma silme + ekleme olarak gelir, iki yol da sınıflanır.
    raw = git(repo, "diff", "--name-only", "--no-renames", "-z", ancestor, head)
    return [part.decode(errors="surrogateescape") for part in raw.split(b"\0") if part]


def decide(repo, base, head):
    """(yalnız belge mi, gerekçe)"""
    try:
        paths = changed_paths(repo, base, head)
    except (RuntimeError, OSError) as error:
        return False, f"belirlenemedi, her şey koşar: {error}"
    if not paths:
        return False, "fark boş, her şey koşar"
    code = [path for path in paths if not is_document(path)]
    if code:
        shown = ", ".join(repr(path) for path in code[:10])
        return False, f"{len(paths)} dosyadan {len(code)} tanesi kod: {shown}"
    return True, f"{len(paths)} dosyanın hepsi belge"


def main(argv):
    try:
        base, head = argv[1], argv[2]
        repo = argv[3] if len(argv) > 3 else "."
        docs_only, reason = decide(repo, base, head)
    except Exception as error:  # Hata yolu da "kod değişti" der.
        docs_only, reason = False, f"beklenmeyen hata, her şey koşar: {error!r}"
    print(reason, file=sys.stderr)
    print("docs_only=true" if docs_only else "docs_only=false")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
