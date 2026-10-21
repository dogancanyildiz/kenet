#!/usr/bin/env python3
"""Exercise the Mac recording workflow with a fake xcodebuild; no Xcode required."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
workflow = json.loads(subprocess.check_output(
    ["ruby", "-ryaml", "-rjson", "-e",
     "puts JSON.generate(YAML.load_file(ARGV[0]))",
     str(ROOT / ".github/workflows/record-snapshots.yml")], text=True))
record_step = next(step for step in workflow["jobs"]["mac"]["steps"]
                   if "SNAPSHOT_TESTING_RECORD" in step.get("env", {}))


class MacRecordingTests(unittest.TestCase):
    def run_recording(self, first=65, verify=0, empty=False):
        with tempfile.TemporaryDirectory(prefix=".d7-test-", dir=ROOT) as directory:
            root = Path(directory)
            scripts = root / ".github/scripts"
            scripts.mkdir(parents=True)
            if empty:
                (scripts / "snapshot-suites.sh").write_text("exit 0\n")
                suites = []
            else:
                # Use the real suite-discovery script and the real Swift suite declarations.
                suites = subprocess.check_output(
                    ["sh", str(ROOT / ".github/scripts/snapshot-suites.sh"), "--mac"],
                    text=True).splitlines()
                (scripts / "snapshot-suites.sh").write_text(
                    "printf '%s\\n' " + " ".join(suites) + "\n")
            fake = root / "xcodebuild"
            fake.write_text("""#!/bin/sh
printf '%s|%s|%s|%s\n' "$SNAPSHOT_TESTING_RECORD" "$TEST_RUNNER_SNAPSHOT_TESTING_RECORD" "$CI" "$*" >> "$CALL_LOG"
if [ "$1" = test ]; then exit "$FIRST_STATUS"; fi
exit "$VERIFY_STATUS"
""")
            fake.chmod(0o755)
            log = root / "calls"
            env = dict(os.environ, **record_step["env"])
            env.update(PATH=str(root) + os.pathsep + os.environ["PATH"],
                       CALL_LOG=str(log), FIRST_STATUS=str(first),
                       VERIFY_STATUS=str(verify))
            result = subprocess.run(["sh", "-eu", "-c", record_step["run"]],
                                    cwd=root, env=env, capture_output=True, text=True)
            calls = log.read_text().splitlines() if log.exists() else []
            return result, calls, suites

    def test_expected_record_failure_then_verify(self):
        result, calls, suites = self.run_recording()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[0].startswith("all|all|true|test "))
        self.assertTrue(calls[1].startswith("never|never|true|test-without-building "))
        self.assertGreater(len(suites), 0)
        for call in calls:
            selected = [arg for arg in call.split() if arg.startswith("-only-testing:")]
            self.assertEqual(selected, ["-only-testing:JournalTests_macOS/" + s for s in suites])
            self.assertIn("-scheme Journal_macOS", call)
            self.assertIn("-derivedDataPath .dd/mac-snapshots", call)

    def test_successful_record_still_verifies(self):
        result, calls, _ = self.run_recording(first=0)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(len(calls), 2)

    def test_verify_failure_is_not_hidden(self):
        result, _, _ = self.run_recording(verify=65)
        self.assertEqual(result.returncode, 65)

    def test_build_failure_cannot_pass_without_verification(self):
        result, _, _ = self.run_recording(first=66, verify=66)
        self.assertEqual(result.returncode, 66)

    def test_empty_suites_fail_before_xcodebuild(self):
        result, calls, _ = self.run_recording(empty=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(calls, [])
        self.assertIn("Mac görüntü kümesi bulunamadı", result.stdout)


if __name__ == "__main__":
    unittest.main()
