#!/usr/bin/env python3
"""ci-changes.py kararlarını geçici depolarda sınar: yalnız belge atlanır, kuşkulu her durum koşar."""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parent / "ci-changes.py"
ZERO = "0" * 40


class ChangesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp.name) / "repo"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "dev", ".")
        self.write("README.md", "oku\n")
        self.write("docs/roadmap.md", "yol\n")
        self.write("App/Main.swift", "// kod\n")
        self.write("Fixtures/vaults/sample/2026-01-01.md", "- 09:00 kurgusal olay\n")
        self.base = self.commit("ilk")

    def tearDown(self):
        self.temp.cleanup()

    def git(self, *args, repo=None):
        environment = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
        done = subprocess.run(
            ["git", "-c", "user.name=test", "-c", "user.email=test@example.invalid", *args],
            cwd=repo or self.repo, env=environment, text=True, capture_output=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        return done.stdout.strip()

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def decide(self, base, head, repo=None):
        done = subprocess.run(
            [sys.executable, str(SCRIPT), base, head, str(repo or self.repo)], text=True, capture_output=True)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn(done.stdout, ("docs_only=true\n", "docs_only=false\n"), done.stderr)
        return done.stdout.strip() == "docs_only=true"

    def change(self, files, message="değişiklik"):
        for path, text in files.items():
            self.write(path, text)
        return self.commit(message)

    # Atlanan tek durum: değişen her dosya belge.

    def test_documents_only_is_skipped(self):
        head = self.change({"docs/roadmap.md": "yeni\n", "docs/yeni/alt.md": "x\n", "README.md": "y\n",
                            "AGENTS.md": "z\n", "LICENSE": "lisans\n"})
        self.assertTrue(self.decide(self.base, head))

    def test_deleted_document_is_skipped(self):
        (self.repo / "docs/roadmap.md").unlink()
        self.assertTrue(self.decide(self.base, self.commit("belge silindi")))

    def test_rename_inside_docs_is_skipped(self):
        self.git("mv", "docs/roadmap.md", "docs/plan.md")
        self.assertTrue(self.decide(self.base, self.commit("belge taşındı")))

    def test_several_document_commits_are_skipped(self):
        self.change({"docs/a.md": "a\n"})
        head = self.change({"docs/b.md": "b\n"})
        self.assertTrue(self.decide(self.base, head))

    def test_pull_request_behind_its_base_counts_only_its_own_changes(self):
        self.git("checkout", "-q", "-b", "docs/dal")
        head = self.change({"docs/a.md": "a\n"})
        self.git("checkout", "-q", "dev")
        base = self.change({"App/Main.swift": "// tabanda ilerleyen kod\n"})
        self.assertTrue(self.decide(base, head))

    # Kod sayılan her şey koşar.

    def test_document_plus_one_code_file_runs(self):
        head = self.change({"docs/roadmap.md": "yeni\n", "App/Main.swift": "// başka\n"})
        self.assertFalse(self.decide(self.base, head))

    def test_code_in_an_earlier_commit_runs(self):
        self.change({"App/Main.swift": "// başka\n"})
        head = self.change({"docs/a.md": "a\n"})
        self.assertFalse(self.decide(self.base, head))

    def test_code_changed_and_reverted_is_an_empty_diff_and_runs(self):
        self.change({"App/Main.swift": "// başka\n"})
        head = self.change({"App/Main.swift": "// kod\n"})
        self.assertFalse(self.decide(self.base, head))

    def test_paths_that_look_like_documents_run(self):
        for path in [
            "Fixtures/vaults/sample/2026-01-02.md", "project.yml", "VERSION", ".github/workflows/ci.yml",
            ".github/scripts/x.sh", "App/Resources/Localizable.xcstrings", "Config/Signing.xcconfig",
            "App/README.md", "Packages/Core/docs/a.md", "docs.md/x.swift", "docsx/a.md", "LICENSE.txt",
            "notes.txt", "BENIOKU.MD", ".gitignore", "Tests/JournalTests/Snapshots/__Snapshots__/a.png",
            "bilinmeyen/yol", "docs ek/a.md", "satır\nsonu.md/x",
        ]:
            with self.subTest(path=path):
                head = self.change({path: "içerik\n", "docs/roadmap.md": path + "\n"})
                self.assertFalse(self.decide(self.base, head))
                self.base = head

    def test_rename_out_of_docs_runs(self):
        self.git("mv", "docs/roadmap.md", "App/roadmap.md")
        self.assertFalse(self.decide(self.base, self.commit("belge koda taşındı")))

    def test_rename_into_docs_runs(self):
        self.git("mv", "App/Main.swift", "docs/Main.swift")
        self.assertFalse(self.decide(self.base, self.commit("kod belgeye taşındı")))

    def test_deleted_code_file_runs(self):
        (self.repo / "App/Main.swift").unlink()
        self.assertFalse(self.decide(self.base, self.commit("kod silindi")))

    # Emin olunamayan durumlar koşar.

    def test_empty_diff_runs(self):
        self.assertFalse(self.decide(self.base, self.base))
        self.assertFalse(self.decide(self.base, self.commit("boş commit")))

    def test_missing_or_malformed_commits_run(self):
        head = self.change({"docs/a.md": "a\n"})
        unknown = "1234567890" * 4
        for base, tip in [(ZERO, head), (self.base, ZERO), ("", head), (self.base, ""), (unknown, head),
                          (self.base, unknown), ("dev", head), (self.base, "HEAD"), (self.base[:12], head),
                          ("--help", head), (self.base, "-z")]:
            with self.subTest(base=base, head=tip):
                self.assertFalse(self.decide(base, tip))

    def test_missing_arguments_run(self):
        for arguments in [[], ["a"]]:
            done = subprocess.run([sys.executable, str(SCRIPT), *arguments], text=True, capture_output=True)
            self.assertEqual((done.returncode, done.stdout), (0, "docs_only=false\n"))

    def test_shallow_checkout_runs(self):
        head = self.change({"docs/a.md": "a\n"})
        self.assertTrue(self.decide(self.base, head))
        shallow = Path(self.temp.name) / "shallow"
        self.git("clone", "-q", "--depth", "1", self.repo.as_uri(), str(shallow), repo=self.temp.name)
        self.assertFalse(self.decide(self.base, head, repo=shallow))
        # Taban elde olsa da kopya sığ kaldıkça karar değişmez.
        self.git("fetch", "-q", "--depth", "2", "origin", "dev", repo=shallow)
        self.assertEqual(self.git("rev-parse", self.base, repo=shallow), self.base)
        self.assertFalse(self.decide(self.base, head, repo=shallow))

    def test_unrelated_histories_run(self):
        self.git("checkout", "-q", "--orphan", "yetim")
        self.git("rm", "-rq", "--cached", ".")
        for name in ["App", "Fixtures", "README.md"]:
            subprocess.run(["rm", "-rf", str(self.repo / name)], check=True)
        head = self.commit("ortak atası olmayan dal")
        self.assertFalse(self.decide(self.base, head))

    def test_not_a_repository_runs(self):
        empty = Path(self.temp.name) / "empty"
        empty.mkdir()
        self.assertFalse(self.decide(self.base, self.base, repo=empty))


if __name__ == "__main__":
    unittest.main()
