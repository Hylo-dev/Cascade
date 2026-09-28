"""The CLI must reject incomplete evidence even when a producer exits successfully."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

VALIDATOR = Path(__file__).resolve().parents[3] / 'scripts/assert-addon-evidence.py'

class CompletionEvidenceTests(unittest.TestCase):
    def run_record(self, record, scenario='launcher-admission', checks=('managedStop',)):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'record.json'
            path.write_text(json.dumps(record))
            return subprocess.run([sys.executable, str(VALIDATOR), str(path), scenario, *checks], capture_output=True, text=True).returncode

    def setUp(self):
        self.valid = dict(schemaVersion=1, scenario='launcher-admission', checks={'managedStop': True}, observations={}, unverified=[])

    def test_valid_record_is_accepted(self):
        self.assertEqual(self.run_record(self.valid), 0)

    def test_false_check_is_rejected(self):
        self.valid['checks']['managedStop'] = False
        self.assertNotEqual(self.run_record(self.valid), 0)

    def test_missing_check_is_rejected(self):
        self.valid['checks'].clear()
        self.assertNotEqual(self.run_record(self.valid), 0)

    def test_different_scenario_is_rejected(self):
        self.assertNotEqual(self.run_record(self.valid, scenario='other'), 0)

    def test_unverified_case_is_rejected(self):
        self.valid['unverified'] = ['macOS 14']
        self.assertNotEqual(self.run_record(self.valid), 0)

    def test_no_explicit_checks_is_rejected(self):
        self.assertNotEqual(self.run_record(self.valid, checks=()), 0)

    def test_truthy_integer_is_rejected(self):
        self.valid['checks']['managedStop'] = 1
        self.assertNotEqual(self.run_record(self.valid), 0)

    def test_missing_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(VALIDATOR), str(Path(directory) / 'missing.json'), 'launcher-admission', 'managedStop'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_malformed_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'malformed.json'
            path.write_text('{')
            result = subprocess.run([sys.executable, str(VALIDATOR), str(path), 'launcher-admission', 'managedStop'], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_wrong_schema_is_rejected(self):
        self.valid['schemaVersion'] = 2
        self.assertNotEqual(self.run_record(self.valid), 0)

if __name__ == '__main__': unittest.main()
