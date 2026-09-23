"""One-way import of the UI label seed into the existing localization source."""
import json
from pathlib import Path
root = Path(__file__).resolve().parents[2]
source = root / 'tools/localization/godsystem_v11645_localization.yml'
lines = source.read_text(encoding='utf-8-sig').splitlines()
labels = json.loads(Path(__file__).with_name('terminal_labels.json').read_text(encoding='utf-8'))
keys = {'Terminal_' + k for k in labels}
lines = [line for line in lines if line.split(': ', 1)[0] not in keys]
lines += ['Terminal_' + k + ': ' + json.dumps(v, ensure_ascii=False) for k, v in labels.items()]
source.write_text('\n'.join(lines) + '\n', encoding='utf-8')
