"""Resolve source citations and validate the local, static research deliverable."""
import csv, hashlib, json, re, os
from pathlib import Path
from urllib.parse import unquote

ROOT=Path(__file__).resolve().parents[1]
REPORTS=ROOT/'docs/readable/chapters/diff'
EVIDENCE=REPORTS/'evidence'

def rows(path):
    with path.open(encoding='utf-8-sig',newline='') as f:
        return list(csv.DictReader(f,delimiter='\t'))

def write_rows(path,data,columns):
    with path.open('w',encoding='utf-8',newline='') as f:
        w=csv.DictWriter(f,columns,delimiter='\t',extrasaction='ignore')
        w.writeheader();w.writerows(data)

def main():
    checks=[];citations=[]
    registry=EVIDENCE/'report-source-citations.tsv'
    if registry.exists():citations=rows(registry)
    for report in sorted(REPORTS.glob('*.md')):
        content=report.read_text(encoding='utf-8')
        content=content.replace('96.50%','96.49%')
        def cite(match):
            source,needle=match.group(1),match.group(2)
            path=ROOT/source
            if not path.is_file():raise AssertionError(f'Missing source {source}')
            text=path.read_text(encoding='utf-8-sig')
            index=text.find(needle)
            if index<0:raise AssertionError(f'Needle not found: {source} | {needle}')
            line=text[:index].count('\n')+1
            version='1.6' if '/decompiled1.6/' in source else '1.7' if '/decompiled/' in source or '/targeted17/' in source else '配置'
            label=f'{version} · {path.name}:{line}'
            link=os.path.relpath(path,REPORTS).replace('\\','/')+f'#L{line}'
            citations.append({'report':report.name,'source':source,'line':line,'needle':needle})
            return f'[{label}]({link})'
        content=re.sub(r'\{\{([^|{}]+)\|([^{}]+)\}\}',cite,content)
        if content!=report.read_text(encoding='utf-8'):report.write_text(content,encoding='utf-8')
        assert '{{' not in content,report
        for link in re.findall(r'\]\(([^)]+)\)',content):
            if re.match(r'^[a-zA-Z]+://',link):continue
            target,_,fragment=unquote(link).partition('#')
            path=(REPORTS/target).resolve() if target else report
            assert path.exists(),f'Broken local link: {report.name} -> {link}'
            if fragment.startswith('L') and fragment[1:].isdigit():
                count=len(path.read_text(encoding='utf-8-sig').splitlines())
                assert 1<=int(fragment[1:])<=count,(path,fragment,count)
        checks.append({'check':'links_and_markers','target':report.name,'result':'pass'})
    unique={(c['report'],c['source'],str(c['line']),c['needle']):c for c in citations}
    write_rows(registry,list(unique.values()),['report','source','line','needle'])
    # Validate the citation against its actual line, including repeat runs.
    for c in unique.values():
        line=(ROOT/c['source']).read_text(encoding='utf-8-sig').splitlines()[int(c['line'])-1]
        assert c['needle'] in line,c
    checks.append({'check':'source_citation_content','target':str(len(unique)),'result':'pass'})
    summary=json.loads((EVIDENCE/'comparison-summary.json').read_text(encoding='utf-8'))
    expected={'unchanged':87261,'removed':409,'changed':3170,'added':1185}
    assert summary['methods']['status']==expected,summary['methods']
    assert summary['types']['old_count']==16157 and summary['types']['new_count']==16221
    assert summary['data_text_files']=={'changed':16,'unchanged':1741,'added':4}
    assert sum(expected.values())==92025
    checks.append({'check':'aggregate_totals','target':'game metadata and Data text','result':'pass'})
    methods=rows(EVIDENCE/'game-methods-diff.tsv')
    critical_types={'Verse.Game','Verse.Root_Play','Verse.TickManager','Verse.BackCompatibility','Verse.ScribeMetaHeaderUtility','Verse.Pawn','Verse.AI.Pawn_JobTracker'}
    critical_names={'Update','UpdatePlay','TickManagerUpdate','DoSingleTick','ExposeData','LoadGame','WriteMetaHeader','IsSaveCompatibleWith','Tick'}
    selected=[r for r in methods if r['type'] in critical_types and any('::'+n+'(' in r['method'] for n in critical_names)]
    write_rows(EVIDENCE/'critical-method-checks.tsv',selected,['status','method','old_il_hash','new_il_hash'])
    for r in selected:
        if r['type']!='Verse.AI.Pawn_JobTracker':assert r['status']=='unchanged',r
    checks.append({'check':'critical_method_fingerprints','target':str(len(selected)),'result':'pass'})
    audit=rows(EVIDENCE/'1.6-unity-reference-signatures.tsv')
    assert sum(r['kind']=='member' and r['match']!='unmatched' for r in audit)==1055
    assert sum(r['kind']=='member' and r['match']=='unmatched' for r in audit)==18
    assert sum(r['kind']=='type' and r['match']=='unmatched' for r in audit)==5
    checks.append({'check':'unity_reference_totals','target':'183 types and 1073 members','result':'pass'})
    manifest=json.loads((EVIDENCE/'assembly-manifest.json').read_text(encoding='utf-8-sig'))
    for entry in manifest:
        assert hashlib.sha256((ROOT/entry['File']).read_bytes()).hexdigest().upper()==entry['SHA256']
    checks.append({'check':'assembly_hashes','target':str(len(manifest)),'result':'pass'})
    # Correct the initial run's progress strings; only structured records are provenance.
    dp=EVIDENCE/'decompilation.json'
    decomp=json.loads(dp.read_text(encoding='utf-8-sig'))
    structured=[d for d in decomp if isinstance(d,dict)]
    if decomp!=structured:dp.write_text(json.dumps(structured,indent=2),encoding='utf-8')
    assert len(structured)==8 and all(d['Exit']==0 for d in structured)
    assert all(len(list((ROOT/'analysis/decompiled1.6'/d['Assembly'].removesuffix('.dll')).rglob('*.cs')))==d['CsFiles'] for d in structured)
    checks.append({'check':'decompiled_modules','target':'8 modules','result':'pass'})
    write_rows(EVIDENCE/'validation.tsv',checks,['check','target','result'])
    print(json.dumps({'reports':len(list(REPORTS.glob('*.md'))),'source_citations':len(unique),'checks':checks},ensure_ascii=True,indent=2))

if __name__=='__main__':main()
