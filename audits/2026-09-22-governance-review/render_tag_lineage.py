#!/usr/bin/env python3
"""Populate the literal HTML template from collected, pinned Git evidence."""
import argparse
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('output', type=Path)
args = parser.parse_args()
data_dir = HERE / 'data' / 'tag-lineage'
data = json.loads((data_dir / 'lineage.json').read_text())
for contract in data['contracts']:
    for edge in contract['edges']:
        edge['diff'] = (data_dir / edge['diffFile']).read_text()
payload = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')
fragment = (HERE / 'tag-lineage.template.html').read_text().replace('__LINEAGE_DATA__', payload)
args.output.write_text(fragment)
print(f'{args.output}: {len(fragment.encode())} bytes')
