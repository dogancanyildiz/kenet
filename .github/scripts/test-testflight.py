#!/usr/bin/env python3
"""TestFlight cleanup regression tests with fake git/Xcode; no build or upload."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


FAKE_TOOL = r'''#!/usr/bin/env python3
import os
from pathlib import Path
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["TEST_ROOT"])
if tool == "git":
    if "remove" in args:
        (root / "removed-tree").write_text(args[-1])
    elif "add" in args:
        tree = Path(args[-2])
        (tree / "Config").mkdir(parents=True)
        (tree / "project.yml").write_text("APP_BUNDLE_IDENTIFIER: example.test\n")
        (tree / "VERSION").write_text("0.9.0\n")
    elif "--abbrev-ref" in args:
        print("dev")
    elif "--count" in args:
        print("42")
    elif "rev-parse" in args:
        print("abc123")
elif tool == "xcodebuild":
    if "archive" in args:
        archive = Path(args[args.index("-archivePath") + 1])
        (root / "work").write_text(str(archive.parent))
        assert "-derivedDataPath" in args, "archive uses global DerivedData"
        derived = Path(args[args.index("-derivedDataPath") + 1])
        assert derived == archive.parent / "DerivedData", derived
        derived.mkdir()
        (derived / "build-product").write_text("temporary build")
        app = archive / "Products/Applications/Kenet.app"
        app.mkdir(parents=True)
        (app / "PrivacyInfo.xcprivacy").touch()
        if os.environ["TEST_MODE"] == "archive-failure":
            print("error: simulated archive failure")
            sys.exit(1)
        (root / "signing").write_text(" ".join(args))
    else:
        (root / "uploaded").touch()
        if os.environ["TEST_MODE"] == "upload-failure":
            print("error: simulated upload failure")
            sys.exit(1)
elif tool == "PlistBuddy":
    key = args[1].split(":")[-1]
    print({"CFBundleIdentifier": "example.test", "CFBundleShortVersionString": "0.9.0",
           "CFBundleVersion": "42", "UIDeviceFamily": "Array { 1 }",
           "LSSupportsOpeningDocumentsInPlace": "true"}.get(key, "true"))
'''


class TestFlightCleanupTests(unittest.TestCase):
    def run_case(self, mode, arguments, expected_status, answer=""):
        source = Path(os.environ.get("TESTFLIGHT_SCRIPT", Path(__file__).with_name("testflight.sh")))
        with tempfile.TemporaryDirectory(prefix="testflight-regression-") as directory:
            root = Path(directory)
            scripts = root / ".github/scripts"
            scripts.mkdir(parents=True)
            # Replace only the absolute system-tool dependency in this isolated test copy.
            subject = scripts / "testflight.sh"
            subject.write_text(source.read_text().replace("/usr/libexec/PlistBuddy", "PlistBuddy"))
            (root / "Config").mkdir()
            (root / "Config/Local.xcconfig").write_text("DEVELOPMENT_TEAM = ABCDE12345\n")
            tools = root / "tools"
            tools.mkdir()
            for name in ("git", "xcodegen", "xcodebuild", "PlistBuddy"):
                executable = tools / name
                executable.write_text(FAKE_TOOL)
                executable.chmod(0o755)
            temporary = root / "tmp"
            temporary.mkdir()
            global_derived = root / "home/Library/Developer/Xcode/DerivedData/Journal-existing"
            global_derived.mkdir(parents=True)
            sentinel = global_derived / "keep"
            sentinel.write_text("user build")
            environment = dict(os.environ, TEST_ROOT=str(root), TEST_MODE=mode,
                               TMPDIR=str(temporary), HOME=str(root / "home"),
                               PATH=str(tools) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["sh", str(subject), *arguments], env=environment,
                                    input=answer, text=True, capture_output=True)
            self.assertEqual(result.returncode, expected_status, result.stdout + result.stderr)
            work = Path((root / "work").read_text())
            self.assertFalse(work.exists(), "archive and DerivedData were not cleaned")
            self.assertEqual((root / "removed-tree").read_text(), str(work / "kaynak"))
            self.assertEqual(sentinel.read_text(), "user build")
            self.assertEqual((root / "uploaded").exists(), mode in ("upload", "upload-failure"))
            if mode == "check":
                self.assertIn("Denetim geçti", result.stdout)
                self.assertIn("CODE_SIGNING_ALLOWED=NO", (root / "signing").read_text())
            if mode.endswith("failure"):
                log = "arsiv" if mode == "archive-failure" else "yukleme"
                self.assertIn("simulated", (temporary / f"kenet-testflight-{log}.log").read_text())

    def test_check_cleanup(self):
        self.run_case("check", ["--check"], 0)

    def test_archive_failure_cleanup(self):
        self.run_case("archive-failure", ["--check"], 1)

    def test_cancel_cleanup(self):
        self.run_case("cancel", [], 0, "H\n")

    def test_yes_upload_cleanup(self):
        self.run_case("upload", ["--yes"], 0)

    def test_upload_failure_cleanup(self):
        self.run_case("upload-failure", ["--yes"], 1)


if __name__ == "__main__":
    unittest.main()
