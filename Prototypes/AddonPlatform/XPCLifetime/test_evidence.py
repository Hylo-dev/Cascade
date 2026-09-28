import unittest
import os
from types import SimpleNamespace
from evidence import classify
from run_probe import Output


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.good = dict(mode="crash", authenticated=True, registered=True,
                         sameInstance=True, trigger=10.0, guardDeadline=16.0,
                         serviceExit=10.1, serviceStatus=9, hostStatus=-9,
                         actionConfirmed=True, windowComplete=True, hostAliveAtWindowEnd=False)

    def test_kernel_exit_after_owned_client_crash_is_observed(self):
        self.assertEqual(classify(self.good), "PASS")

    def test_guard_cleanup_is_not_success(self):
        for field, value in [("serviceExit", 16.1), ("serviceStatus", 14),
                             ("serviceExit", 9.9)]:
            with self.subTest(field=field):
                self.assertNotEqual(classify(self.good | {field: value}), "PASS")

    def test_missing_or_untrusted_evidence_cannot_pass(self):
        for field in ["authenticated", "registered", "sameInstance", "serviceStatus", "actionConfirmed"]:
            with self.subTest(field=field):
                self.assertEqual(classify(self.good | {field: None}), "UNKNOWN")
        self.assertEqual(classify(self.good | {"authenticated": "true"}), "UNKNOWN")
        self.assertEqual(classify(self.good | {"observationError": "lost event"}), "UNKNOWN")

    def test_cancel_requires_client_stays_alive(self):
        record = self.good | dict(mode="cancel", hostStatus=None, hostAliveAtWindowEnd=True)
        self.assertEqual(classify(record), "PASS")
        self.assertEqual(classify(record | {"hostAliveAtWindowEnd": False}), "UNKNOWN")
        self.assertEqual(classify(record | {"serviceExit": None, "serviceStatus": None}), "FAIL")

    def test_normal_and_cooperative_exit_need_correct_status(self):
        self.assertEqual(classify(self.good | dict(mode="normal", hostStatus=0)), "PASS")
        self.assertEqual(classify(self.good | dict(mode="normal", hostStatus=-9)), "UNKNOWN")
        record = self.good | dict(mode="cooperate", hostStatus=None,
                                  hostAliveAtWindowEnd=True, serviceStatus=0)
        self.assertEqual(classify(record), "PASS")
        self.assertEqual(classify(record | {"serviceStatus": 14}), "FAIL")

    def test_service_fault_or_fixture_error_is_not_cleanup(self):
        for status in [11, 81 << 8, 0]:
            self.assertEqual(classify(self.good | {"serviceStatus": status}), "FAIL")

    def test_expected_invalidation_does_not_hide_action_marker(self):
        for event, accepted in [("connection-invalid", True), ("authentication-error", False)]:
            reader, writer = os.pipe()
            os.write(writer, ('{"event":"' + event + '"}\n{"event":"cancelled"}\n').encode())
            os.close(writer)
            with os.fdopen(reader, 'rb') as stream:
                output = Output(SimpleNamespace(stdout=stream), {"events": []})
                if accepted:
                    self.assertEqual(output.expect("cancelled", allow_terminal=True)["event"], "cancelled")
                else:
                    with self.assertRaises(RuntimeError):
                        output.expect("cancelled", allow_terminal=True)


if __name__ == "__main__":
    unittest.main()
