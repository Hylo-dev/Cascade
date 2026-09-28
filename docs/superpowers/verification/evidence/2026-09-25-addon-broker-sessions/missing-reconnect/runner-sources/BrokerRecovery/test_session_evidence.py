import copy
import unittest
from session_evidence import classify


class SessionEvidenceTests(unittest.TestCase):
    def record(self):
        return dict(mode="restart", authenticated=True, registered=True, confirmed=True,
                    rootAlive=True, trigger=10., guardDeadline=40.,
                    exits=dict(broker=dict(time=10.1, status=0), provider=dict(time=10.2, status=9)),
                    restartStarted=11., freshAuthenticated=True, freshRegistered=True,
                    freshConfirmed=True, freshBroker=True, freshProvider=True,
                    freshStop=12., freshGuard=40.,
                    freshExits=dict(broker=dict(time=12.1, status=0), provider=dict(time=12.2, status=9)))

    def test_restart_requires_new_chain_after_confirmed_exit(self):
        record = self.record()
        self.assertEqual(classify(record), "PASS")
        for key, value in [("restartStarted", 10.15), ("freshProvider", False),
                           ("freshBroker", False), ("freshConfirmed", False), ("rootAlive", False)]:
            changed = dict(record, **{key: value})
            self.assertNotEqual(classify(changed), "PASS")

    def test_guard_exit_missing_exit_or_outside_window_cannot_pass(self):
        for key in ("exits", "freshExits"):
            for event in ({}, dict(time=10.2, status=14), dict(time=100., status=9)):
                record = copy.deepcopy(self.record())
                record[key]["provider"] = event
                self.assertNotEqual(classify(record), "PASS")

    def test_isolation_requires_distinct_processes_and_live_other_session(self):
        record = dict(self.record(), mode="two-hosts", distinctBrokers=True,
                      distinctProviders=True, otherAlive=True, otherConfirmed=True,
                      otherObservedUntil=12.)
        self.assertEqual(classify(record), "PASS")
        for key in ("distinctBrokers", "distinctProviders", "otherAlive", "otherConfirmed"):
            self.assertEqual(classify(dict(record, **{key: False})), "FAIL")
        self.assertNotEqual(classify(dict(record, otherObservedUntil=10.1)), "PASS")

    def test_missing_or_nonfinite_observations_are_unknown(self):
        for key, value in [("trigger", float("nan")), ("guardDeadline", 15.),
                           ("authenticated", False), ("observationError", "lost channel")]:
            self.assertEqual(classify(dict(self.record(), **{key: value})), "UNKNOWN")


if __name__ == "__main__":
    unittest.main()
