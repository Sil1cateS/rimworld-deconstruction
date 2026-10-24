import csv,difflib,json,sys,xml.etree.ElementTree as ET
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding='utf-8')
out=root/'docs/readable/chapters/diff/evidence'
rows=list(csv.DictReader((out/'data-text-files-diff.tsv').open(encoding='utf-8'),delimiter='\t'))
text=['# Data 文本差异原文\n\n只比较两份本地样本的 Data 目录；不是全部图片、音频与二进制资源。\n']
for r in rows:
    if r['status']=='unchanged':continue
    name=r['path'];text.append(f"\n## {r['status']}: {name}\n")
    old,new=[root/v/'Data'/name for v in ('RimWorld1.6','RimWorld')]
    if r['status']=='changed':
        a,b=[p.read_text(encoding='utf-8-sig').splitlines(True) for p in (old,new)]
        text+=['\n```diff\n',''.join(difflib.unified_diff(a,b,fromfile='1.6/'+name,tofile='1.7/'+name,n=3)),'```\n']
    elif new.suffix=='.xml':
        tree=ET.parse(new);counts={}
        for x in tree.getroot():counts[x.tag]=counts.get(x.tag,0)+1
        text.append('\nXML 顶层节点计数：`'+json.dumps(counts,ensure_ascii=False)+'`。\n')
(out/'data-deltas.md').write_text(''.join(text),encoding='utf-8')
print(''.join(text))
