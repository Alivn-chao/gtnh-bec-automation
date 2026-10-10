"""Lua 5.2 checks for the narrow V1 cache-working recovery patch."""
import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'work/lua_runtime'))
from lupa.lua52 import LuaRuntime

source = (Path(__file__).parent / 'patch_v1.lua').read_text(encoding='utf-8')
block = re.search(r'local patch = \[=\[(.*?)\]=\]', source, re.S).group(1)
setup = r'''
old={stage='cache-working',lastState='idle',expected={},secured={},configOwned=false,requests={},transfers={}}
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
    ('new paused order recovers', "state='paused-immediate';old.lastState='paused-immediate'", True),
    ('historical state absent but real node paused recovers', "state='paused-immediate';old.lastState=nil", True),
    ('bee mismatch paused order recovers for normal switching', "state='nanite-tier-too-low'", True),
    ('actively crafting node blocked', "state='crafting'", False),
    ('unconfirmed old plan blocked', 'old.plan={}', False),
    ('historical production raw records do not block empty real subnet', "old.expected={raw=144};old.secured={raw=144};old.requests={{state='done'}};old.transfers={{ok=true,amount=144,requested=144}}", True),
    ('historical records with actual leftover fluid blocked', "old.secured={raw=144};sub={raw=144}", False),
    ('old production pending transfer blocked', 'old.pending={}', False),
    ('old production pending request blocked', "old.requests={{state='submitted'}}", False),
    ('old production partial transfer blocked', 'old.transfers={{ok=true,amount=144,requested=288}}', False),
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
assert patched.count('BEC_V1_CACHE_RESUME_V3') == 1
assert lua.globals().files[path + '.before-cache-resume-1'] == controller
lua.execute('assert(load(...))', patched)
writes = lua.globals().writes
install()
assert lua.globals().writes == writes
assert lua.globals().files['/home/bec_auto.journal'] == 'preserve production journal'
assert lua.globals().files['/home/bec_cache.journal'] == 'preserve cache journal'
print('Installer syntax, backup, rollback, repeat installation and unchanged journals: PASS')

# Upgrade the previously installed V1 recovery block, without touching other code.
legacy = block.replace('BEC_V1_CACHE_RESUME_V3', 'BEC_V1_CACHE_RESUME_V1')
legacy = legacy.replace('-- expected/secured describe the prior production round, not live inventory.',
    'assert(next(old.secured)==nil,"缓存恢复：旧生产还有原液记录，保留日志核对")')
legacy = legacy.replace('assert(old.plan == nil, "缓存恢复：旧生产仍有备料计划，保留日志核对")',
    'assert(old.lastState == "idle" and old.plan == nil, "缓存恢复：旧生产状态不是空闲，保留日志核对")')
anchor = 'local stopped=old.stage=="stopped"'
legacy_controller = controller.replace(anchor, legacy + '\n' + anchor)
lua.globals().files[path] = legacy_controller
install()
upgraded = lua.globals().files[path]
assert 'BEC_V1_CACHE_RESUME_V1' not in upgraded
assert upgraded.count('BEC_V1_CACHE_RESUME_V3') == 1
assert '旧生产状态不是空闲' not in upgraded
assert lua.globals().files[path + '.before-cache-resume-2'] == legacy_controller
assert lua.globals().files['/home/bec_auto.journal'] == 'preserve production journal'
assert lua.globals().files['/home/bec_cache.journal'] == 'preserve cache journal'
lua.execute('assert(load(...))', upgraded)
print('Installed V1 recovery block upgrades in place and preserves journals: PASS')

legacy2 = legacy.replace('BEC_V1_CACHE_RESUME_V1', 'BEC_V1_CACHE_RESUME_V2')
lua.globals().files[path] = controller.replace(anchor, legacy2 + '\n' + anchor)
install()
assert lua.globals().files[path].count('BEC_V1_CACHE_RESUME_V3') == 1
assert 'BEC_V1_CACHE_RESUME_V2' not in lua.globals().files[path]
print('Second recovery patch also upgrades: PASS')

# Execute the patched controller through resume and a new production order.
def literal(file, name):
    tree = ast.parse((ROOT / file).read_text(encoding='utf-8'))
    return next(n.value.value for n in tree.body if isinstance(n, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name for t in n.targets))

base = literal('test_auto_once.py', 'MOCK').replace('/home/bec_auto_once.journal', '/home/bec_auto.journal')
base += literal('test_stream.py', 'EXTRA') + literal('test_stream.py', 'STREAM')
base += literal('work/test_nanites_controller.py', 'setup')
real = LuaRuntime(unpack_returned_tuples=True)
real.execute(base + r'''
s.now=1
s.stock={entangled_chromaticglass=144000,entangled_transcendentmetal=144000}
local ser=require('serialization')
s.files['/home/bec_auto.journal']=ser.serialize({version=1,kind='continuous',stage='cache-working',
 pending=nil,configOwned=false,lastState='paused-immediate',
 expected={['molten.chromaticglass']=144},secured={['molten.chromaticglass']=144},
 requests={{state='done',amount=144}},transfers={{ok=true,amount=144,requested=144}},
 target={entangled_chromaticglass=2880,entangled_transcendentmetal=2880}},false)
s.files['/home/bec_cache.journal']=ser.serialize({version=1,kind='cache',stage='stopped',
 background=true,incomplete=false,configOwned=false,requests={},
 transfers={{ok=true,amount=3456,requested=3456}},target={entangled_chromaticglass=144000}},false)
''')
real.eval('function(...)' + patched + '\nend')('resume')
s = real.globals().s
assert s.completed == s.total, list(s.logs.values())
assert s.requests == 0 and s.moves == 0, list(s.logs.values())
assert s.output == 15 and s.enabled is False
assert any('.before-resume-' in name for name in s.files.keys())
print('Actual patched V1 controller resumes paused order with stale records, completes it without replay: PASS')
