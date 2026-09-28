#!/usr/bin/env python3
"""Reject incomplete addon evidence. Completeness never proves the producer honest."""
import json
import sys


def validate(record, scenario, required):
    if not isinstance(record, dict) or type(record.get('schemaVersion')) is not int or record['schemaVersion'] != 1:
        raise ValueError('schemaVersion must be 1')
    if record.get('scenario') != scenario:
        raise ValueError('scenario does not match')
    if record.get('unverified') != []:
        raise ValueError('unverified must be empty')
    if not required:
        raise ValueError('Serve almeno una verifica esplicita')
    checks = record.get('checks')
    if not isinstance(checks, dict):
        raise ValueError('checks must be an object')
    for check in required:
        if checks.get(check) is not True:
            raise ValueError(check)


if __name__ == '__main__':
    try:
        if len(sys.argv) < 4:
            raise ValueError('usage: assert-addon-evidence.py RECORD SCENARIO CHECK [CHECK ...]')
        with open(sys.argv[1]) as source:
            record = json.load(source)
        validate(record, sys.argv[2], sys.argv[3:])
    except (OSError, ValueError, TypeError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        sys.exit(1)
