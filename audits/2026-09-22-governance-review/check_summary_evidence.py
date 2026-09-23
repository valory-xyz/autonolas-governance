"""Offline consistency checks for published references; no independent chain proof.

--check-raw additionally compares retained local input hashes when available.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check-raw', action='store_true')
args = parser.parse_args()
evidence = json.loads((ROOT / 'evidence.json').read_text())
checks = []


def check(name, condition):
    checks.append({'claim': name, 'matches_recorded_references': bool(condition)})


proposals = evidence['proposalInventory']
check('12 proposals: 9 executed, 1 cancelled, 2 inferred defeated',
      proposals['proposal_count'] == 12 and proposals['outcomes'] == {
          'ProposalExecuted': 9, 'ProposalCanceled': 1,
          'Defeated (inferred: ended, zero For, positive Against)': 2})
roles = evidence['roleHistory']
check('31 role events from deployment; pin 26032428', roles['eventCount'] == 31
      and len(roles['events']) == 31 and roles['deploymentBoundary']['beforeCodeEmpty']
      and evidence['pin']['number'] == 26032428)
addresses = evidence['addresses']
gov, tl, cm = (addresses[k].lower() for k in ['governor', 'timelock', 'cm'])
expected = {'TIMELOCK_ADMIN_ROLE': {tl, gov}, 'PROPOSER_ROLE': {gov, cm},
            'EXECUTOR_ROLE': {gov, cm}, 'CANCELLER_ROLE': {gov}, 'DEFAULT_ADMIN_ROLE': set()}
for role in roles['roles']:
    check(role['name'] + ' holders and administrator', set(role['holders']) == expected[role['name']]
          and role['adminName'] == ('DEFAULT_ADMIN_ROLE' if role['name'] == 'DEFAULT_ADMIN_ROLE'
                                   else 'TIMELOCK_ADMIN_ROLE'))
snapshot = evidence['parameterSnapshots'][-1]
check('Pinned timing, proposal threshold and quorum', snapshot['block'] == 26032428
      and snapshot['minDelay'] == '0' and all(snapshot['parameters'][k] == v for k, v in {
          'votingDelay': '13091', 'votingPeriod': '19636', 'governorDelay': '157092',
          'proposalThreshold': str(250000 * 10**18), 'quorumNumerator': '10', 'quorumDenominator': '100'}.items()))
check('Heartbeat unknown; only enabled CM module is Timelock',
      'unknown proposal id' in str(evidence['guardState']['heartbeatState'])
      and [x.lower() for x in evidence['cmModules']] == [tl])
cases = evidence['tests']['recovery-tests.txt']['cases']
check('Nine recorded recovery fork tests passed', len(cases) == 9 and all(x['result'] == 'PASS' for x in cases))
reports = ['README.md', 'SUMMARY.md', 'EVIDENCE.md', 'CONTRACT_MATRIX.md', 'onchain/AREA0.md',
           'point-1/README.md', 'point-1/ROLES_AND_RECOVERY.md', 'point-3/DEPLOYMENT.md']
# Holder eligibility and quorum coverage are a separate voting-power follow-up; their
# evidence is not published here, so no holder checks run in this index.
missing, bad_anchors = [], []
for name in reports:
    source = ROOT / name
    for href in re.findall(r'\]\(([^)]+)\)', source.read_text()):
        if href.startswith(('https:', 'http:', 'mailto:')):
            continue
        filename, _, anchor = unquote(href).partition('#')
        target = (source.parent / filename).resolve() if filename else source
        try:
            relative = str(target.relative_to(ROOT.resolve()))
        except ValueError:
            relative = ''
        unpublished = relative in ['WORK_PLAN.md', 'area1_timelock_delay.md'] or (
            relative.startswith(('data/', 'onchain/data/', 'point-1/data/', 'point-3/data/', 'holders/data/', '.local-archive/'))
            and relative != 'point-1/data/pin.json')
        if not target.exists() or unpublished:
            missing.append({'file': name, 'link': href})
        elif anchor and target.suffix == '.md':
            headings = re.findall(r'^#{1,6} (.+)$', target.read_text(), re.MULTILINE)
            slugs = {re.sub(r'[^\w\- ]', '', h.lower()).replace(' ', '-') for h in headings}
            if anchor not in slugs:
                bad_anchors.append({'file': name, 'link': href})
check('All reports link to published files or original sources', not missing)
check('All report section references resolve', not bad_anchors)
items = [line for line in (ROOT / 'SUMMARY.md').read_text().splitlines() if re.match(r'- \[[ x]\] ', line)]
check('Every checklist item has a reference', all(re.search(r'\]\([^)]+\)', line) for line in items))
raw_results = []
if args.check_raw:
    for name, expected_hash in evidence['inputSha256'].items():
        path = ROOT / name
        matched = path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == expected_hash
        raw_results.append({'file': name, 'matches': matched})
    for name, expected_hash in deployment['localInputSha256'].items():
        path = ROOT / 'point-3/data' / name
        matched = path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == expected_hash
        raw_results.append({'file': 'point-3/data/' + name, 'matches': matched})
    check('Local raw inputs match recorded SHA-256 hashes', all(x['matches'] for x in raw_results))
result = {'method': 'Offline consistency check against compact recorded references; not a fresh RPC check or independent proof',
          'checks': checks, 'missing_or_unpublished_links': missing, 'unresolved_anchors': bad_anchors,
          'raw_checks': raw_results}
out = ROOT / 'data/summary-evidence-check.json'
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'checks': len(checks), 'matched': sum(x['matches_recorded_references'] for x in checks),
                  'missing_links': missing, 'unresolved_anchors': bad_anchors}, indent=2))
if not all(x['matches_recorded_references'] for x in checks):
    raise SystemExit(1)
