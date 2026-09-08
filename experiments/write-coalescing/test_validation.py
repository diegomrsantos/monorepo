"""Ensure corrupted archived evidence cannot pass the final dataset audit."""

import copy
import json
import pathlib
import unittest

from validate_native import validate


class EvidenceValidation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = pathlib.Path(__file__).parent
        cls.rows = [json.loads(line) for line in (root / "results/native/macos/grid.jsonl").read_text().splitlines()]
        cls.plan = json.loads((root / "plans/backend-grid.json").read_text())
        cls.manifest = json.loads((root / "results/native/macos/manifest.json").read_text())

    def test_complete_archive_passes(self):
        self.assertEqual(validate(self.rows, self.plan, self.manifest)["trials"], 672)

    def test_missing_case_cannot_disappear_from_analysis(self):
        rows = [row for row in self.rows if row["case"] != self.rows[0]["case"]]
        with self.assertRaisesRegex(ValueError, "expected 672 trials"):
            validate(rows, self.plan, self.manifest)

    def test_invalid_evidence_is_rejected(self):
        changes = {
            "seed": -1,
            "binary_sha256": "wrong executable",
            "verified_bytes": self.rows[0]["bytes_per_write"],
            "mib_per_second": self.rows[0]["mib_per_second"] * 2,
        }
        for key, value in changes.items():
            with self.subTest(key=key):
                rows = copy.deepcopy(self.rows)
                rows[0][key] = value
                with self.assertRaises(ValueError):
                    validate(rows, self.plan, self.manifest)


if __name__ == "__main__":
    unittest.main()
