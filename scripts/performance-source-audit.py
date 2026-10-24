"""Static performance evidence only; does not launch either game or benchmark it."""
import csv, hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/readable/chapters/diff/evidence'

def read_methods(version):
    with (OUT / 'metadata' / f'{version}-Assembly-CSharp.methods.tsv').open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f, delimiter='\t'))

def write(path, data, columns):
    with path.open('w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, columns, delimiter='\t')
        w.writeheader(); w.writerows(data)

data = {v: read_methods(v) for v in ('1.6', '1.7')}
targets = [
    'UnityEngine.Time::get_frameCount()',
    'UnityEngine.Time::get_deltaTime()',
    'UnityEngine.Time::get_realtimeSinceStartup()',
    'UnityEngine.Transform::get_position()',
]
callers = [
    {'target': t, 'old_caller_methods': sum(t in r['called_members'] for r in data['1.6']),
     'new_caller_methods': sum(t in r['called_members'] for r in data['1.7'])}
    for t in targets
]
write(OUT / 'performance-static-callers.tsv', callers, ['target', 'old_caller_methods', 'new_caller_methods'])
paths = ['RimWorld1.6/MonoBleedingEdge/EmbedRuntime/mono-2.0-bdwgc.dll',
         'RimWorld/coreclr.dll', 'RimWorld/clrjit.dll', 'RimWorld/clrgc.dll',
         'RimWorld/RimWorld.runtimeconfig.json']
files = [{'file': p, 'bytes': (ROOT / p).stat().st_size,
          'sha256': hashlib.sha256((ROOT / p).read_bytes()).hexdigest().upper()} for p in paths]
write(OUT / 'performance-runtime-files.tsv', files, ['file', 'bytes', 'sha256'])
print(json.dumps({'static_callers': callers, 'runtime_files': len(files), 'game_executed': False}, indent=2))
