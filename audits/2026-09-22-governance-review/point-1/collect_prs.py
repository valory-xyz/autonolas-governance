"""Save primary GitHub PR metadata, discussion, and reviews without posting."""
import json
import subprocess
from pathlib import Path

out = Path(__file__).resolve().parent / 'data' / 'prs'
out.mkdir(parents=True, exist_ok=True)
for number in [178, 187, 199, 200, 209, 232, 233]:
    result = subprocess.run(['gh', 'pr', 'view', str(number), '--repo',
                             'valory-xyz/autonolas-governance', '--json',
                             'number,title,body,state,mergedAt,comments,reviews,url'],
                            capture_output=True, text=True, check=True)
    (out / f'{number}.json').write_text(result.stdout)
    data = json.loads(result.stdout)
    print(number, data['title'], len(data['comments']), len(data['reviews']))
