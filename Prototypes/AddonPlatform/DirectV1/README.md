# Direct-v1 finite qualification probes

Diagnostic launchd process-group and Mach audit-token fixtures. No production launcher is enabled. See `docs/superpowers/verification/2026-09-10-addon-direct-v1.md` for the API rationale, failed containment cases, scope and logs.

- `scripts/test-addon-direct-v1-group.sh`: signs uniquely built helper/worker fixtures, probes group cleanup and sandbox restrictions, then boots out each unique temporary job. Characterization exit 0 does not imply admission.
- `scripts/test-addon-direct-v1-audit.sh`: signs isolated original/replacement fixtures, proves fresh kernel audit-token validation and session invalidation after exec. An exact fixture-only Mach lookup exception is explicit in the script.
- `evidence.py RECORD`: exact direct-v1 policy validator. The committed-to-workspace diagnostic record is expected to fail.
- `evidence.py --compose GROUP_RESULTS AUDIT_RESULTS OUTPUT`: produces a deliberately blocked integrated record with the isolated identity result under observations. Requires further integrated qualification before any check can become true.

Native cases have five-second external budgets and three-second fixture guard alarms. Worker guard alarms are not recovery. Do not signal discovered PID/name matches. Logs live separately from signed executable files. Only the tested machine/team is represented; a deployment target is not OS qualification.
