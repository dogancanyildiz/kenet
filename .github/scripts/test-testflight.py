#!/usr/bin/env python3
"""TestFlight script regression tests with fake git/Xcode/security; no build, signing or upload."""

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
with (root / "calls").open("a") as calls:
    calls.write(tool + " " + " ".join(args) + "\n")
if tool == "git":
    if "--is-shallow-repository" in args:
        print(os.environ.get("TEST_SHALLOW", "false"))
    elif "merge-base" in args:
        sys.exit(int(os.environ.get("TEST_NOT_ANCESTOR", "0")))
    elif "remove" in args:
        (root / "removed-tree").write_text(args[-1])
    elif "add" in args:
        tree = Path(args[-2])
        (tree / "Config").mkdir(parents=True)
        (tree / "project.yml").write_text("APP_BUNDLE_IDENTIFIER: example.test\n")
        (tree / "VERSION").write_text("0.9.0\n")
    elif "--abbrev-ref" in args:
        print(os.environ.get("TEST_BRANCH", "dev"))
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
        (root / "signing").write_text(" ".join(args))
        if os.environ["TEST_MODE"] == "archive-failure":
            # Real xcodebuild logs echo the full command line, credentials included.
            print("Command line invocation: xcodebuild " + " ".join(args))
            print("error: simulated archive failure: " + " ".join(args))
            sys.exit(1)
    else:
        (root / "uploaded").touch()
        (root / "export-args").write_text(" ".join(args))
        options = Path(args[args.index("-exportOptionsPlist") + 1])
        (root / "export-options").write_text(options.read_text())
        if os.environ["TEST_MODE"] == "upload-failure":
            print("Command line invocation: xcodebuild " + " ".join(args))
            print("error: simulated upload failure: " + " ".join(args))
            sys.exit(1)
elif tool == "security":
    assert args[:4] == ["find-identity", "-v", "-p", "codesigning"], args
    print(os.environ.get("TEST_IDENTITIES", ""))
elif tool == "PlistBuddy":
    key = args[1].split(":")[-1]
    print({"CFBundleIdentifier": "example.test", "CFBundleShortVersionString": "0.9.0",
           "CFBundleVersion": "42", "UIDeviceFamily": "Array {\n    1\n    2\n}",
           "UISupportedInterfaceOrientations~ipad": "Array {\n" + "".join(
               f"    UIInterfaceOrientation{name}\n"
               for name in ("Portrait", "PortraitUpsideDown", "LandscapeLeft", "LandscapeRight")) + "}",
           "LSSupportsOpeningDocumentsInPlace": "true"}.get(key, "true"))
'''


TEAM = "ABCDE12345"
KEY_ID = "KEY1234567"
ISSUER = "11111111-2222-3333-4444-555555555555"
DISTRIBUTION = f'  1) 0A1B2C "Apple Distribution: Example Person ({TEAM})"'
DEVELOPMENT = '  2) 3D4E5F "Apple Development: Example Person (XYZ9876543)"'
BOTH_IDENTITIES = DISTRIBUTION + "\n" + DEVELOPMENT + "\n     2 valid identities found"


class TestFlightCleanupTests(unittest.TestCase):
    def run_case(self, mode, arguments, expected_status, answer="", extra_env=None, local_config=True,
                 inspect=None, started=True):
        source = Path(os.environ.get("TESTFLIGHT_SCRIPT", Path(__file__).with_name("testflight.sh")))
        with tempfile.TemporaryDirectory(prefix="testflight-regression-") as directory:
            root = Path(directory)
            scripts = root / ".github/scripts"
            scripts.mkdir(parents=True)
            # Replace only the absolute system-tool dependency in this isolated test copy.
            subject = scripts / "testflight.sh"
            subject.write_text(source.read_text().replace("/usr/libexec/PlistBuddy", "PlistBuddy"))
            (root / "Config").mkdir()
            if local_config:
                (root / "Config/Local.xcconfig").write_text("DEVELOPMENT_TEAM = " + TEAM + "\n")
            (root / "keychain-db").write_text("fake keychain")
            (root / "AuthKey.p8").write_text("fake key")
            tools = root / "tools"
            tools.mkdir()
            for name in ("git", "xcodegen", "xcodebuild", "PlistBuddy", "security"):
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
            environment.pop("GITHUB_ACTIONS", None)
            environment.pop("GITHUB_OUTPUT", None)
            # "ROOT/<name>" in arguments and environment values points into this temporary root.
            in_root = lambda value: str(root / value[5:]) if value.startswith("ROOT/") else value
            environment.update({key: in_root(value) for key, value in (extra_env or {}).items()})
            arguments = [in_root(argument) for argument in arguments]
            result = subprocess.run(["sh", str(subject), *arguments], env=environment,
                                    input=answer, text=True, capture_output=True)
            self.assertEqual(result.returncode, expected_status, result.stdout + result.stderr)
            if inspect:
                inspect(result, root)
            if not started:
                self.assertFalse((root / "work").exists(), "script archived despite refusing")
                self.assertFalse((root / "uploaded").exists())
                return
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
            if "--ci" not in arguments and (root / "signing").exists():
                # Local runs keep the Xcode account path: no API key, no command-line team.
                self.assertNotIn("-authentication", (root / "signing").read_text())
                self.assertNotIn("DEVELOPMENT_TEAM", (root / "signing").read_text())

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

    # --ci: CI upload (testflight.yml) with an API key and a prepared keychain.

    CI_ARGUMENTS = ["--ci", "--keychain", "ROOT/keychain-db", "--api-key", "ROOT/AuthKey.p8",
                    "--api-key-id", KEY_ID, "--api-issuer", ISSUER]

    def ci_case(self, mode, expected_status, identities=BOTH_IDENTITIES, inspect=None, started=True,
                arguments=None, **environment):
        extra = {"TEST_IDENTITIES": identities, "GITHUB_ACTIONS": "true",
                 "GITHUB_OUTPUT": "ROOT/github-output", **environment}
        self.run_case(mode, self.CI_ARGUMENTS if arguments is None else arguments, expected_status,
                      extra_env=extra, local_config=False, inspect=inspect, started=started)

    def test_ci_upload_uses_api_key_and_keychain_team(self):
        def inspect(result, root):
            archive = (root / "signing").read_text()
            export = (root / "export-args").read_text()
            for arguments in (archive, export):
                self.assertIn("-allowProvisioningUpdates", arguments)
                self.assertIn(f"-authenticationKeyPath {root / 'AuthKey.p8'}", arguments)
                self.assertIn(f"-authenticationKeyID {KEY_ID}", arguments)
                self.assertIn(f"-authenticationKeyIssuerID {ISSUER}", arguments)
            self.assertIn(f"DEVELOPMENT_TEAM={TEAM}", archive)
            self.assertNotIn("CODE_SIGNING_ALLOWED=NO", archive)
            options = (root / "export-options").read_text()
            self.assertIn(f"<string>{TEAM}</string>", options)
            self.assertIn("<string>upload</string>", options)
            # The team comes from the distribution identity, masked before anything else prints it.
            self.assertTrue(result.stdout.startswith(f"::add-mask::{TEAM}\n"), result.stdout)
            self.assertEqual(result.stdout.count(TEAM), 1, result.stdout)
            self.assertNotIn("yüklensin mi", result.stdout)
            self.assertIn("version=0.9.0\nbuild=42\n", (root / "github-output").read_text())
            self.assertNotIn("Apple Development kimliği yok", result.stderr)
            calls = (root / "calls").read_text()
            self.assertIn("merge-base --is-ancestor HEAD origin/dev", calls)
            self.assertIn(f"find-identity -v -p codesigning {root / 'keychain-db'}", calls)

        self.ci_case("upload", 0, inspect=inspect)

    def assert_ci_log_redacted(self, log_name):
        def inspect(result, root):
            log = (root / "tmp" / f"kenet-testflight-{log_name}.log").read_text()
            self.assertIn("simulated", log)
            for secret in (TEAM, KEY_ID, ISSUER):
                self.assertNotIn(secret, log)
                self.assertNotIn(secret, result.stderr)
            self.assertIn("-authenticationKeyID ASC_KEY_ID", log)
            self.assertIn("-authenticationKeyIssuerID ASC_ISSUER_ID", log)
        return inspect

    def test_ci_archive_failure_log_is_redacted(self):
        self.ci_case("archive-failure", 1, inspect=self.assert_ci_log_redacted("arsiv"))

    def test_ci_upload_failure_log_is_redacted(self):
        self.ci_case("upload-failure", 1, inspect=self.assert_ci_log_redacted("yukleme"))

    def test_ci_without_development_identity_warns_and_uploads(self):
        def inspect(result, root):
            self.assertIn("Apple Development kimliği yok", result.stderr)
        self.ci_case("upload", 0, identities=DISTRIBUTION + "\n     1 valid identities found", inspect=inspect)

    def test_ci_refuses_without_distribution_identity(self):
        def inspect(result, root):
            self.assertIn("Apple Distribution kimliği yok", result.stderr)
        self.ci_case("refused", 1, identities=DEVELOPMENT + "\n     1 valid identities found",
                     inspect=inspect, started=False)

    def test_ci_refuses_shallow_clone(self):
        def inspect(result, root):
            self.assertIn("sığ kopya", result.stderr)
        self.ci_case("refused", 1, inspect=inspect, started=False, TEST_SHALLOW="true")

    def test_ci_refuses_commit_outside_dev(self):
        def inspect(result, root):
            self.assertIn("origin/dev geçmişinde değil", result.stderr)
        self.ci_case("refused", 1, inspect=inspect, started=False, TEST_NOT_ANCESTOR="1")

    def test_ci_refuses_other_branch(self):
        self.ci_case("refused", 1, started=False, TEST_BRANCH="feat/example")

    def test_ci_option_errors(self):
        cases = {
            "missing issuer": self.CI_ARGUMENTS[:-2],
            "malformed key id": self.CI_ARGUMENTS[:-3] + ["key-123", "--api-issuer", ISSUER],
            "malformed issuer": self.CI_ARGUMENTS[:-1] + ["not-a-uuid"],
            "missing keychain file": ["--ci", "--keychain", "ROOT/none"] + self.CI_ARGUMENTS[3:],
            "ci with check": ["--check"] + self.CI_ARGUMENTS,
            "api key without ci": self.CI_ARGUMENTS[1:],
            "option without value": ["--ci", "--keychain"],
        }
        for name, arguments in cases.items():
            with self.subTest(name):
                def inspect(result, root):
                    for secret in (KEY_ID, ISSUER):
                        self.assertNotIn(secret, result.stderr)
                    self.assertFalse((root / "calls").exists(), "a tool ran before options were checked")
                self.ci_case("refused", 2, arguments=arguments, inspect=inspect, started=False)


if __name__ == "__main__":
    unittest.main()
