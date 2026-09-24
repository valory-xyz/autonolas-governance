#!/usr/bin/env python3
"""Collect pinned tag-to-tag source evidence for the interactive lineage."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / 'data' / 'tag-lineage'
REFS = ['v1.2.5-post-external-audit', 'v1.2.5', 'v1.3.0-pre-external-audit']
HEAD = '93901ec315eb2b1d4683aab5615ef38b071228f8'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    nodes = []
    for ref in REFS:
        sha = git('rev-parse', ref + '^{commit}')
        nodes.append(dict(label=ref, sha=sha, commitDate=git('show', '-s', '--format=%cs', sha),
                          tagDate=git('for-each-ref', '--format=%(creatordate:short)', 'refs/tags/' + ref)))
    nodes.append(dict(label='main · snapshot review', sha=HEAD,
                      commitDate=git('show', '-s', '--format=%cs', HEAD), tagDate=None))
    files = [p for p in git('ls-tree', '-r', '--name-only', HEAD, 'contracts').splitlines()
             if p.endswith('.sol') and '/test/' not in p and '/interfaces/' not in p]
    contracts = []
    for path in files:
        edges = []
        for index, (a, b) in enumerate(zip(nodes, nodes[1:])):
            subprocess.run(['git', 'merge-base', '--is-ancestor', a['sha'], b['sha']], cwd=ROOT, check=True)
            diff = git('diff', a['sha'], b['sha'], '--', path)
            stats = git('diff', '--numstat', a['sha'], b['sha'], '--', path)
            commits = git('log', '--format=%h %cs %s', a['sha'] + '..' + b['sha'], '--', path).splitlines()
            diff_name = path.replace('/', '__') + '__' + str(index) + '.diff'
            (OUT / diff_name).write_text(diff + ('\n' if diff else ''))
            edges.append(dict(changed=bool(diff), stats=stats, commits=commits, diffFile=diff_name))
        contracts.append(dict(name=Path(path).stem, path=path, edges=edges))
    payload = dict(nodes=nodes, contracts=contracts, tagSelectionCutoff='2026-05-01',
                   baselineRule='Last tag before May; include all subsequent tag deltas without filtering commit dates',
                   source='Local Git; source-file diffs, not compiled bytecode or live deployment')
    (OUT / 'lineage.json').write_text(json.dumps(payload, indent=2) + '\n')
    print(json.dumps(dict(nodes=nodes, contracts=len(contracts)), indent=2))


if __name__ == '__main__':
    main()
