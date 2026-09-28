"""Pure harness regression evidence; never launches or signals a native fixture."""
import importlib.util
import json
from pathlib import Path
import subprocess
import types
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

lifecycle = load('lifecycle', ROOT / 'Tests/run_lifecycle.py')
direct = load('direct_evidence', ROOT / 'DirectChild/evidence.py')
HOST = Path('/fixture/Products/Release/Host.app/Contents/MacOS/Host')
PROVIDER = HOST.parents[3] / 'CascadeAddonProbeContainer.app/Contents/Extensions/CascadeProbeProvider.appex/Contents/MacOS/ProbeProvider'

class Clock:
    def __init__(self): self.now = 0.0
    def monotonic(self): return self.now
    def sleep(self, duration): self.now += duration

class Harness:
    def __init__(self, clock, *, observation_error=None, slow=False, communicate_timeout=False, absent_after_initial=False):
        self.clock, self.observation_error, self.slow = clock, observation_error, slow
        self.communicate_timeout = communicate_timeout
        self.absent_after_initial = absent_after_initial
        self.calls, self.kills, self.host_kills = [], [], []
        self.observer_calls = 0
        self.stdout = types.SimpleNamespace(fileno=lambda: 42)
        self.process = types.SimpleNamespace(pid=123, stdout=self.stdout, stderr=object(),
            poll=lambda: None, kill=lambda: self.host_kills.append(clock.now), communicate=self.communicate)
        self.selector = types.SimpleNamespace(register=lambda *args: None, close=lambda: None, select=self.select)
        self.selected = False

    def select(self, timeout):
        self.calls.append(('select', self.clock.now, timeout))
        if self.slow and not self.selected:
            # Simulate a late readiness notification using successive bounded waits.
            if self.clock.now + timeout < 2.8:
                self.clock.sleep(timeout)
                return []
            self.clock.sleep(max(0, 2.8 - self.clock.now))
        self.selected = True
        return [True]

    def observer(self, command, *, timeout, **kwargs):
        self.calls.append(('observer', self.clock.now, timeout))
        self.observer_calls += 1
        duration = (.1 if self.observer_calls == 1 else .8) if self.slow else 0
        self.clock.sleep(min(duration, timeout))
        if duration > timeout:
            raise subprocess.TimeoutExpired(command, timeout)
        if self.observation_error and self.observer_calls == 2:
            return subprocess.CompletedProcess(command, self.observation_error[0], '', self.observation_error[1])
        if self.absent_after_initial and self.observer_calls > 1:
            return subprocess.CompletedProcess(command, 0, '111 Thu Sep 10 12:00:00 2026 /fixture/harness\n', '')
        rows = f'222 Thu Sep 10 12:00:00 2026 {PROVIDER}\n111 Thu Sep 10 12:00:00 2026 /fixture/harness\n'
        return subprocess.CompletedProcess(command, 0, rows, '')

    def communicate(self, timeout):
        self.calls.append(('communicate', self.clock.now, timeout))
        if self.communicate_timeout:
            self.clock.sleep(timeout)
            raise subprocess.TimeoutExpired('host', timeout)
        duration = .6 if self.slow else 0
        self.clock.sleep(min(duration, timeout))
        if duration > timeout: raise subprocess.TimeoutExpired('host', timeout)
        return b'', b''

    def execute(self):
        with patch.object(lifecycle.time, 'monotonic', self.clock.monotonic), patch.object(lifecycle.time, 'sleep', self.clock.sleep), \
             patch.object(lifecycle.subprocess, 'Popen', return_value=self.process), patch.object(lifecycle.subprocess, 'run', side_effect=self.observer), \
             patch.object(lifecycle.selectors, 'DefaultSelector', return_value=self.selector), \
             patch.object(lifecycle.os, 'read', return_value=json.dumps({'providerPID': 222, 'status': 'OBSERVATION'}).encode() + b'\n'), \
             patch.object(lifecycle.os, 'getpid', return_value=111), \
             patch.object(lifecycle.os, 'kill', side_effect=lambda pid, sig: self.kills.append((pid, self.clock.now))):
            return lifecycle.run('invalidate-spin', HOST)

class C0HarnessRegressionTests(unittest.TestCase):
    def test_missing_replacement_output_never_authenticates_invalidation(self):
        events = [{'event': 'exec-image-observed', 'pid': 222, 'replacementMatch': True}]
        for failure in (None, 'truncated output', 'fixture failed'):
            with self.subTest(failure=failure):
                checks = direct.exec_checks(events, 222, failure)
                self.assertFalse(checks['sessionInvalidatedAfterExec'])

    def test_pipe_survival_is_separate_diagnostic_evidence(self):
        events = [{'event': 'exec-image-observed', 'pid': 222, 'replacementMatch': True},
                  {'event': 'replacement-running', 'pid': 222}]
        checks = direct.exec_checks(events, 222, None)
        self.assertTrue(checks.get('diagnosticPipeSurvivedExec'))
        self.assertFalse(checks['sessionInvalidatedAfterExec'])

    def test_denied_or_failed_ps_never_counts_as_exit(self):
        for error in ((1, 'Operation not permitted'), (2, 'ps failed')):
            with self.subTest(error=error):
                h = Harness(Clock(), observation_error=error)
                evidence = h.execute()
                self.assertFalse(evidence['checks']['exitObserved'])
                self.assertEqual(evidence['status'], 'FAIL')
                self.assertTrue(evidence['unverified'])
                self.assertIn(error[1], json.dumps(evidence['observations']))

    def test_successful_absence_with_observer_control_can_pass(self):
        h = Harness(Clock(), absent_after_initial=True)
        result = h.execute()
        self.assertEqual(result['status'], 'PASS')
        self.assertTrue(result['checks']['exitObserved'])
        self.assertEqual(result['unverified'], [])
        self.assertEqual(h.kills, [])

    def test_missing_control_is_an_observation_error(self):
        result = subprocess.CompletedProcess('ps', 0, '', '')
        with patch.object(lifecycle.os, 'getpid', return_value=111), patch.object(lifecycle.subprocess, 'run', return_value=result):
            observation = lifecycle.identity(222, lifecycle.time.monotonic() + 1)
        self.assertEqual(observation['state'], 'error')

    def test_observer_timeout_is_an_error_not_absence(self):
        with patch.object(lifecycle.subprocess, 'run', side_effect=subprocess.TimeoutExpired('ps', .1)):
            observation = lifecycle.identity(222, lifecycle.time.monotonic() + 1)
        self.assertEqual(observation['state'], 'error')

    def test_late_handshake_and_slow_calls_share_five_seconds(self):
        clock = Clock(); h = Harness(clock, slow=True)
        result = h.execute()
        self.assertLessEqual(clock.now, 5.000001)
        self.assertTrue(h.kills, 'authenticated provider cleanup must still be attempted')
        for name, started, timeout in h.calls:
            self.assertLessEqual(started + timeout, 5.000001, name)
        self.assertFalse(result['checks']['exitObserved'])

    def test_communicate_timeout_does_not_skip_provider_cleanup(self):
        h = Harness(Clock(), communicate_timeout=True)
        try:
            result = h.execute()
        except subprocess.TimeoutExpired:
            result = None
        self.assertTrue(h.kills, 'communicate timeout skipped authenticated cleanup')
        self.assertIsNotNone(result, 'cleanup timeout must be recorded, not escape')
        self.assertEqual(result['status'], 'FAIL')
        self.assertTrue(result['unverified'])

if __name__ == '__main__': unittest.main()
