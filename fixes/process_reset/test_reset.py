"""Execute the installed V1 patch and its reset path with Lua 5.2."""
import ast
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'work/lua_runtime'))
from lupa.lua52 import LuaRuntime

source = (Path(__file__).parent / 'patch_v1.lua').read_text(encoding='utf-8')
controller = Path(sys.argv[1]).read_text(encoding='utf-8') if len(sys.argv) > 1 else (ROOT / 'outputs/nanites_switch/bec_auto.lua').read_text(encoding='utf-8')
ui = Path(sys.argv[2]).read_text(encoding='utf-8') if len(sys.argv) > 2 else 'local mode=...;assert(mode=="run" or mode=="resume" or mode=="monitor" or mode=="restock","用法: run / resume / monitor / restock")'
installer = r'''
files={};writes=0
io={open=function(p,mode)
 if mode=='r' and files[p]==nil then return nil end
 local text=mode=='w' and '' or files[p]
 return {read=function()return text end,write=function(_,v)text=text..v;return true end,
 flush=function()files[p]=text;writes=writes+1;return true end,close=function()end}
end}
local fs={exists=function(p)return files[p]~=nil end,rename=function(a,b)
 if files[a]==nil or files[b]~=nil then return false end
 if failInstall and a:find('next-new',1,true)then return false end
 files[b]=files[a];files[a]=nil;return true end}
local c={invoke=function(a,m)if m=='getOutput'then return 15 else return false end end}
require=function(name)if name=='filesystem'then return fs else return c end end
print=function()end
'''
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(installer)
lua.globals().files['/home/bec_auto.lua'] = controller
lua.globals().files['/home/bec_ui.lua'] = ui
lua.globals().files['/home/bec_auto.journal'] = 'original journal'
old_upload = (ROOT / 'diagnostics/upload.lua').read_text(encoding='utf-8')
# Exercise the local upgrade of the version delivered before recent mode existed.
old_upload = re.sub(r'-- Current journals.*?local function scan', 'local function scan', old_upload, flags=re.S)
old_upload = re.sub(r'  if mode == "recent" then.*?\n  end\n', '', old_upload, flags=re.S)
old_upload = old_upload.replace('local mode = (...) or "recent"', 'local mode = (...) or "full"')
old_upload = old_upload.replace('assert(mode == "recent" or mode == "full"', 'assert(mode == "full"')
lua.globals().files['/home/bec_upload.lua'] = old_upload
run = lua.eval('function()' + source + '\nend')
lua.globals().failInstall = True
try:
    run()
    raise AssertionError('Expected rollback')
except Exception as err:
    assert '已还原' in str(err), err
assert lua.globals().files['/home/bec_auto.lua'] == controller
lua.globals().failInstall = False
run()
patched = lua.globals().files['/home/bec_auto.lua']
assert 'BEC_V1_NEXT_RECIPE_V1' in patched
assert '节点进入空闲但凝聚物未消耗完' not in patched
assert 'verifyGate(filters);pause(0);deadline' not in patched
lua.execute('assert(load(...))', patched)
assert lua.globals().files['/home/bec_auto.journal'] == 'original journal'
assert 'mode=="reset"' in lua.globals().files['/home/bec_ui.lua']
assert 'local recentBackups = {}' in lua.globals().files['/home/bec_upload.lua']
assert 'local mode = (...) or "recent"' in lua.globals().files['/home/bec_upload.lua']
assert lua.globals().files['/home/bec_upload.lua.before-next-1'] == old_upload
writes = lua.globals().writes
run()
assert lua.globals().writes == writes
print('Installed controller/UI syntax, journal preservation, rollback, idempotence: PASS')

block = re.search(r'local reset=\[=\[(.*?)\]=\]', source, re.S).group(1)
setup = r'''
mode='reset';JOURNAL='/home/bec_auto.journal';SUB='sub';RS='rs';GEN='gen';sides={top=1}
production={version=1,kind='continuous',stage='watching',pending=nil,configOwned=false,
 requests={},transfers={{ok=true,amount=144,requested=144}},target={old=999},plan={old=true}}
cache={version=1,kind='cache',stage='stopped',configOwned=false,requests={},transfers={},target={old=144000}}
files={[JOURNAL]='production',['/home/bec_cache.journal']='cache'}
fieldReads=0;sub={};active=false;allowed=false;output=15;renames=0
function call(a,m)if m=='getOutput'then return output elseif m=='isMachineActive'then return active else return allowed end end
function network()return sub end
function field()fieldReads=fieldReads+1;return {old=130176}end
function integer(n)assert(type(n)=='number'and n>=0 and n==math.floor(n));return n end
fs={exists=function(p)return files[p]~=nil end,rename=function(a,b)
 if files[a]==nil or files[b]~=nil then return false end
 files[b]=files[a];files[a]=nil;renames=renames+1;return true end}
io={open=function(p)if not files[p]then return nil end
 return {read=function()return files[p]end,close=function()end}end}
ser={unserialize=function(v)if v=='production'then return production else return cache end end}
print=function()end
'''
cases = [
 ('old target/plan ignored, actual shortage allowed', '', True),
 ('production intent not confirmed', 'production.pending={}', False),
 ('cache intent not confirmed before any archive', 'cache.pending={}', False),
 ('old request still in progress', "production.requests={{state='submitted'}}", False),
 ('cache request still in progress', "cache.requests={{state='submitted'}}", False),
 ('partial old transfer', 'production.transfers[1].requested=288', False),
 ('configuration still owned', 'cache.configOwned=true', False),
 ('generator active', 'active=true', False),
 ('node not paused', 'output=0', False),
 ('unprocessed fluid in subnet', 'sub={raw=144}', False),
 ('unique archives retained', "files[JOURNAL..'.reset-1']='earlier'", True),
]
for label, change, expected in cases:
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(setup + change)
    result = runtime.eval('function()return pcall(function()' + block + 'end)end')()
    ok = result[0] if isinstance(result, tuple) else result
    assert ok == expected, (label, result)
    assert runtime.globals().renames == (2 if expected else 0), label
    assert runtime.globals().mode == ('run' if expected else 'reset'), label
    if expected:
        assert runtime.globals().files['/home/bec_cache.journal.reset-1'] == 'cache'
    print(label + ': PASS')

def literal(file, name):
    tree = ast.parse((ROOT / file).read_text(encoding='utf-8'))
    return next(n.value.value for n in tree.body if isinstance(n, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name for t in n.targets))

base = literal('test_auto_once.py','MOCK').replace('/home/bec_auto_once.journal','/home/bec_auto.journal')
base += literal('test_stream.py','EXTRA') + literal('test_stream.py','STREAM')
base += literal('work/test_nanites_controller.py','setup')
for skipped in (False, True):
    runtime = LuaRuntime(unpack_returned_tuples=True)
    runtime.execute(base + r'''
s.stock={entangled_chromaticglass=144000,entangled_transcendentmetal=144000}
local ser=require('serialization')
s.files['/home/bec_auto.journal']=ser.serialize({version=1,kind='continuous',stage='watching',
 configOwned=false,requests={},transfers={},target={entangled_chromaticglass=999999}},false)
''')
    if skipped:
        runtime.execute(r'''
local c=require('component');local invoke=c.invoke
function c.invoke(a,m,...)
 if m=='getRequiredTier' then return {tier=4} end
 if m=='getState' and s.completed==1 and not s.injectedIdle then
  s.injectedIdle=true;s.fakeIdle=true;return 'idle'
 end
 if m=='getRequiredCondensate' and s.fakeIdle then return nil end
 if m=='getConsumedCondensate' and s.fakeIdle then s.fakeIdle=false;return {} end
 return invoke(a,m,...)
end
''')
    runtime.eval('function(...)' + patched + '\nend')('reset')
    s = runtime.globals().s
    assert s.completed == s.total, list(s.logs.values())
    assert s.output == 15 and s.enabled is False
    assert s.requests == 0 and s.moves == 0
    assert s.files['/home/bec_auto.journal.reset-1'] is not None
    if skipped:
        assert any('旧轮次消耗未确认' in x for x in s.logs.values()), list(s.logs.values())
    print(('Incomplete idle consumption continues' if skipped else 'Reset starts current orders with existing stock') + ': PASS')
