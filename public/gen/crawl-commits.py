import subprocess, json, re, collections, sys
SEP='\x1e'; F='\x1f'
def git(*a): return subprocess.run(['git',*a],capture_output=True,text=True,check=True).stdout
raw=git('log','--reverse','--date=short',f'--format={SEP}%H{F}%h{F}%ad{F}%P{F}%s{F}%b')
commits=[]
for chunk in raw.split(SEP)[1:]:
    h,short,date,parents,subject,body=chunk.split(F,5)
    commits.append(dict(hash=h,short=short,date=date,parents=parents.split(),subject=subject.strip(),body=body.strip()))
byhash={c['hash']:c for c in commits}
for c in commits: c['files']={'added':[],'modified':[],'deleted':[]}; c['stat']={'files':0,'insertions':0,'deletions':0}
# files per commit
cur=None
for line in git('log','--name-status','--format=%x1e%H','--no-renames').split('\n'):
    if line.startswith(SEP): cur=byhash[line[1:]]; cur['files']={'added':[],'modified':[],'deleted':[]}; continue
    if not line.strip() or cur is None: continue
    st,path=line.split('\t',1)
    cur['files'][{'A':'added','M':'modified','D':'deleted'}.get(st[0],'modified')].append(path)
# shortstat
cur=None
for line in git('log','--shortstat','--format=%x1e%H').split('\n'):
    if line.startswith(SEP): cur=byhash[line[1:]]; cur['stat']={'files':0,'insertions':0,'deletions':0}; continue
    m=re.search(r'(\d+) files? changed',line)
    if m and cur:
        cur['stat']['files']=int(m.group(1))
        i=re.search(r'(\d+) insertions?',line); d=re.search(r'(\d+) deletions?',line)
        cur['stat']['insertions']=int(i.group(1)) if i else 0
        cur['stat']['deletions']=int(d.group(1)) if d else 0
# command / table-row additions from patches of the command-defining files
cur=None
for c in commits: c['commands_added']=[]; c['commands_removed']=[]
patch=git('log','-p','--format=%x1e%H','--no-renames','--','src','core','modules','pkg','maf.el')
PUBLIC=r'(?!maf--|mafcmd--)(?:maf|mafcmd)-[a-z0-9-]+'
pending=None  # (name, lines-left) for an added defun awaiting its (interactive)
for line in patch.split('\n'):
    if line.startswith(SEP): cur=byhash[line[1:]]; pending=None; continue
    if cur is None: continue
    if line.startswith('+++') or line.startswith('---'): continue
    if pending:
        name,left=pending
        if re.search(r'\(interactive\b',line): cur['commands_added'].append(name); pending=None
        elif left<=0 or re.match(r'^[+ -]?\(def',line): pending=None
        else: pending=(name,left-1)
    m=re.match(r'^\+\(maf-defcmd ('+PUBLIC+')',line)
    if m: cur['commands_added'].append(m.group(1)); continue
    m=re.match(r'^\+  \(([a-z0-9-]+) (?:unary|binary) ',line)
    if m: cur['commands_added'].append('mafcmd-'+m.group(1)); continue
    m=re.match(r'^\+\(defun ('+PUBLIC+') ',line)
    if m: pending=(m.group(1),150); continue
    m=re.match(r'^-\(maf-defcmd ('+PUBLIC+')',line) or re.match(r'^-\(defun ('+PUBLIC+') ',line)
    if m: cur['commands_removed'].append(m.group(1)); continue
    m=re.match(r'^-  \(([a-z0-9-]+) (?:unary|binary) ',line)
    if m: cur['commands_removed'].append('mafcmd-'+m.group(1))
for c in commits:
    # a move within one commit is not an addition
    moved=set(c['commands_added'])&set(c['commands_removed'])
    c['commands_added']=sorted(set(c['commands_added'])-moved)
    c['commands_removed']=sorted(set(c['commands_removed'])-moved)
NOISE=re.compile(r'^(modified|new file|deleted|renamed|added|Untracked):\s')
ADD=('Add','Bind','Port','Introduce','Land','New')
FIX=('Fix','Repair','Guard','Stop','Prevent','Avoid','Correct')
REFACTOR=('Move','Rename','Fold','Split','Extract','Reword','Tidy','Simplify','Hoist','Inline')
def classify(c):
    s=c['subject']; files=c['files']; allf=files['added']+files['modified']+files['deleted']
    if len(c['parents'])>1: return 'merge'
    if s.startswith('Revert '): return 'revert'
    if NOISE.match(s) or re.match(r'^[\w./-]+\.(el|org|md|sh):\s*$',s): return 'note'
    first=s.split()[0] if s else ''
    if c['modules_added'] or c['commands_added'] or first in ADD: return 'addition'
    if allf and all(p.startswith('docs/') or p in ('CLAUDE.md','README.md') for p in allf): return 'docs'
    if allf and all(p.startswith(('tests/','sandbox/','human-tests/','manual-tests/')) for p in allf): return 'tests'
    if first in FIX: return 'fix'
    if first in REFACTOR: return 'refactor'
    return 'change'
for c in commits:
    c['modules_added']=sorted(p for p in c['files']['added'] if re.match(r'^(modules/maf-[\w-]+\.el|pkg/[\w-]+/[\w-]+\.el)$',p))
    c['tests_added']=sorted(p for p in c['files']['added'] if re.match(r'^tests/[\w-]+\.el$',p))
    c['areas']=sorted({p.split('/')[0] if '/' in p else p for p in c['files']['added']+c['files']['modified']+c['files']['deleted']})
    c['type']=classify(c)
tags={}
for line in git('tag','-l','--format=%(if)%(*objectname)%(then)%(*objectname)%(else)%(objectname)%(end) %(refname:short)').split('\n'):
    if line.strip(): h,t=line.split(); tags[h]=t
for c in commits: c['tag']=tags.get(c['hash'])
months=collections.OrderedDict()
for c in commits:
    m=c['date'][:7]; months.setdefault(m,collections.Counter())[c['type']]+=1
summary=dict(total=len(commits),first=commits[0]['date'],last=commits[-1]['date'],
             by_type=dict(collections.Counter(c['type'] for c in commits)),
             by_month={m:dict(v) for m,v in months.items()},
             commands_added=sum(len(c['commands_added']) for c in commits),
             modules_added=sum(len(c['modules_added']) for c in commits),
             tests_added=sum(len(c['tests_added']) for c in commits))
out=dict(generated=commits[-1]['date'],summary=summary,commits=commits)
json.dump(out,open('public/data/commits.json','w'),ensure_ascii=False)
open('public/data/commits.js','w').write('window.MAF_COMMITS = '+json.dumps(out,ensure_ascii=False)+';\n')
print(json.dumps(summary,indent=1))
