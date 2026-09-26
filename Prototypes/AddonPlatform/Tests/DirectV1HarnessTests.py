import contextlib
import io
import json
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch, MagicMock

RUNNER = Path(__file__).resolve().parents[1] / 'DirectV1/run_audit.py'

class DirectV1HarnessTests(unittest.TestCase):
    def test_bootout_timeout_still_saves_unknown_report(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            bootstrap = subprocess.CompletedProcess([], 1, '', 'bootstrap failed')
            with patch('sys.argv', [str(RUNNER), temporary, 'test-fixture']), \
                 patch('tempfile.mkdtemp', return_value=temporary), \
                 patch('subprocess.run', side_effect=[bootstrap, subprocess.TimeoutExpired('bootout', 1)]) as run, \
                 contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(RUNNER), run_name='__main__')
            result = json.loads((root/'results.json').read_text())
            self.assertEqual(run.call_count, 2)
            self.assertTrue(result['cleanupErrors'])
            self.assertIsNone(result['bootoutReturnCode'])

    def test_failed_worker_drain_does_not_skip_launchd_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            process = MagicMock()
            process.poll.return_value = None
            process.communicate.side_effect = subprocess.TimeoutExpired('worker drain', 1)
            okay = subprocess.CompletedProcess([], 0, '', '')
            with patch('sys.argv', [str(RUNNER), temporary, 'test-fixture']), \
                 patch('tempfile.mkdtemp', return_value=temporary), \
                 patch('subprocess.run', return_value=okay) as run, \
                 patch('subprocess.Popen', return_value=process), \
                 contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(RUNNER), run_name='__main__')
            result = json.loads((root/'results.json').read_text())
            self.assertEqual(run.call_count, 2)
            self.assertEqual(result['bootoutReturnCode'], 0)
            self.assertTrue(result['cleanupErrors'])
            self.assertIsNone(result['workerReturnCode'])
            process.kill.assert_called_once()

if __name__ == '__main__': unittest.main()
