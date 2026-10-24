import sys, difflib, re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding='utf-8')
def clean(p):
    return [line+'\n' for line in p.read_text(encoding='utf-8-sig').splitlines() if not re.match(r'\s*//.*(?:Token:|RID:|RVA:|File Offset:)',line)]
for name in sys.argv[1:]:
    old,new=[root/'analysis'/v/'Assembly-CSharp'/name for v in ('decompiled1.6','decompiled')]
    print(''.join(difflib.unified_diff(clean(old),clean(new),fromfile='1.6/'+name,tofile='1.7/'+name,n=3)))
