import copy
import unittest
from chain_evidence import classify


class ChainEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.good = dict(mode="stop", authenticated=True, registered=True,
                         sameInstances=True, actionConfirmed=True, windowComplete=True,
                         hostStatus=None, survivorConfirmed=True, trigger=10.0,
                         guards={key: 20.0 for key in ("A.broker", "A.worker", "B.broker", "B.worker")},
                         exits={"A.broker": {"time": 10.1, "status": 0},
                                "A.worker": {"time": 10.2, "status": 9}})

    def test_stop_requires_worker_exit_and_surviving_other_chain(self):
        self.assertEqual(classify(self.good), "PASS")
        record=copy.deepcopy(self.good)
        del record["exits"]["A.worker"]
        self.assertEqual(classify(record), "FAIL")
        self.assertEqual(classify(self.good | {"survivorConfirmed": False}), "FAIL")

    def test_collateral_exit_fails_isolation(self):
        record=copy.deepcopy(self.good)
        record["exits"]["B.worker"]={"time": 10.3, "status": 9}
        self.assertEqual(classify(record), "FAIL")

    def test_cleanup_guard_fault_and_pretrigger_do_not_pass(self):
        for exit in [dict(time=20.0,status=14),dict(time=10.2,status=11),
                     dict(time=10.2,status=81<<8),dict(time=9.9,status=9),
                     dict(time=12.1,status=9),dict(time=10.2,status=0)]:
            record=copy.deepcopy(self.good)
            record["exits"]["A.worker"]=exit
            self.assertNotEqual(classify(record), "PASS")

    def test_missing_evidence_is_unknown(self):
        for field in ["authenticated","registered","sameInstances","actionConfirmed","windowComplete"]:
            self.assertEqual(classify(self.good | {field: None}), "UNKNOWN")
        self.assertEqual(classify(self.good | {"observationError": "lost kernel event"}), "UNKNOWN")

    def test_host_death_requires_all_four_exits(self):
        record=copy.deepcopy(self.good)
        record.update(mode="host-crash",hostStatus=-9)
        record["exits"]={key:dict(time=10.1,status=9) for key in record["guards"]}
        self.assertEqual(classify(record), "PASS")
        record["exits"].pop("B.worker")
        self.assertEqual(classify(record), "FAIL")

    def test_broker_crash_and_host_normal_have_exact_status(self):
        record=copy.deepcopy(self.good)
        record["mode"]="broker-crash"
        record["exits"]["A.broker"]["status"]=9
        self.assertEqual(classify(record), "PASS")
        record["exits"]["A.broker"]["status"]=15
        self.assertEqual(classify(record), "FAIL")
        record.update(mode="host-normal", hostStatus=0)
        record["exits"]={key:dict(time=10.1,status=9) for key in record["guards"]}
        self.assertEqual(classify(record), "PASS")
        self.assertEqual(classify(record | {"hostStatus": -9}), "UNKNOWN")


if __name__ == "__main__":
    unittest.main()
