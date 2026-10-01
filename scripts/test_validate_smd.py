"""Regression cases for the SMD gate. Run with Python 3; no Blender required."""
import copy
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from validate_smd import compare, parse_smd, validate


BASE = '''version 1
nodes
0 "root" -1
1 "joint" 0
2 "tip" 1
3 "other" 0
end
skeleton
time 0
0 0 0 0 0 0 0
1 0 0 35 0 0 0
2 0 0 20 0 0 0
3 0 0 10 0 0 0
end
triangles
skin
0 0 0 0 0 1 0 0 0 1 0 1
0 1 0 72 0 1 0 1 0 1 0 1
0 -1 0 72 0 1 0 0 1 1 0 1
end
'''


class ValidatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "模型.smd"

    def parse(self, text=BASE):
        self.path.write_text(text, encoding="utf-8")
        return parse_smd(self.path)

    def test_valid_and_three_weights(self):
        model = self.parse(BASE.replace(" 1 0 1\n", " 3 0 0.5 1 0.3 2 0.2\n"))
        self.assertTrue(validate(model, model)["valid"])
        self.assertEqual(model["max_influences"], 3)

    def test_rigid_implicit_and_explicit_zero_links(self):
        for tail in ("", " 0"):
            with self.subTest(tail=tail):
                self.assertTrue(validate(self.parse(BASE.replace(" 1 0 1\n", tail + "\n")))["valid"])

    def test_weight_failures(self):
        for tail, failure in (
            ("4 0 0.25 1 0.25 2 0.25 3 0.25", "too_many_bone_influences"),
            ("2 0 0.5 1 0", "invalid_weight_values"),
            ("1 0 0.6", "non_normalized_weights"),
            ("2 0 0.5 0 0.5", "duplicate_weight_links"),
            ("1 99 1", "invalid_weight_ids"),
        ):
            with self.subTest(failure=failure):
                report = validate(self.parse(BASE.replace(" 1 0 1\n", " " + tail + "\n")))
                self.assertIn(failure, report["failures"])

    def test_rejects_malformed_structure(self):
        variants = [
            BASE.replace('3 "other" 0', '3 "other" 99'),
            BASE.replace('0 "root" -1', '0 "root" 2'),
            BASE.replace('3 "other" 0', '3 "tip" 0'),
            BASE.replace('3 "other" 0', '2 "other" 0'),
            BASE.replace('3 0 0 10 0 0 0\n', ''),
            BASE.replace('3 0 0 10 0 0 0', '3 0 0 10 0 0'),
            BASE.replace('3 0 0 10 0 0 0', '3 0 0 nan 0 0 0'),
            BASE.replace('0 1 0 72', '0 inf 0 72'),
            BASE.replace(' 1 0 1\n', ' 1 0 nan\n'),
            BASE.replace(' 1 0 1\n', ' 2 0 1\n'),
            BASE.replace(' 1 0 1\n', ' 1 0 1 99\n'),
            BASE.replace(' 1 0 1\n', ' 2 0 1e308 1 1e308\n'),
            BASE.replace('time 0', 'time 1'),
            BASE.rsplit('end', 1)[0],
        ]
        for i, text in enumerate(variants):
            with self.subTest(case=i), self.assertRaises(ValueError):
                self.parse(text)

    def test_equivalent_euler_and_real_rotation(self):
        reference = self.parse()
        candidate = copy.deepcopy(reference)
        a = [0.8, -1.3, 2.9]
        reference["transforms"]["joint"][3:] = a
        for b in ([a[0] + 2 * math.pi, a[1], a[2]],
                  [a[0] + math.pi, math.pi - a[1], a[2] + math.pi]):
            candidate["transforms"]["joint"][3:] = b
            self.assertFalse(compare(candidate, reference, 2e-4)["rest_transform_mismatches"])
        candidate["transforms"]["joint"][3:] = [a[0] + 0.02, a[1], a[2]]
        self.assertIn("joint", compare(candidate, reference, 2e-4)["rest_transform_mismatches"])

    def test_translation_and_parent_changes(self):
        reference = self.parse()
        candidate = copy.deepcopy(reference)
        candidate["transforms"]["joint"][0] += 0.01
        self.assertIn("rest_transform_mismatches", validate(candidate, reference)["failures"])
        candidate = copy.deepcopy(reference)
        candidate["parents"]["tip"] = "root"
        self.assertIn("parent_mismatches", validate(candidate, reference)["failures"])

    def test_node_ids_are_file_local(self):
        reference = self.parse()
        candidate = self.parse(BASE.replace('0 "root" -1', '8 "root" -1').replace('" 0\n', '" 8\n')
                               .replace('0 0 0 0 0 0 0\n', '8 0 0 0 0 0 0\n')
                               .replace(' 1 0 1\n', ' 1 8 1\n')
                               .replace('\n0 0 0 0 0 1', '\n8 0 0 0 0 1')
                               .replace('\n0 1 0 72', '\n8 1 0 72').replace('\n0 -1 0 72', '\n8 -1 0 72'))
        self.assertTrue(validate(candidate, reference)["valid"])

    def test_source_z_height(self):
        report = validate(self.parse(BASE.replace(" 72 ", " 2 ")))
        self.assertIn("implausible_source_height", report["failures"])

    def test_cli_reports_and_nonzero_failure(self):
        script = Path(__file__).with_name("validate_smd.py")
        report_path = Path(self.temp.name) / "report.json"
        self.parse()
        proc = subprocess.run([sys.executable, str(script), "--candidate", str(self.path),
                               "--summary", "--report", str(report_path)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(json.loads(proc.stdout)["valid"])
        self.assertIn("transforms", json.loads(report_path.read_text())["candidate"])
        self.path.write_text("broken", encoding="utf-8")
        proc = subprocess.run([sys.executable, str(script), "--candidate", str(self.path)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertFalse(json.loads(proc.stdout)["valid"])
        self.assertNotIn("Traceback", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
