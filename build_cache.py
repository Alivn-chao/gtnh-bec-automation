"""Build a standalone cache worker from the tested streaming implementation."""
from pathlib import Path
root=Path(__file__).resolve().parent
source=(root/'bec_auto.lua').read_text(encoding='utf-8')
source=source[:source.index('local function serve()')]
for begin,end in [('local function checkRecipe(', 'local function tick('),
                  ('local function current(', 'local function waitUntil(')]:
    start=source.index(begin);stop=source.index(end,start)
    source=source[:start]+source[stop:]
source=source.replace('local mode = (...) or "preview"','local mode, cacheCopies = ...\nmode=mode or "preview"\nlocal fixedStock\nlocal background=mode=="background-stock"\nif mode=="preview-stock" or mode=="run-stock" or background then\n fixedStock=tonumber(cacheCopies)\n assert(fixedStock and fixedStock>=1 and fixedStock<=2147483647 and fixedStock==math.floor(fixedStock),"统一库存需指定正整数mB")\n mode=mode=="preview-stock" and "preview" or "run"\n cacheCopies=1\nelse cacheCopies=tonumber(cacheCopies) or 1 end')
source=source.replace('"/home/bec_auto.journal"','"/home/bec_cache.journal"')
guard='''local function unchanged()
  local state=call(NODE,"getState")
  local blocked={idle=true,["paused-immediate"]=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true}
  assert(state=="idle" or (background and blocked[state]),"节点状态变化，停止预缓存并保留已有库存")
  assert(call(RS,"getOutput",sides.top)==15,"暂停信号变化")
  field()
end
'''
source=source.replace('local function prepareStreaming(',guard+'local function prepareStreaming(',1)
source+='\n'+(root/'cache_main.lua.inc').read_text(encoding='utf-8')
(root/'bec_cache.lua').write_text(source,encoding='utf-8')
lines=[line.strip() for line in source.splitlines() if line.strip() and not line.lstrip().startswith('--')]
assert not any('--' in line for line in lines)
compact='\n'.join(' '.join(lines[i:i+3]) for i in range(0,len(lines),3))+'\n'
assert len(compact.splitlines())<=250
(root/'bec_cache_paste.lua').write_text(compact,encoding='utf-8')
print('Cache paste lines:',len(compact.splitlines()))
