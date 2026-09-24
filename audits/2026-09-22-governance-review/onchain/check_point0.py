#!/usr/bin/env python3
"""Offline reconciliation of saved point-0 evidence; no new chain queries."""
import json
from collections import Counter
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
START = datetime.fromisoformat('2026-05-01T00:00:00+02:00')
rows = json.loads((HERE / 'data/timeline.json').read_text())
raw = json.loads((HERE / 'data/raw_logs.json').read_text())
assert len({(r['tx'], r['logIndex']) for r in rows}) == len(rows), 'Duplicate events'
assert len(rows) == len(raw['logs']), 'Raw/decoded event count differs'
artifacts = []
for folder in sorted((ROOT / 'scripts/proposals').glob('proposal_*')):
    if (folder / 'description.txt').exists() and (folder / 'calldata.json').exists():
        artifacts.append((folder.name, (folder / 'description.txt').read_text(),
                          json.loads((folder / 'calldata.json').read_text())))

def calls(args):
    assert not any(args['signatures']), 'Non-empty Bravo signatures require normalization'
    return [(t.lower(), int(v), d.lower()) for t, v, d in
            zip(args['targets'], args['values'], args['calldatas'])]

proposals = []
for row in rows:
    if row['event'] != 'ProposalCreated' or datetime.fromisoformat(row['time'].replace('Z', '+00:00')) < START:
        continue
    args = row['args']
    related = [r for r in rows if r['contract'] == row['contract']
               and r['args'].get('proposalId') == args['proposalId']]
    lifecycle = [r for r in related if r['event'] in ('ProposalExecuted', 'ProposalCanceled')]
    votes = Counter()
    for r in related:
        if r['event'] == 'VoteCast':
            votes[int(r['args']['support'])] += int(r['args']['weight'])
    status = lifecycle[-1]['event'] if lifecycle else 'No terminal event'
    if not lifecycle and int(args['endBlock']) < raw['to'] and votes[1] == 0 and votes[0] > 0:
        status = 'Defeated (inferred: ended, zero For, positive Against)'
    matches = []
    for name, description, artifact in artifacts:
        expected = [(c['target'].lower(), int(c['value']), c['calldata'].lower()) for c in artifact]
        actual = calls(args)
        same_positions = [i for i, (a, b) in enumerate(zip(actual, expected)) if a == b]
        if description == args['description'] or (len(same_positions) >= 3 and len(same_positions) / len(expected) > .5):
            matches.append(dict(artifact=name, description_exact=description == args['description'],
                                calls_exact=actual == expected, artifact_calls=len(expected),
                                matching_call_indices=same_positions,
                                differing_shared_indices=[i for i, (a, b) in enumerate(zip(actual, expected)) if a != b],
                                additional_onchain_indices=list(range(len(expected), len(actual))),
                                match_basis='exact description or candidate based on majority of same-position calls'))
    proposals.append(dict(governor=row['contract'], proposalId=args['proposalId'],
                          created=row['time'], title=args['description'].split('.')[0],
                          call_count=len(args['targets']), status=status,
                          terminal_date=lifecycle[-1]['time'] if lifecycle else None,
                          creation_tx=row['tx'], artifact_matches=matches,
                          for_votes=str(votes[1]), against_votes=str(votes[0])))

# Match Timelock operations by ID/index, rather than merely subtracting totals.
scheduled = {(r['args']['id'], r['args']['index']) for r in rows if r['event'] == 'CallScheduled'}
executed = {(r['args']['id'], r['args']['index']) for r in rows if r['event'] == 'CallExecuted'}
cancelled = {r['args']['id'] for r in rows if r['event'] == 'Cancelled'}
unresolved = sorted(k for k in scheduled if k not in executed and k[0] not in cancelled)
result = dict(selection_start=START.isoformat(), source_to_block=raw['to'],
              method='Offline saved-log reconciliation; no new RPC or failed-transaction search',
              proposal_count=len(proposals), outcomes=dict(Counter(p['status'] for p in proposals)),
              proposals=proposals, timelock_collected_window=dict(scheduled_calls=len(scheduled),
                  executed_calls=len(executed), calls_in_cancelled_operations=sum(k[0] in cancelled for k in scheduled),
                  unresolved_collected_calls=unresolved),
              limitations=['Defeated status inferred from saved votes and endBlock, not a fresh state() call.',
                           'No claims about uncollected addresses, pre-window pending operations, reverted attempts or L2 completion.',
                           'Positional overlap identifies candidate artifacts; only explicit equality establishes an exact match.'])
(HERE / 'data/point0_reconciliation.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({k:v for k,v in result.items() if k!='proposals'}, indent=2))
for p in proposals:
    print(p['created'][:10], p['call_count'], p['status'],
          [(m['artifact'], m['description_exact'], m['calls_exact']) for m in p['artifact_matches']])
