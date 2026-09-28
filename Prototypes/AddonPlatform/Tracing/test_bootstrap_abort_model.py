"""Offline contract tests; all observations are invented, never kernel evidence.

Run: python3 -B -m unittest discover -s Prototypes/AddonPlatform/Tracing
-p test_bootstrap_abort_model.py -v
"""

from copy import deepcopy
from dataclasses import FrozenInstanceError, replace
import unittest

from bootstrap_abort_model import BootstrapAbortModel, evaluate_synthetic_fixture

NONCE = "0123456789abcdef0123456789abcdef"
CLOCK = "synthetic-observer-monotonic-ns"
START = 10_000_000_000


def frame(command="advance", sequence=1, nonce=NONCE, phase="bootstrap", version="1"):
    payload = f"{version}|{nonce}|{phase}|{sequence}|{command}".encode("ascii")
    return len(payload).to_bytes(2, "big") + payload


def fixture():
    identities = {role: {"run": NONCE, "role": role, "pid": pid, "instance": digit * 32}
                  for role, pid, digit in (("observer", 101, "1"),
                                           ("supervisor", 102, "2"), ("child", 103, "3"))}
    records = []
    kinds = [("observer-retained", "observer", 1), ("supervisor-retained", "supervisor", 2),
             ("child-retained", "child", 3), ("injection", "supervisor", 100_000_000),
             ("child-exit", "child", 200_000_000), ("model-eof-decision", "child", 210_000_000),
             ("supervisor-exit", "supervisor", 220_000_000),
             ("supervisor-direct-wait", "supervisor", 230_000_000)]
    for index, (kind, role, offset) in enumerate(kinds):
        record = {"kind": kind, "at_ns": START + offset, "clock": CLOCK, "batch": index,
                  "observer": deepcopy(identities["observer"]),
                  "subject": deepcopy(identities[role])}
        if kind == "child-exit":
            record["status"] = {"kind": "exit", "value": 70}
        elif kind in {"supervisor-exit", "supervisor-direct-wait"}:
            record["status"] = {"kind": "signal", "value": 9}
        elif kind == "injection":
            record["action"] = {"kind": "signal", "value": 9}
        records.append(record)
    return {"schema": "cascade.bootstrap-abort.synthetic.v1", "simulation": "simulated",
            "run": NONCE, "clock": CLOCK, "window_start_ns": START,
            "identities": identities, "events": records}


def eof_decision():
    return BootstrapAbortModel.begin(NONCE, 0).observe(1, eof=True)


class BootstrapAbortTests(unittest.TestCase):
    # Literal outcomes catch missing protocol, precedence, and terminal branches.
    def test_eof_before_first_token_predicts_channel_loss(self):
        self.assertEqual(eof_decision().predicted_exit_code, 70)

    def test_advance_is_not_liveness_and_eof_after_or_with_token_is_terminal(self):
        model = BootstrapAbortModel.begin(NONCE, 0).observe(1, data=frame())
        self.assertIsNone(model.predicted_exit_code)
        self.assertEqual(model.phase, "advanced")
        self.assertEqual(model.observe(2, eof=True).predicted_exit_code, 70)
        self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(
            1, data=frame(), eof=True).predicted_exit_code, 70)

    def test_every_split_position_coalescing_and_bytewise_fragmentation(self):
        wire = frame() + frame("complete", 2)
        for split in range(len(wire) + 1):
            with self.subTest(split=split):
                model = BootstrapAbortModel.begin(NONCE, 0).observe(1, data=wire[:split])
                self.assertEqual(model.observe(2, data=wire[split:]).predicted_exit_code, 0)
        model = BootstrapAbortModel.begin(NONCE, 0)
        for index, value in enumerate(wire):
            model = model.observe(index + 1, data=bytes([value]))
            self.assertLessEqual(len(model.partial), 97)
        self.assertEqual(model.predicted_exit_code, 0)

    def test_all_nonempty_incomplete_prefixes_plus_eof_are_protocol_failure(self):
        wire = frame()
        for split in range(1, len(wire)):
            with self.subTest(split=split):
                model = BootstrapAbortModel.begin(NONCE, 0).observe(1, data=wire[:split])
                self.assertEqual(model.observe(2, eof=True).predicted_exit_code, 71)

    def test_absolute_deadline_equality_and_no_renewal(self):
        for options in ({}, {"eof": True}, {"read_failed": True},
                        {"data": frame() + frame("complete", 2)}, {"eintr": True}):
            with self.subTest(options=options):
                self.assertEqual(BootstrapAbortModel.begin(NONCE, 20).observe(
                    2_000_000_020, **options).predicted_exit_code, 72)
        model = BootstrapAbortModel.begin(NONCE, 20).observe(1_900_000_020, data=frame()[:1])
        model = model.observe(1_999_999_999, eintr=True)
        self.assertEqual(model.deadline_ns, 2_000_000_020)
        self.assertEqual(model.observe(2_000_000_020, eof=True).predicted_exit_code, 72)
        model = BootstrapAbortModel.begin(NONCE, 0).observe(1_999_999_999, data=frame())
        self.assertIsNone(model.predicted_exit_code)
        self.assertEqual(model.observe(2_000_000_000).predicted_exit_code, 72)

    def test_deadline_is_derived_even_for_direct_state_construction(self):
        model = BootstrapAbortModel(NONCE, 20)
        self.assertIsNone(model.observe(21).predicted_exit_code)
        self.assertEqual(model.observe(2_000_000_020).predicted_exit_code, 72)
        with self.assertRaises(TypeError):
            BootstrapAbortModel(NONCE, 20, deadline_ns=3_000_000_020)

    def test_bad_time_nonce_and_backwards_time_fail_closed(self):
        for bad in (True, False, -1, 1.0, float("nan"), float("inf"), None, 2**63):
            with self.subTest(bad=bad):
                self.assertEqual(BootstrapAbortModel.begin(NONCE, bad).predicted_exit_code, 71)
                self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(bad).predicted_exit_code, 71)
        for nonce in ("", "a" * 31, "a" * 33, "G" * 32, "A" * 32, None, b"a" * 32):
            self.assertEqual(BootstrapAbortModel.begin(nonce, 0).predicted_exit_code, 71)
        model = BootstrapAbortModel.begin(NONCE, 0).observe(10)
        self.assertEqual(model.observe(9, eof=True).predicted_exit_code, 71)
        self.assertEqual(BootstrapAbortModel.begin(NONCE, 2**63 - 1).predicted_exit_code, 71)

    def test_invalid_fields_sequence_and_commands_are_protocol_failure(self):
        invalid = [frame(version="2"), frame(nonce="a" * 32), frame(phase="attach"),
                   frame(sequence=0), frame(sequence=2), frame(sequence="01"),
                   frame(command="exec"), frame(command="attach"), frame("complete", 1),
                   b"\x00\x00", b"\x00\x01\xff", b"\x00\x01x", frame() + frame(),
                   frame() + frame("advance", 2), frame() + frame("complete", 3)]
        for wire in invalid:
            with self.subTest(wire=wire):
                self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(
                    1, data=wire, eof=True).predicted_exit_code, 71)

    def test_adverse_whole_batch_dominates_baseline_and_eof(self):
        baseline = frame() + frame("complete", 2)
        for tail in (b"x", b"\x00\x01x", frame(), b"\xff\xff"):
            with self.subTest(tail=tail):
                self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(
                    1, data=baseline + tail).predicted_exit_code, 71)
        for options, status in (({"eof": True}, 70), ({"read_failed": True}, 73),
                                ({"setup_failed": True, "eof": True}, 73)):
            self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(
                1, data=baseline, **options).predicted_exit_code, status)
        self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(
            1, data=b"\x00\x01x", eof=True).predicted_exit_code, 71)

    def test_frame_total_and_frame_count_limits_admit_no_oversize(self):
        for wire in (b"\x00\x61", b"\xff\xff", b"x" * 197):
            model = BootstrapAbortModel.begin(NONCE, 0).observe(1, data=wire)
            self.assertEqual(model.predicted_exit_code, 71)
            self.assertEqual(model.partial, b"")
        model = BootstrapAbortModel.begin(NONCE, 0).observe(1, data=b"\x00")
        self.assertEqual(model.observe(2, data=b"\x61").predicted_exit_code, 71)
        model = BootstrapAbortModel.begin(NONCE, 0).observe(1, data=b"\x00\x60" + b"x" * 95)
        self.assertIsNone(model.predicted_exit_code)
        self.assertEqual(len(model.partial), 97)
        self.assertEqual(model.observe(2, data=b"x").predicted_exit_code, 71)
        self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(
            1, data=frame() + frame("complete", 2) + frame()).predicted_exit_code, 71)

    def test_cumulative_limit_checks_new_batch_before_retaining_it(self):
        model = BootstrapAbortModel.begin(NONCE, 0).observe(1, data=b"\x00\x60" + b"x" * 95)
        model = model.observe(2, data=b"x" * 100)
        self.assertEqual(model.predicted_exit_code, 71)
        self.assertEqual(model.reason, "total-byte-limit")
        self.assertEqual(model.partial, b"")
        self.assertEqual(model.total_bytes, 97)

    def test_bad_observation_types_are_rejected_without_coercion(self):
        for data in (bytearray(b"x"), memoryview(b"x"), "x", None, 1):
            self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(1, data=data).predicted_exit_code, 71)
        for flag in ("eof", "hup", "eintr", "read_failed", "setup_failed"):
            self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(
                1, **{flag: 1}).predicted_exit_code, 71)

    def test_setup_and_read_failure_are_distinct_from_eof(self):
        for flag in ("setup_failed", "read_failed"):
            self.assertEqual(BootstrapAbortModel.begin(NONCE, 0).observe(
                1, **{flag: True}).predicted_exit_code, 73)

    def test_hup_no_data_eintr_and_leaked_writer_do_not_predict_eof(self):
        model = BootstrapAbortModel.begin(NONCE, 0)
        for index, options in enumerate(({"hup": True}, {}, {"eintr": True},
                                         {"hup": True, "data": frame()})):
            model = model.observe(index + 1, **options)
            self.assertIsNone(model.predicted_exit_code)
        self.assertEqual(model.observe(2_000_000_000).predicted_exit_code, 72)

    def test_each_terminal_outcome_is_frozen_across_later_calls(self):
        models = [eof_decision(), BootstrapAbortModel.begin(NONCE, 0).observe(1, data=b"\x00\x00"),
                  BootstrapAbortModel.begin(NONCE, 0).observe(2_000_000_000),
                  BootstrapAbortModel.begin(NONCE, 0).observe(1, read_failed=True),
                  BootstrapAbortModel.begin(NONCE, 0).observe(1, data=frame() + frame("complete", 2))]
        for model in models:
            for options in ({"eof": True}, {"data": frame()}, {"read_failed": True}, {"data": None}):
                self.assertIs(model.observe(-1, **options), model)
            with self.assertRaises(FrozenInstanceError):
                model.predicted_exit_code = 0


class SyntheticEvidenceTests(unittest.TestCase):
    def assert_native_false(self, result):
        for name in ("trustedBootstrapAbortObserved", "supervisorDeathStopsWorker",
                     "nativeLauncherAdmitted", "nativeSuccess"):
            self.assertIs(getattr(result, name), False)

    def check_rejected(self, value, decision=None):
        result = evaluate_synthetic_fixture(value, eof_decision() if decision is None else decision)
        self.assertFalse(result.modelAbortEvidenceConsistent)
        self.assertTrue(result.reasons)
        self.assert_native_false(result)

    def test_exact_simulated_fixture_is_consistent_but_never_native_success(self):
        result = evaluate_synthetic_fixture(fixture(), eof_decision())
        self.assertTrue(result.modelAbortEvidenceConsistent, result.reasons)
        self.assertEqual(result.reasons, ())
        self.assert_native_false(result)
        with self.assertRaises(FrozenInstanceError):
            result.nativeSuccess = True

    def test_missing_required_observations_and_log_only_exit_are_rejected(self):
        for index in range(8):
            value = fixture()
            del value["events"][index]
            self.check_rejected(value)
        value = fixture()
        value["events"][4]["kind"] = "log-child-exit"
        self.check_rejected(value)

    def test_duplicate_and_unknown_fields_events_are_rejected(self):
        for index in range(8):
            value = fixture()
            value["events"].append(deepcopy(value["events"][index]))
            self.check_rejected(value)
        for target in ("fixture", "event", "identity", "status"):
            value = fixture()
            dest = {"fixture": value, "event": value["events"][0],
                    "identity": value["identities"]["child"],
                    "status": value["events"][4]["status"]}[target]
            dest["extra"] = True
            self.check_rejected(value)

    def test_guard_fallback_cleanup_timeout_error_grants_dominate_same_batch(self):
        for kind in ("guard", "fallback", "cleanup", "timeout", "error", "normal-completion",
                     "attach-grant", "exec-grant", "alarm", "log-success"):
            value = fixture()
            record = deepcopy(value["events"][5])
            record["kind"] = kind
            value["events"].append(record)
            self.check_rejected(value)

    def test_status_requires_valid_exact_type_and_direct_wait_agreement(self):
        for status in (None, True, 70, {"kind": "exit", "value": True},
                       {"kind": "exit", "value": -1}, {"kind": "exit", "value": 256},
                       {"kind": "exit", "value": 70.0}, {"kind": "signal", "value": 0},
                       {"kind": "signal", "value": 128}, {"kind": "unknown", "value": 70}):
            value = fixture()
            value["events"][4]["status"] = status
            self.check_rejected(value)
        for code in (0, 71, 72, 73):
            value = fixture()
            value["events"][4]["status"]["value"] = code
            self.check_rejected(value)
        value = fixture()
        value["events"][7]["status"]["value"] = 15
        self.check_rejected(value)

    def test_retained_observer_run_child_supervisor_identity_must_match_exactly(self):
        for index in range(8):
            for field, bad in (("pid", 999), ("instance", "f" * 32), ("run", "a" * 32),
                               ("pid", True), ("role", "worker")):
                value = fixture()
                value["events"][index]["subject"][field] = bad
                self.check_rejected(value)
            value = fixture()
            value["events"][index]["observer"]["instance"] = "f" * 32
            self.check_rejected(value)
        for field, bad in (("pid", 102), ("instance", "2" * 32)):
            value = fixture()
            value["identities"]["child"][field] = bad
            self.check_rejected(value)

    def test_clock_domain_window_and_nonfinite_times_fail_closed(self):
        for index in range(8):
            for bad in (True, 1.0, float("nan"), float("inf"), -1, 2**63,
                        START - 1, START + 1_500_000_000):
                value = fixture()
                value["events"][index]["at_ns"] = bad
                self.check_rejected(value)
            value = fixture()
            value["events"][index]["clock"] = "native-kernel-clock"
            self.check_rejected(value)
        value = fixture()
        value["clock"] = "native-kernel-clock"
        self.check_rejected(value)
        value = fixture()
        for record in value["events"][4:]:
            record["at_ns"] = START + 1_499_999_999
        self.assertTrue(evaluate_synthetic_fixture(value, eof_decision()).modelAbortEvidenceConsistent)

    def test_retention_precedes_injection_receipts_must_not_precede_it(self):
        for index in (0, 1, 2):
            value = fixture()
            value["events"][index]["at_ns"] = START + 100_000_000
            self.check_rejected(value)
        for index in (4, 5, 6, 7):
            value = fixture()
            value["events"][index]["at_ns"] = START + 99_999_999
            self.check_rejected(value)
        value = fixture()
        for record in value["events"][4:]:
            record["at_ns"] = START + 100_000_000
        self.assertTrue(evaluate_synthetic_fixture(value, eof_decision()).modelAbortEvidenceConsistent)

    def test_only_actual_modeled_eof_can_support_consistency(self):
        for decision in (BootstrapAbortModel.begin(NONCE, 0),
                         BootstrapAbortModel.begin(NONCE, 0).observe(1, hup=True),
                         BootstrapAbortModel.begin(NONCE, 0).observe(2_000_000_000),
                         BootstrapAbortModel.begin(NONCE, 0).observe(1, data=b"\x00\x00"),
                         BootstrapAbortModel.begin(NONCE, 0).observe(1, read_failed=True),
                         BootstrapAbortModel.begin(NONCE, 0).observe(1, data=frame() + frame("complete", 2)),
                         BootstrapAbortModel.begin(NONCE, 0).observe(1, data=frame() + frame("complete", 2), eof=True),
                         BootstrapAbortModel.begin("a" * 32, 0).observe(1, eof=True),
                         {"predicted_exit_code": 70}, True):
            self.check_rejected(fixture(), decision)
        self.assertFalse(evaluate_synthetic_fixture(fixture()).modelAbortEvidenceConsistent)

    def test_malformed_schema_and_bounded_input_shape_fail_closed(self):
        for bad in (None, True, [], "native-report", {}):
            self.check_rejected(bad)
        for key in tuple(fixture()):
            value = fixture()
            del value[key]
            self.check_rejected(value)
        for field, bad in (("schema", "C0d"), ("simulation", True), ("run", "a" * 33),
                           ("events", None), ("identities", []), ("window_start_ns", True),
                           ("window_start_ns", 2**63 - 1)):
            value = fixture()
            value[field] = bad
            self.check_rejected(value)
        value = fixture()
        value["events"] *= 3
        self.check_rejected(value)
        for field, bad in (("batch", True), ("batch", 16), ("kind", []), ("subject", None)):
            value = fixture()
            value["events"][0][field] = bad
            self.check_rejected(value)

    def test_malformed_identity_never_invokes_custom_comparison(self):
        class InvalidValue:
            def __eq__(self, other):
                raise AssertionError("Evaluator invoked caller's custom comparison")

        value = fixture()
        value["identities"]["child"]["run"] = InvalidValue()
        self.check_rejected(value)

    def test_nonbuiltin_field_names_are_not_accepted_as_schema_keys(self):
        class InvalidKey(str):
            pass

        value = fixture()
        value[InvalidKey("schema")] = value.pop("schema")
        self.check_rejected(value)

    def test_malformed_model_fields_are_rejected_before_custom_comparison(self):
        class InvalidValue:
            def __eq__(self, other):
                raise AssertionError("Evaluator compared a malformed model field")

        decision = BootstrapAbortModel(InvalidValue(), 0)
        self.check_rejected(fixture(), decision)
        decision = BootstrapAbortModel(NONCE, 0, phase="aborted", predicted_exit_code=70,
                                       reason="eof-boundary", eof_observed=1)
        self.check_rejected(fixture(), decision)

    def test_impossible_eof_model_states_are_inconsistent(self):
        decision = eof_decision()
        for changes in ({"start_ns": True}, {"start_ns": -1}, {"start_ns": 2**63},
                        {"last_ns": True}, {"last_ns": -1}, {"last_ns": 2_000_000_000},
                        {"last_ns": 2_000_000_001}, {"frame_count": True}, {"frame_count": -1},
                        {"frame_count": 2}, {"frame_count": 3}, {"total_bytes": True},
                        {"total_bytes": -1}, {"total_bytes": 197}, {"total_bytes": 1},
                        {"frame_count": 1, "total_bytes": 0},
                        {"frame_count": 1, "total_bytes": 57}):
            with self.subTest(changes=changes):
                self.check_rejected(fixture(), replace(decision, **changes))
        # Frozen values are unauthenticated, so explicitly forged input must
        # also be rejected. This changes a fixture object, never production code.
        forged = replace(decision)
        object.__setattr__(forged, "deadline_ns", 3_000_000_000)
        self.check_rejected(fixture(), forged)
        advanced = BootstrapAbortModel.begin(NONCE, 0).observe(1, data=frame()).observe(2, eof=True)
        self.assertTrue(evaluate_synthetic_fixture(fixture(), advanced).modelAbortEvidenceConsistent)

    def test_injected_supervisor_death_cannot_be_matching_normal_exits(self):
        for status in ({"kind": "exit", "value": 0}, {"kind": "signal", "value": 15}):
            with self.subTest(status=status):
                value = fixture()
                for index in (6, 7):
                    value["events"][index]["status"] = deepcopy(status)
                self.check_rejected(value)

    def test_injection_action_is_explicit_closed_signal9(self):
        for action in (None, True, 9, {"kind": "signal", "value": True},
                       {"kind": "signal", "value": 15}, {"kind": "exit", "value": 0},
                       {"kind": "signal", "value": 9, "extra": True}):
            value = fixture()
            value["events"][3]["action"] = action
            self.check_rejected(value)
        value = fixture()
        del value["events"][3]["action"]
        self.check_rejected(value)


if __name__ == "__main__":
    unittest.main()
