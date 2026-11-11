#!/usr/bin/env python3
"""a11y-issues.py: düşen vakaları, A11Y başlıklarını ve hata iletilerini seçer; eksik paket 0 ile çıkar."""

import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("a11y_issues", HERE / "a11y-issues.py")
a11y_issues = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a11y_issues)

TESTS = {
    "testNodes": [
        {
            "nodeType": "Test Plan",
            "children": [
                {
                    "nodeType": "Test Suite",
                    "children": [
                        {
                            "nodeType": "Test Case",
                            "nodeIdentifier": "QuickEntryNameChipAccessibilityUITests/testChips()",
                            "result": "Failed",
                            "children": [
                                {"nodeType": "Failure Message", "name": "Hit area is too small"},
                                {"nodeType": "Device", "children": [
                                    {"nodeType": "Failure Message", "name": "failed - A11Y (x): touch target"}
                                ]},
                            ],
                        },
                        {"nodeType": "Test Case", "nodeIdentifier": "Other/testPasses()", "result": "Passed"},
                    ],
                }
            ],
        }
    ]
}

ACTIVITIES = {
    "testRuns": [
        {
            "activities": [
                {"title": "Set Up", "childActivities": [{"title": "Launch"}]},
                {
                    "title": "Audit",
                    "childActivities": [
                        {"title": "A11Y issue (quickEntryNames): hitRegion — '' 'Good morning.' (5, 74, 92, 16)"}
                    ],
                },
                {"title": "A11Y issue (quickEntryNames): textClipped — 'sectionHeader' 'Timeline' (16, 776, 67, 20)"},
            ]
        }
    ]
}


class A11yIssuesTests(unittest.TestCase):
    def test_failed_cases_keep_only_failures_with_nested_messages(self):
        cases = a11y_issues.failed_cases(TESTS)
        self.assertEqual(
            cases,
            [("QuickEntryNameChipAccessibilityUITests/testChips()",
              ["Hit area is too small", "failed - A11Y (x): touch target"])])

    def test_issue_titles_walk_nested_activities_in_order(self):
        titles = a11y_issues.issue_titles(ACTIVITIES)
        self.assertEqual(len(titles), 2)
        self.assertIn("hitRegion", titles[0])
        self.assertIn("textClipped", titles[1])

    def test_unknown_schema_yields_nothing(self):
        self.assertEqual(a11y_issues.failed_cases({}), [])
        self.assertEqual(a11y_issues.issue_titles({}), [])

    def test_missing_bundle_warns_and_exits_zero(self):
        with tempfile.TemporaryDirectory() as directory:
            output = io.StringIO()
            with redirect_stdout(output):
                code = a11y_issues.main([str(Path(directory) / "none.xcresult"), "--title", "T"])
        self.assertEqual(code, 0)
        self.assertIn("::warning::T:", output.getvalue())


if __name__ == "__main__":
    unittest.main()
