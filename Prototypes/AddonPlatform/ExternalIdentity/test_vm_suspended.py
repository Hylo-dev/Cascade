"""Fail-closed checks for the disposable guest's measured result."""
import contextlib
import io
import json
import os
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from run_vm_suspended import (Stream, classify, guest_allowed, validate_options,
                              stackshot_budget, stackshot_unchanged, run)


def evidence():
    audit = [1, 2, 3, 4, 5, 502, 7, 9]
    identity = dict(authenticated=True, pid=502, audit=audit, basicInfoStatus=0,
                    suspendCount=1, guardDeadline=50, time=10)
    return dict(mode='broker-crash', guestVerified=True, inputsVerified=True,
                cleanupQualified=True, firstExit=dict(time=8, status=0), firstGuard=30,
                firstAudit=[1, 2, 3, 4, 5, 501, 7, 8], firstPID=501,
                debugArmed=8.5, secondHelloRequested=9, identity=identity,
                registration=dict(pid=502, time=10.1, flags=0x4000, data=0),
                confirmed=dict(identity, time=10.2), beforeTrigger=dict(identity, time=11),
                trigger=12, brokerGuard=40, rootGuard=45,
                providerExit=dict(pid=502, time=12.1, status=15, fflags=0x84000000),
                brokerExit=dict(time=12.2, status=9, fflags=0x84000000),
                rootStatus=0, rootExitObserved=13, observerAlive=True, rootSurvivedFault=True,
                helloBeforeTrigger=False, cleanupComplete=True)


class EvidenceTests(unittest.TestCase):
    def test_fault_with_bound_identity_and_exits(self):
        self.assertEqual(classify(evidence()), 'PASS')

    def test_no_suspend_or_no_basic_info(self):
        for field, value in [('suspendCount', 0), ('basicInfoStatus', 5)]:
            item = evidence(); item['beforeTrigger'][field] = value
            self.assertNotEqual(classify(item), 'PASS')

    def test_reused_pid_wrong_audit_or_missing_authentication(self):
        for field, value in [('audit', [0] * 8), ('authenticated', False), ('pid', 999)]:
            item = evidence(); item['confirmed'][field] = value
            self.assertNotEqual(classify(item), 'PASS')

    def test_early_guard_or_observed_exit_before_fault(self):
        for field, value in [('brokerGuard', 19), ('trigger', 13)]:
            item = evidence(); item[field] = value
            self.assertNotEqual(classify(item), 'PASS')

    def test_unknown_cleanup_exit_status_or_provider_running(self):
        for field, value in [('cleanupComplete', False), ('providerExit', None),
                             ('observerAlive', False), ('helloBeforeTrigger', True),
                             ('rootSurvivedFault', False)]:
            item = evidence(); item[field] = value
            self.assertNotEqual(classify(item), 'PASS')
        item = evidence(); item['brokerExit']['status'] = 15
        self.assertNotEqual(classify(item), 'PASS')

    def test_guest_guard_rejects_host_and_root(self):
        self.assertTrue(guest_allowed('1', 'VirtualMac2,1', 501))
        for env, model, uid in [('1', 'Mac14,5', 501), ('0', 'VirtualMac2,1', 501),
                                ('1', 'VirtualMac2,1', 0)]:
            self.assertFalse(guest_allowed(env, model, uid))

    def test_pending_hello_is_rejected_but_post_fault_error_allows_ping(self):
        for events, target, kwargs, rejected in [
            ([dict(event='hello'), dict(event='broker-info')], 'broker-info', dict(reject=('hello',)), True),
            ([dict(event='response-error'), dict(event='ping', pid=123)], 'ping', dict(ignore_errors=True), False),
        ]:
            read_fd, write_fd = os.pipe()
            with os.fdopen(read_fd, 'rb', buffering=0) as pipe, os.fdopen(write_fd, 'wb', buffering=0) as writer:
                writer.write(('\n'.join(json.dumps(event) for event in events) + '\n').encode())
                stream = Stream(SimpleNamespace(stdout=pipe), 'root', [])
                with contextlib.redirect_stdout(io.StringIO()):
                    if rejected:
                        with self.assertRaises(RuntimeError): stream.expect(target, **kwargs)
                    else:
                        self.assertEqual(stream.expect(target, **kwargs)['pid'], 123)

    def test_stackshot_is_opt_in_and_release_only(self):
        for mode in ('release-control', 'broker-stop', 'broker-crash', 'root-quit', 'root-crash'):
            validate_options(mode, False)
            if mode == 'release-control':
                validate_options(mode, True)
            else:
                with self.assertRaises(ValueError): validate_options(mode, True)
        with patch('run_vm_suspended.subprocess.run') as process:
            with self.assertRaises(ValueError): run(SimpleNamespace(mode='broker-crash', stackshot=True))
            process.assert_not_called()

    def test_stackshot_budget_includes_command_observation_and_margin(self):
        self.assertTrue(stackshot_budget(10, (32, 40, 50)))
        self.assertFalse(stackshot_budget(10, (31, 40, 50)))
        self.assertFalse(stackshot_budget(10, (40, 30, 50)))

    def test_stackshot_rejects_suspension_or_identity_mutation(self):
        before = evidence()['beforeTrigger']
        after = dict(before, time=before['time'] + 1)
        self.assertTrue(stackshot_unchanged(before, after))
        for key, value in [('suspendCount', 0), ('suspendCount', 2), ('authenticated', False),
                           ('audit', [0] * 8), ('pid', 999), ('basicInfoStatus', 5)]:
            self.assertFalse(stackshot_unchanged(before, dict(after, **{key: value})))

    def test_inconclusive_stackshot_can_release_but_timeout_or_mutation_cannot_pass(self):
        item = evidence(); item.update(mode='release-control', resumedHello=dict(authenticated=True,
            provider=dict(pid=502, authenticated=True, guardDeadline=35, instance='new')),
            firstInstance='old', resumed=dict(item['identity'], time=12.1, suspendCount=0),
            providerStop=12.2, providerExit=dict(pid=502, time=12.3, status=0, fflags=0x84000000))
        item['brokerExit']['time'] = 13.1; item['rootExitObserved'] = 13
        item['stackshot'] = dict(before=dict(item['identity'], time=10.3),
            after=dict(item['identity'], time=10.9), started=10.4, timedOut=False,
            helloObserved=False, phaseQualified=False, status=1, diagnostic='inconclusive')
        self.assertEqual(classify(item), 'PASS')
        for field, value in [('timedOut', True), ('helloObserved', True), ('phaseQualified', True), ('started', 20)]:
            changed = dict(item, stackshot=dict(item['stackshot'], **{field: value}))
            self.assertNotEqual(classify(changed), 'PASS')
        item['stackshot']['after']['suspendCount'] = 2
        self.assertNotEqual(classify(item), 'PASS')

    def test_release_requires_same_provider_and_resumed_observation(self):
        item = evidence(); item.update(mode='release-control', resumedHello=dict(authenticated=True,
            provider=dict(pid=502, authenticated=True, guardDeadline=35, instance='new')),
            firstInstance='old', resumed=dict(item['identity'], time=12.1, suspendCount=0),
            providerStop=12.2, providerExit=dict(pid=502, time=12.3, status=0, fflags=0x84000000))
        item['brokerExit']['time'] = 13.1; item['rootExitObserved'] = 13
        self.assertEqual(classify(item), 'PASS')
        item['resumedHello']['provider']['pid'] = 1000
        self.assertNotEqual(classify(item), 'PASS')


if __name__ == '__main__': unittest.main()
