"""Bounded evidence from a fixed provider parked inside AppExtension.init."""
import math


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def classify(record):
    mode = record.get('mode')
    if mode not in ('broker-stop', 'broker-crash', 'root-quit', 'root-crash') or record.get('observationError'):
        return 'UNKNOWN'
    if any(record.get(k) is not True for k in ('authenticated', 'registered', 'confirmed', 'observerAlive')):
        return 'UNKNOWN'
    if any(record.get(k) not in ('initializer-pending', 'process-ready') for k in ('phaseBefore', 'phaseAfter')):
        return 'UNKNOWN'
    if any(not finite(record.get(k)) for k in ('trigger', 'providerGuard', 'brokerGuard', 'observerGuard', 'windowEnd')):
        return 'UNKNOWN'
    trigger = record['trigger']
    if trigger + 8.5 >= min(record['providerGuard'], record['brokerGuard'], record['observerGuard']): return 'UNKNOWN'
    if not trigger <= record['windowEnd'] < min(record['providerGuard'], record['brokerGuard'], record['observerGuard']):
        return 'UNKNOWN'
    exits = record.get('exits', {})
    for name in ('broker', 'provider'):
        event = exits.get(name, {})
        if not finite(event.get('time')) or type(event.get('status')) is not int: return 'UNKNOWN'
        if event['time'] < trigger: return 'UNKNOWN'
        expected = ((0,) if mode == 'broker-stop' else (9,)) if name == 'broker' and mode.startswith('broker-') else (9, 15)
        if event['time'] > min(trigger + 8, record['windowEnd']) or event['status'] not in expected: return 'FAIL'
    if mode.startswith('broker-'):
        return 'PASS' if record.get('rootAlive') is True else 'FAIL'
    if (record.get('rootStatus') != (0 if mode == 'root-quit' else -9)
            or not finite(record.get('rootExit')) or not trigger <= record['rootExit'] <= record['windowEnd']):
        return 'UNKNOWN'
    return 'PASS'
