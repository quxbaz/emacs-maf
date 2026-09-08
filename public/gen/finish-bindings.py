"""Normalize public/data/bindings.json after export-bindings.el and emit bindings.js.

json.el writes the :null keyword as the string "null"; this turns those into real
nulls and keys the variants by command name. Run from the repository root.
"""
import json
p = 'public/data/bindings.json'
d = json.load(open(p))
for prof in d['profiles']:
    for g in prof['groups']:
        for it in g['items']:
            for k in ('title', 'example', 'example_latex', 'example_parts', 'inv', 'hyp', 'invhyp'):
                if it[k] == 'null': it[k] = None
variants = d.get('variants', [])
if isinstance(variants, list):
    for it in variants:
        for k in ('title', 'example', 'example_latex', 'example_parts'):
            if it[k] == 'null': it[k] = None
    d['variants'] = {it['cmd']: it for it in variants}
json.dump(d, open(p, 'w'), ensure_ascii=False)
open('public/data/bindings.js', 'w').write('window.MAF_BINDINGS = ' + json.dumps(d, ensure_ascii=False) + ';\n')
n = d['profiles'][0]
print('profiles', [p['name'] for p in d['profiles']], 'native items', sum(len(g['items']) for g in n['groups']), 'variants', len(d['variants']))
