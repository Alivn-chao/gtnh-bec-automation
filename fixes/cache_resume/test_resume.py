"""Lua 5.2 checks for the narrow V1 cache-working recovery patch."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'work/lua_runtime'))
from lupa.lua52 import LuaRuntime

source = (Path(__file__).parent / 'patch_v1.lua').read_text(encoding='utf-8')
block = re.search(r'local patch = \[=\[(.*?)\]=\]', source, re.S).group(1)
setup = r'''
old={stage='cache-working',lastState='idle',expected={},secured={}}
cache={version=1,kind='cache',background=true,stage='stopped',incomplete=false,
  configOwned=false,requests={},transfers={{ok=true,amount=3456,requested=3456}},
  target={entangled_hypogen=144000}}
state='idle';output=15;allowed=false;active=false;sub={};stock={entangled_hypogen=144000}
ser={unserialize=function()return cache end}
io={open=function()return {read=function()return 'cache' end,close=function()end}end}
NODE='node';RS='rs';GEN='gen';SUB='sub';sides={top=1}
function call(a,m) if m=='getState'then return state elseif m=='getOutput'then return output
elseif m=='isWorkAllowed'then return allowed elseif m=='isMachineActive'then return active end end
function network()return sub end
function field()return stock end
function integer(n)assert(type(n)=='number'and n>=0 and n==math.floor(n));return n end
print=function()end
'''
cases = [
    ('completed cache recovers', '', True),
    ('pending transfer blocked', 'cache.pending={}', False),
    ('partial transfer blocked', 'cache.transfers[1].requested=4000', False),
    ('unconfirmed transfer blocked', 'cache.transfers[1].ok=false', False),
    ('craft in progress blocked', "cache.requests={{state='submitted'}}", False),
    ('incomplete cache blocked', 'cache.incomplete=true', False),
    ('non-stopped cache blocked', "cache.stage='converting'", False),
    ('remaining raw fluid blocked', "sub={['molten.hypogen']=3456}", False),
    ('actual cache shortage blocked', 'stock.entangled_hypogen=143000', False),
    ('generator running blocked', 'active=true', False),
    ('unpaused node blocked', 'output=0', False),
    ('new order blocked for manual review', "state='paused-immediate'", False),
    ('old production raw records blocked', "old.secured={raw=144}", False),
    ('missing cache record blocked', 'cache=nil', False),
]
for label, change, expected in cases:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(setup + change)
    result = lua.eval('function()return pcall(function()' + block + 'end)end')()
    ok = result[0] if isinstance(result, tuple) else result
    assert ok == expected, label
    assert lua.globals().old.stage == ('waiting' if expected else 'cache-working'), label
    print(label + ': PASS')

# Run the actual installer against an in-memory filesystem and real controller text.
controller = (ROOT / 'outputs/nanites_switch/bec_auto.lua').read_text(encoding='utf-8')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
files={};writes=0
io={open=function(p,mode)
 if mode=='r' and files[p]==nil then return nil end
 local text=mode=='w' and '' or files[p]
 return {read=function()return text end,write=function(_,v)text=text..v;return true end,
 flush=function()files[p]=text;writes=writes+1;return true end,close=function()end}
end}
local fs={exists=function(p)return files[p]~=nil end,rename=function(a,b)
 if files[a]==nil or files[b]~=nil then return false end
 if failInstall and a:find('cache-resume-new',1,true)then return false end
 files[b]=files[a];files[a]=nil;return true end}
require=function()return fs end
print=function()end
''')
path = '/home/bec_auto.lua'
lua.globals().files[path] = controller
lua.globals().files['/home/bec_auto.journal'] = 'preserve production journal'
lua.globals().files['/home/bec_cache.journal'] = 'preserve cache journal'
install = lua.eval('function()' + source + '\nend')
lua.globals().failInstall = True
try:
    install()
    raise AssertionError('Expected installation failure')
except Exception as err:
    assert '已还原原文件' in str(err), err
assert lua.globals().files[path] == controller
lua.globals().files['/home/bec_auto.lua.cache-resume-new'] = None
lua.globals().failInstall = False
install()
patched = lua.globals().files[path]
assert patched.count('BEC_V1_CACHE_RESUME_V1') == 1
assert lua.globals().files[path + '.before-cache-resume-1'] == controller
lua.execute('assert(load(...))', patched)
writes = lua.globals().writes
install()
assert lua.globals().writes == writes
assert lua.globals().files['/home/bec_auto.journal'] == 'preserve production journal'
assert lua.globals().files['/home/bec_cache.journal'] == 'preserve cache journal'
print('Installer syntax, backup, rollback, repeat installation and unchanged journals: PASS')
