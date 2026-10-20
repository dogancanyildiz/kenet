#!/usr/bin/env python3
"""check-catalog-keys.py'yi küçük örnek kaynak ağaçlarıyla sınar.

Korunan şey: katalogda olmayan sabit metin denetimi düşürür; `verbatim:`, değişken argüman,
enterpolasyonlu metin ve yorum düşürmez.
"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check-catalog-keys.py"


def run(source: str, keys=("Kayıtlı",)):
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "App/Resources").mkdir(parents=True)
        (root / "App/Screens").mkdir(parents=True)
        catalog = {"strings": {k: {} for k in keys}, "version": "1.0"}
        (root / "App/Resources/Localizable.xcstrings").write_text(json.dumps(catalog))
        (root / "App/Screens/View.swift").write_text(source)
        return subprocess.run(
            [sys.executable, "-I", str(SCRIPT), str(root)], capture_output=True, text=True
        )


class CatalogKeyTests(unittest.TestCase):
    def assertFails(self, source, key):
        r = run(source)
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn(repr(key), r.stderr)

    def assertPasses(self, source):
        r = run(source)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_known_key_passes(self):
        self.assertPasses('Text("Kayıtlı")\nButton("Kayıtlı") {}\n')

    def test_missing_keys_fail_for_each_call_kind(self):
        cases = [
            ('Text("Eksik")', "Eksik"),
            ('Button("Eksik") { }', "Eksik"),
            ('Label("Eksik", systemImage: "x")', "Eksik"),
            ('let s = String(localized: "Eksik")', "Eksik"),
            ('.accessibilityLabel("Eksik")', "Eksik"),
            ('let k = LocalizedStringKey("Eksik")', "Eksik"),
            ('Toggle(\n    "Eksik", isOn: $x)', "Eksik"),
            ('Text("Satır \\"tırnaklı\\"")', 'Satır "tırnaklı"'),
        ]
        for source, key in cases:
            with self.subTest(source=source):
                self.assertFails(source, key)

    def test_verbatim_variable_and_interpolation_do_not_fail(self):
        self.assertPasses(
            'Text(verbatim: "Eksik")\n'
            "Text(copy.copy)\n"
            'Text("Eksik \\(count)")\n'
            'InfoBand(kind: .error, verbatim: "Eksik")\n'
            'Text("")\n'
            'let x = myText("Eksik")\n'
            'Button(action: {}) { Text(model.title) }\n'
        )

    def test_comments_do_not_fail(self):
        self.assertPasses('// Text("Eksik")\n/* Button("Eksik") */\nText("Kayıtlı") // Text("Eksik")\n')

    def test_url_in_string_is_not_comment(self):
        self.assertFails('let u = "https://x"; Text("Eksik")', "Eksik")


if __name__ == "__main__":
    unittest.main()
