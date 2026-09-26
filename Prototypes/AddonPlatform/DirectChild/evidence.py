"""Pure derivation for diagnostic observations, never session authentication."""

def exec_checks(events, pid, failure):
    observed = any(e.get('event') == 'exec-image-observed' and e.get('pid') == pid
                   and e.get('replacementMatch') is True for e in events)
    pipe_survived = observed and any(e.get('event') == 'replacement-running' and e.get('pid') == pid
                                     for e in events)
    return {'execReplacementObserved': observed,
            'diagnosticPipeSurvivedExec': pipe_survived,
            # No authenticated invalidation mechanism exists in this prototype.
            # Neither silence nor a fixture error supplies affirmative evidence.
            'sessionInvalidatedAfterExec': False}
