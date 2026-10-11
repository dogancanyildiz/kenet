#!/usr/bin/env python3
"""ci-gate.py kararını her sonuç birleşimi için sınar ve iş akışının ona doğru bağlandığını denetler.

Korunan şey: düşen ya da iptal olan bir iş hiçbir koşulda yeşil "ci" üretmez; atlanan iş yalnız
belge PR'ında ve yalnız atlanabilir işler için başarı sayılır.
"""

import importlib.util
import itertools
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / "ci-gate.py"
WORKFLOW = HERE.parent / "workflows" / "ci.yml"

spec = importlib.util.spec_from_file_location("ci_gate", SCRIPT)
ci_gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci_gate)

RESULTS = ["success", "failure", "cancelled", "skipped"]
NEVER_SKIPPED = ["changes", "lint"]
SKIPPABLE = ["core-macos", "core-linux", "app-macos", "app-ios", "app-ios-snapshots"]
JOBS = NEVER_SKIPPED + SKIPPABLE
# İş akışının verebileceği ve veremeyeceği "yalnız belge" değerleri; yalnız tam "true" atlatır.
DOCS_ONLY_VALUES = ["true", "false", "", "True", "TRUE", "1", "yes", " true", "true\n", "null"]


def needs(results):
    return {job: {"result": result, "outputs": {}} for job, result in results.items()}


def run(results, docs_only, arguments=NEVER_SKIPPED, raw=None):
    environment = dict(os.environ, DOCS_ONLY=docs_only, NEEDS=raw if raw is not None else json.dumps(needs(results)))
    done = subprocess.run([sys.executable, str(SCRIPT), *arguments], env=environment, text=True, capture_output=True)
    return done.returncode, done.stdout + done.stderr


class GateDecisionTests(unittest.TestCase):
    def passes(self, results, docs_only):
        return ci_gate.evaluate(needs(results), docs_only, set(NEVER_SKIPPED)) == []

    def test_every_combination_of_results(self):
        """4^7 sonuç birleşimi x iki durum; beklenti betikten bağımsız yazılmıştır."""
        checked = 0
        for combination in itertools.product(RESULTS, repeat=len(JOBS)):
            results = dict(zip(JOBS, combination))
            values = set(combination)
            all_green = values == {"success"}
            nothing_red = values <= {"success", "skipped"}
            gates_ran = all(results[job] == "success" for job in NEVER_SKIPPED)
            self.assertEqual(self.passes(results, "false"), all_green, results)
            self.assertEqual(self.passes(results, "true"), nothing_red and gates_ran, results)
            checked += 2
        self.assertEqual(checked, 2 * 4 ** len(JOBS))

    def test_failed_or_cancelled_job_never_passes(self):
        for job, bad, docs_only in itertools.product(JOBS, ["failure", "cancelled"], DOCS_ONLY_VALUES):
            for others in ["success", "skipped"]:
                results = dict.fromkeys(JOBS, others)
                results.update(dict.fromkeys(NEVER_SKIPPED, "success"))
                results[job] = bad
                with self.subTest(job=job, result=bad, docs_only=docs_only, others=others):
                    self.assertFalse(self.passes(results, docs_only))

    def test_skipped_job_passes_only_for_a_documents_only_change(self):
        for job in SKIPPABLE:
            results = dict.fromkeys(JOBS, "success")
            results[job] = "skipped"
            for docs_only in DOCS_ONLY_VALUES:
                with self.subTest(job=job, docs_only=docs_only):
                    self.assertEqual(self.passes(results, docs_only), docs_only == "true")

    def test_documents_only_run_passes_with_code_jobs_skipped(self):
        results = dict.fromkeys(SKIPPABLE, "skipped")
        results.update(dict.fromkeys(NEVER_SKIPPED, "success"))
        self.assertTrue(self.passes(results, "true"))
        self.assertFalse(self.passes(results, "false"))

    def test_jobs_that_always_run_may_not_be_skipped(self):
        for job in NEVER_SKIPPED:
            results = dict.fromkeys(SKIPPABLE, "skipped")
            results.update(dict.fromkeys(NEVER_SKIPPED, "success"))
            results[job] = "skipped"
            with self.subTest(job=job):
                self.assertFalse(self.passes(results, "true"))

    def test_failed_change_detection_skips_everything_and_fails(self):
        # "changes" düşünce ona bağlı işler atlanır ve çıktısı boş kalır.
        results = dict.fromkeys(SKIPPABLE, "skipped")
        results.update({"changes": "failure", "lint": "success"})
        for docs_only in DOCS_ONLY_VALUES:
            self.assertFalse(self.passes(results, docs_only))

    def test_unknown_or_missing_results_fail(self):
        for value in ["", "neutral", "SUCCESS", "success ", None, 0, True]:
            results = dict.fromkeys(JOBS, "success")
            results["app-macos"] = value
            for docs_only in ["true", "false"]:
                with self.subTest(value=value, docs_only=docs_only):
                    self.assertFalse(self.passes(results, docs_only))
        green = needs(dict.fromkeys(JOBS, "success"))
        for broken in [{}, "success", "skipped", [], None]:
            entries = dict(green, **{"core-linux": broken})
            self.assertNotEqual(ci_gate.evaluate(entries, "true", set(NEVER_SKIPPED)), [], broken)

    def test_missing_gate_job_or_empty_input_fails(self):
        for job in NEVER_SKIPPED:
            results = dict.fromkeys(JOBS, "success")
            del results[job]
            self.assertFalse(self.passes(results, "true"), job)
            self.assertFalse(self.passes(results, "false"), job)
        for empty in [{}, None, [], "", "success"]:
            self.assertNotEqual(ci_gate.evaluate(empty, "true", set(NEVER_SKIPPED)), [], empty)


class GateCommandTests(unittest.TestCase):
    """Çıkış kodu: iş akışının gördüğü tek şey."""

    def test_exit_codes(self):
        green = dict.fromkeys(JOBS, "success")
        docs = dict(dict.fromkeys(SKIPPABLE, "skipped"), changes="success", lint="success")
        cases = [
            ("hepsi başarılı", green, "false", 0),
            ("hepsi başarılı, belge", green, "true", 0),
            ("belge PR'ı, kod işleri atlandı", docs, "true", 0),
            ("kod PR'ında atlanan iş", docs, "false", 1),
            ("çıktı boşken atlanan iş", docs, "", 1),
            ("düşen iş", dict(green, **{"app-ios": "failure"}), "false", 1),
            ("belge PR'ında düşen iş", dict(docs, **{"app-ios": "failure"}), "true", 1),
            ("belge PR'ında iptal olan iş", dict(docs, **{"core-linux": "cancelled"}), "true", 1),
            ("belge PR'ında düşen biçim işi", dict(docs, lint="failure"), "true", 1),
            ("belge PR'ında atlanan biçim işi", dict(docs, lint="skipped"), "true", 1),
        ]
        for name, results, docs_only, expected in cases:
            with self.subTest(name):
                code, output = run(results, docs_only)
                self.assertEqual(code, expected, output)

    def test_unreadable_input_fails(self):
        for raw in ["", "{", "null", "[]", "{}", '"success"']:
            with self.subTest(raw=raw):
                self.assertEqual(run({}, "true", raw=raw)[0], 1)

    def test_missing_environment_or_arguments_fail(self):
        green = dict.fromkeys(JOBS, "success")
        self.assertEqual(run(green, "true", arguments=[])[0], 1)
        environment = {key: value for key, value in os.environ.items() if key not in ("NEEDS", "DOCS_ONLY")}
        done = subprocess.run([sys.executable, str(SCRIPT), *NEVER_SKIPPED], env=environment, capture_output=True)
        self.assertEqual(done.returncode, 1)


class WorkflowWiringTests(unittest.TestCase):
    """ci.yml birleştiriciyi doğru besliyor mu (YAML kitaplığı gerektirmeyen satır okuması)."""

    @classmethod
    def setUpClass(cls):
        cls.jobs = {}
        current = None
        in_jobs = False
        for line in WORKFLOW.read_text().splitlines():
            if re.fullmatch(r"\S.*", line):
                in_jobs = line.rstrip() == "jobs:"
                continue
            if not in_jobs:
                continue
            header = re.fullmatch(r"  ([A-Za-z0-9_-]+):\s*", line)
            if header:
                current = cls.jobs.setdefault(header.group(1), {})
                continue
            field = re.fullmatch(r"    ([a-z-]+):\s*(.*)", line)
            if field and current is not None:
                current[field.group(1)] = field.group(2).strip()
        cls.gate_needs = [name.strip() for name in cls.jobs["ci"]["needs"].strip("[]").split(",")]
        command = re.search(r"run: python3 \.github/scripts/ci-gate\.py(.*)", WORKFLOW.read_text())
        cls.gate_arguments = command.group(1).split()

    def test_jobs_in_this_test_match_the_workflow(self):
        self.assertEqual(sorted(self.gate_needs), sorted(JOBS))
        self.assertEqual(sorted(self.gate_arguments), sorted(NEVER_SKIPPED))

    def test_gate_always_runs_and_waits_for_every_blocking_job(self):
        self.assertEqual(self.jobs["ci"].get("if"), "always()")
        self.assertEqual(self.jobs["ci"].get("name"), "ci")
        blocking = [name for name, job in self.jobs.items()
                    if name != "ci" and job.get("continue-on-error") != "true"]
        self.assertEqual(sorted(self.gate_needs), sorted(blocking))

    def test_only_document_skipping_can_skip_a_job(self):
        for name in self.gate_needs:
            job = self.jobs[name]
            with self.subTest(job=name):
                if name in self.gate_arguments:
                    self.assertNotIn("if", job)
                    self.assertNotIn("needs", job)
                else:
                    self.assertEqual(job.get("if"), "needs.changes.outputs.docs_only != 'true'")
                    self.assertEqual(job.get("needs"), "changes")

    def test_gate_reads_results_and_the_documents_only_flag(self):
        text = WORKFLOW.read_text()
        self.assertIn("NEEDS: ${{ toJSON(needs) }}", text)
        self.assertIn("DOCS_ONLY: ${{ needs.changes.outputs.docs_only }}", text)
        self.assertEqual(self.jobs["changes"].get("outputs"), "")
        self.assertIn("      docs_only: ${{ steps.detect.outputs.docs_only }}", text)


if __name__ == "__main__":
    unittest.main()
