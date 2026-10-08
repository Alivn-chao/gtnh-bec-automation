"""Build copy/paste artifacts without changing the Lua token sequence."""
from pathlib import Path
root=Path(__file__).resolve().parent
source=(root/'bec_auto.lua').read_text(encoding='utf-8')
lines=source.splitlines(keepends=True)
for i,offset in enumerate(range(0,len(lines),250),1):
    (root/f'bec_auto.part{i}.txt').write_text(''.join(lines[offset:offset+250]),encoding='utf-8')
# This source uses only full-line comments, no multiline strings/comments.
assert '[[' not in source and '[=' not in source
code=[]
for line in source.splitlines():
    line=line.strip()
    if not line or line.startswith('--'): continue
    assert '--' not in line
    code.append(line)
compact='\n'.join(' '.join(code[i:i+3]) for i in range(0,len(code),3))+'\n'
assert len(compact.splitlines())<=250
(root/'bec_auto_paste.lua').write_text(compact,encoding='utf-8')
print(f'Full paste version: {len(compact.splitlines())} lines; split copies: {(len(lines)+249)//250}')
