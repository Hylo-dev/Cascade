import unittest
from interruption_evidence import classify


class EvidenceTests(unittest.TestCase):
    def record(self):
        return dict(authenticated=True,registered=True,confirmed=True,hostAlive=True,
                    launchNonce="start-1",trigger=10.,windowEnd=16.,guardDeadline=35.,
                    notifications=[dict(nonce="start-1",time=11.)],
                    exit=dict(time=11.01,status=0))

    def test_notification_requires_independent_exit(self):
        self.assertEqual(classify(self.record()),"EXIT_AND_NOTIFICATION")
        self.assertEqual(classify(self.record() | {"exit":None}),"NOTIFICATION_WITHOUT_CONFIRMED_EXIT")

    def test_absence_is_bounded_observation(self):
        self.assertEqual(classify(self.record() | {"notifications":[]}),"EXIT_WITHOUT_NOTIFICATION")
        self.assertEqual(classify(self.record() | {"notifications":[],"exit":None}),"NO_EXIT_OR_NOTIFICATION")

    def test_wrong_session_guard_or_cleanup_evidence_rejected(self):
        for patch in [{"notifications":[dict(nonce="other",time=11.)]},
                      {"notifications":[dict(nonce="start-1",time=17.)]},
                      {"exit":dict(time=17.,status=9)},
                      {"exit":dict(time=11.,status=14)},
                      {"guardDeadline":15.}, {"registered":False}, {"hostAlive":False},
                      {"observationError":"missing event"}]:
            self.assertEqual(classify(self.record() | patch),"UNKNOWN")


if __name__=="__main__": unittest.main()
