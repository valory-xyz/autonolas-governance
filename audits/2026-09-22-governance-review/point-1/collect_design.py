"""Extract design text for source review; does not interpret figures or alter PDFs."""
from pathlib import Path
from pypdf import PdfReader

here = Path(__file__).resolve().parent
root = here.parents[2]
out = here / 'data' / 'design'
out.mkdir(parents=True, exist_ok=True)
for name in ['Specs of governance contracts_v1.1.0.pdf', 'Governance_process.pdf']:
    reader = PdfReader(root / 'docs' / name)
    text = '\n'.join(f'\nPAGE {i + 1}\n' + (page.extract_text() or '')
                     for i, page in enumerate(reader.pages))
    (out / (name + '.txt')).write_text(text)
