import unittest
from evidence import classify


class EvidenceTests(unittest.TestCase):
    def record(self):
        return dict(mode="broker", authenticated=True, registered=True, confirmed=True,
                    survivedInvalidation=True, rootAlive=True, trigger=10.,
                    brokerGuard=40., providerGuard=30.,
                    exits={"broker":dict(time=10.1,status=0),"provider":dict(time=10.2,status=9)})

    def test_selective_exit(self):
        self.assertEqual(classify(self.record()), "PASS")

    def test_rejects_guard_exit_and_late_exit(self):
        for time, status in [(10.2,14),(19.,9)]:
            r=self.record(); r["exits"]["provider"]=dict(time=time,status=status)
            self.assertEqual(classify(r),"FAIL")

    def test_missing_or_early_exit_is_unknown(self):
        for exits in [{}, {"broker":dict(time=9.,status=0),"provider":dict(time=11.,status=9)}]:
            r=self.record();r["exits"]=exits
            self.assertEqual(classify(r),"UNKNOWN")

    def test_root_death_is_not_selective_success(self):
        r=self.record();r["rootAlive"]=False
        self.assertEqual(classify(r),"FAIL")

    def test_global_needs_expected_root_exit(self):
        r=self.record();r.update(mode="crash",rootStatus=-9,rootExitObserved=10.1)
        r["exits"]["broker"]["status"]=9
        self.assertEqual(classify(r),"PASS")
        r["rootStatus"]=0
        self.assertEqual(classify(r),"UNKNOWN")


if __name__ == "__main__": unittest.main()
