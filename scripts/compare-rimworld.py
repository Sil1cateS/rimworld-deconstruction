"""Compare assembly metadata/IL inventories without executing game code."""
import csv, json, re, difflib, hashlib
from pathlib import Path
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/readable/chapters/diff/evidence'
META = OUT / 'metadata'

def read(prefix, kind, key):
    with (META / f'{prefix}.{kind}.tsv').open(encoding='utf-8-sig', newline='') as f:
        return {r[key]: r for r in csv.DictReader(f, delimiter='\t')}

def write_tsv(path, rows, columns):
    with path.open('w', encoding='utf-8', newline='') as f:
        w = csv.DictWriter(f, columns, delimiter='\t', extrasaction='ignore')
        w.writeheader(); w.writerows(rows)

def changes(kind, key, compare):
    old, new = [read(f'{v}-Assembly-CSharp', kind, key) for v in ('1.6', '1.7')]
    result = []
    for name in sorted(old.keys() | new.keys()):
        a, b = old.get(name), new.get(name)
        status = 'added' if a is None else 'removed' if b is None else 'unchanged' if all(a[k] == b[k] for k in compare) else 'changed'
        row = {'status':status, key:name, 'type':(b or a).get('type', name)}
        for col in compare:
            row[f'old_{col}'] = a[col] if a else ''
            row[f'new_{col}'] = b[col] if b else ''
        if kind == 'methods':
            row['generated_name'] = '<' in name or '/<>' in name
        result.append(row)
    columns = ['status',key] + ([] if key=='type' else ['type']) + [f'{v}_{c}' for c in compare for v in ('old','new')]
    if kind == 'methods': columns += ['generated_name']
    write_tsv(OUT/f'game-{kind}-diff.tsv', result, columns)
    return old, new, result

def source_clean(text):
    return '\n'.join(x.rstrip() for x in text.splitlines() if not re.match(r'\s*//.*(?:Token:|RID:|RVA:|File Offset:)',x))+'\n'

def source_diff():
    dest = OUT/'source-diffs'; dest.mkdir(exist_ok=True)
    oldroot, newroot = [ROOT/'analysis'/v/'Assembly-CSharp' for v in ('decompiled1.6','decompiled')]
    candidates=[]
    for old in oldroot.rglob('*.cs'):
        relative=old.relative_to(oldroot); new=newroot/relative
        if not new.exists(): continue
        a,b=[source_clean(p.read_text(encoding='utf-8-sig')) for p in (old,new)]
        if a==b: continue
        diff=list(difflib.unified_diff(a.splitlines(True),b.splitlines(True),fromfile=f'1.6/{relative.as_posix()}',tofile=f'1.7/{relative.as_posix()}',n=3))
        nplus=sum(x.startswith('+') and not x.startswith('+++') for x in diff)
        nminus=sum(x.startswith('-') and not x.startswith('---') for x in diff)
        candidates.append({'path':relative.as_posix(),'added_lines':nplus,'removed_lines':nminus})
        # Preserve all textual deltas; generated/compiler noise is explicitly unfiltered.
        (dest/(relative.as_posix().replace('/','__')+'.diff')).write_text(''.join(diff),encoding='utf-8')
    write_tsv(OUT/'source-diff-index.tsv',candidates,['path','added_lines','removed_lines'])
    return len(candidates)

def data_diff():
    oldroot,newroot=[ROOT/v/'Data' for v in ('RimWorld1.6','RimWorld')]
    extensions={'.xml','.txt','.json','.shader','.compute','.slang'}
    def scan(root):
        return {p.relative_to(root).as_posix():p for p in root.rglob('*') if p.is_file() and p.suffix.lower() in extensions}
    a,b=scan(oldroot),scan(newroot); rows=[]
    for key in sorted(a.keys() | b.keys()):
        old,new=a.get(key),b.get(key)
        status='added' if old is None else 'removed' if new is None else 'unchanged' if old.read_bytes()==new.read_bytes() else 'changed'
        rows.append({'status':status,'path':key})
    write_tsv(OUT/'data-text-files-diff.tsv',rows,['status','path'])
    return dict(Counter(r['status'] for r in rows))

def compatibility():
    types=read('1.7-UnityStubs','types','type')
    methods=read('1.7-UnityStubs','methods','method')
    fields=read('1.7-UnityStubs','fields','field')
    refs=read('1.6-Assembly-CSharp','typerefs','type')
    members=read('1.6-Assembly-CSharp','memberrefs','member')
    redirected=lambda s:s.startswith('UnityEngine') or (s.startswith('Unity.') and s!='Unity.Newtonsoft.Json') or s=='Assembly-CSharp-firstpass'
    rows=[{'kind':'type','name':n,'old_assembly':r['assembly'],'exact_definition_present':n in types} for n,r in refs.items() if redirected(r['assembly'])]
    rows += [{'kind':'member','name':n,'old_assembly':r['assembly'],'exact_definition_present':n in methods or n in fields} for n,r in members.items() if redirected(r['assembly'])]
    write_tsv(OUT/'old-game-unity-references.tsv',rows,['kind','name','old_assembly','exact_definition_present'])
    # Entire managed API surface, not equivalent to required API or runtime behavior.
    oldtypes={};oldmethods={};oldfields={}
    for p in META.glob('1.6-Unity*.types.tsv'):
        prefix=p.name.removesuffix('.types.tsv')
        oldtypes.update(read(prefix,'types','type'));oldmethods.update(read(prefix,'methods','method'));oldfields.update(read(prefix,'fields','field'))
    coverage={}
    for kind,old,new in [('types',oldtypes,types),('methods',oldmethods,methods),('fields',oldfields,fields)]:
        coverage[kind]={'old_definitions':len(old),'exact_name_signature_overlap':len(old.keys() & new.keys()),'new_definitions':len(new)}
    return {'old_game_direct_refs':dict(Counter(f"{r['kind']}_{r['exact_definition_present']}" for r in rows)),'all_old_unity_definitions':coverage}

def main():
    summary={}
    for kind,key,columns in [('types','type',['attributes','base','interfaces']),('methods','method',['attributes','impl_attributes','il_hash']),('fields','field',['attributes','constant'])]:
        a,b,rows=changes(kind,key,columns)
        summary[kind]={'old_count':len(a),'new_count':len(b),'status':dict(Counter(r['status'] for r in rows))}
        if kind=='types':
            summary['top_level_types']={'old':sum(r['type']==r['top_type'] for r in a.values()),'new':sum(r['type']==r['top_type'] for r in b.values())}
        if kind=='methods':
            summary['methods_without_generated_name']=dict(Counter(r['status'] for r in rows if not r['generated_name']))
    summary['compatibility']=compatibility()
    summary['source_changed_files']=source_diff()
    summary['data_text_files']=data_diff()
    (OUT/'comparison-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(summary,ensure_ascii=False,indent=2))
if __name__=='__main__': main()
