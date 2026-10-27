#!/usr/bin/env python3
"""case-durations.py sıralamasını, toplamını, bozuk girdide sessiz geçişini ve bilinmeyen şemada uyarısını sınar."""

import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "case-durations.py"

spec = importlib.util.spec_from_file_location("case_durations", SCRIPT)
case_durations = importlib.util.module_from_spec(spec)
spec.loader.exec_module(case_durations)

DOCUMENT = {
    "devices": [],
    "testNodes": [
        {
            "nodeType": "Test Plan",
            "name": "Journal_iOS",
            "children": [
                {
                    "nodeType": "Unit test bundle",
                    "name": "JournalUITests",
                    "children": [
                        {
                            "nodeType": "Test Suite",
                            "name": "AccessibilityAuditUITests",
                            "children": [
                                {
                                    "nodeType": "Test Case",
                                    "name": "testTasks()",
                                    "nodeIdentifier": "AccessibilityAuditUITests/testTasks()",
                                    "durationInSeconds": 36.2,
                                    "duration": "36sn",
                                    "result": "Passed",
                                },
                                {
                                    "nodeType": "Test Case",
                                    "name": "testToday()",
                                    "nodeIdentifier": "AccessibilityAuditUITests/testToday()",
                                    "durationInSeconds": 19.0,
                                    "result": "Failed",
                                    "children": [{"nodeType": "Failure Message", "name": "x"}],
                                },
                            ],
                        },
                        {
                            "nodeType": "Test Case",
                            "name": "testSkipped()",
                            "nodeIdentifier": "Other/testSkipped()",
                            "duration": "0,23s",
                            "result": "Skipped",
                        },
                    ],
                }
            ],
        }
    ],
}


class Rows(unittest.TestCase):
    def test_longest_first_and_only_test_cases(self):
        table = case_durations.rows(DOCUMENT)
        self.assertEqual(
            [row[2] for row in table],
            ["AccessibilityAuditUITests/testTasks()", "AccessibilityAuditUITests/testToday()", "Other/testSkipped()"],
        )
        self.assertEqual(table[0][:2], (36.2, "Passed"))
        # Sayısal süre yoksa 0 sayılır; yerel biçimli "0,23s" ayrıştırılmaz.
        self.assertEqual(table[2][0], 0.0)

    def test_render_total(self):
        text = case_durations.render(case_durations.rows(DOCUMENT), "Arayüz")
        self.assertIn("== Arayüz: vaka süreleri", text)
        self.assertIn("-- 3 vaka, toplam 55.2 sn", text)
        self.assertRegex(text, r"\n\s+36\.2  Passed\s+AccessibilityAuditUITests/testTasks\(\)")

    def test_markdown_caps_rows(self):
        many = {"testNodes": [
            {"nodeType": "Test Case", "nodeIdentifier": f"S/t{i}()", "durationInSeconds": i, "result": "Passed"}
            for i in range(30)
        ]}
        text = case_durations.render_markdown(case_durations.rows(many), "Çok")
        self.assertEqual(text.count("| `S/t"), case_durations.SUMMARY_ROWS)
        self.assertIn("5 vaka daha", text)
        self.assertIn("30 vaka, toplam 435.0 sn", text)


class Main(unittest.TestCase):
    def run_script(self, stdin, env_extra=None, args=()):
        env = dict(os.environ, **(env_extra or {}))
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), *args], input=stdin, capture_output=True, text=True, env=env)

    def test_stdin_and_step_summary(self):
        with tempfile.TemporaryDirectory() as folder:
            summary = Path(folder) / "summary.md"
            done = self.run_script(json.dumps(DOCUMENT), {"GITHUB_STEP_SUMMARY": str(summary)}, ("--title", "Arayüz"))
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("-- 3 vaka, toplam 55.2 sn", done.stdout)
            self.assertIn("### Arayüz", summary.read_text(encoding="utf-8"))

    def test_broken_input_warns_and_passes(self):
        done = self.run_script("not json")
        self.assertEqual(done.returncode, 0)
        self.assertIn("::warning::Vaka süreleri okunamadı", done.stdout)

    def test_missing_file_warns_and_passes(self):
        done = self.run_script("", args=("/nonexistent/tests.json",))
        self.assertEqual(done.returncode, 0)
        self.assertIn("::warning::", done.stdout)

    def test_known_schema_gives_no_warning(self):
        done = self.run_script(json.dumps(DOCUMENT))
        self.assertEqual(done.returncode, 0)
        self.assertNotIn("::warning::", done.stdout)

    def test_unknown_schema_warns_and_passes(self):
        # Anahtar adları değişmiş belge: ne testNodes ne "Test Case" düğümü.
        renamed = json.loads(json.dumps(DOCUMENT).replace('"nodeType"', '"kind"').replace('"testNodes"', '"nodes"'))
        done = self.run_script(json.dumps(renamed), args=("--title", "Arayüz"))
        self.assertEqual(done.returncode, 0)
        self.assertIn("::warning::Vaka süreleri (Arayüz): girdide testNodes yok", done.stdout)
        self.assertIn('"Test Case" düğümü yok', done.stdout)
        self.assertIn("-- 0 vaka, toplam 0.0 sn", done.stdout)

    def test_test_nodes_without_test_cases_warn(self):
        renamed = json.loads(json.dumps(DOCUMENT).replace('"Test Case"', '"Test Method"'))
        done = self.run_script(json.dumps(renamed))
        self.assertEqual(done.returncode, 0)
        self.assertIn("::warning::", done.stdout)
        self.assertIn('"Test Case" düğümü yok', done.stdout)
        self.assertNotIn("testNodes yok", done.stdout)

    def test_empty_document_warns(self):
        for text in ["{}", "[]"]:
            with self.subTest(text=text):
                done = self.run_script(text)
                self.assertEqual(done.returncode, 0)
                self.assertIn("::warning::", done.stdout)


if __name__ == "__main__":
    unittest.main()
