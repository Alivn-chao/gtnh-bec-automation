"""Mock installer failures: never replace old files before validation/backup."""
import subprocess
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
SOURCE=subprocess.check_output(['git','show','a2c8c9a:fixes/nanites_topup/bec_nanites.lua'],cwd=ROOT).decode()
INSTALL=(Path(__file__).parent/'install_sidefix.lua').read_text(encoding='utf-8')
MOCK=r'''
s={files={['/home/bec_nanites.lua']='old module',journal='unchanged'}, output=15, allowed=false, state='paused-immediate'}
package.preload.component=function() return {
 invoke=function(a,m,...) local arg={...}
  if m=='getOutput' then return s.output end
  if m=='isWorkAllowed' then return s.allowed end
  if m=='getState' then return s.state end
  if m=='getInventoryName' then return s.badPort and 'wrong' or 'tile.appliedenergistics2.BlockInterface' end
  if m=='getInventorySize' then return 9 end
  if m=='getItemsInNetwork' then return {} end
  if m=='getStackInSlot' then return nil end
  if m=='getRequiredTier' then return 1 end
  if m=='getAvailableNanites' then return 0 end
  error('unexpected call: '..m)
 end,
 type=function()return 'me_interface'end,
 methods=function()return {getItemsInNetwork=false,getInterfaceConfiguration=false,setInterfaceConfiguration=false}end
} end
package.preload.filesystem=function()return {
 exists=function(p)return s.files[p]~=nil end,
 rename=function(a,b)
  if s.failRename or (s.failInstall and a:find('pending',1,true)) then return nil,'blocked' end
  assert(not s.files[b],'rename cannot overwrite')
  s.files[b]=s.files[a];s.files[a]=nil;return true
 end
}end
package.preload.internet=function()return {request=function()
 local body=s.badDownload and '404' or download;local n=1
 return function()if n>#body then return end;local v=body:sub(n,n+1023);n=n+1024;return v end
end}end
package.preload.sides=function()return {top=1}end
package.preload.serialization=function()return {serialize=function()return '{}'end}end
package.preload.computer=function()return {}end
io.open=function(p,mode)
 if mode=='r' then if not s.files[p] then return nil end;return {read=function()return s.files[p]end,close=function()end}end
 if s.failBackup and p:find('before_sidefix',1,true) then return nil,'disk full' end
 s.files[p]='';return {write=function(_,v)s.files[p]=s.files[p]..v;return true end,
 flush=function()return true end,close=function()end}
end
print=function()end
'''
def run(name,setup='',ok=False):
 lua=LuaRuntime(unpack_returned_tuples=True);lua.globals().download=SOURCE
 lua.execute(MOCK+setup);result=lua.eval('function(src)return pcall(assert(load(src)))end')(INSTALL)
 actual=result[0] if isinstance(result,tuple) else result
 assert actual==ok,(name,result)
 assert lua.eval("s.files.journal=='unchanged'")
 if not ok:assert lua.eval("s.files['/home/bec_nanites.lua']=='old module'")
 print(name+': PASS');return lua
run('running node rejected','s.allowed=true')
run('no pause signal rejected','s.output=0')
run('bad download rejected','s.badDownload=true')
run('wrong real port rejected','s.badPort=true')
run('backup failure preserves old module','s.failBackup=true')
lua=run('rename failure preserves old module','s.failRename=true')
assert lua.eval("s.files['/home/bec_nanites.lua.before_sidefix-1']=='old module'")
run('install rename failure restores old target','s.failInstall=true')
lua=run('successful install backs up exact original',ok=True)
assert lua.eval("s.files['/home/bec_nanites.lua.before_sidefix-1']=='old module'")
assert lua.eval("s.files['/home/bec_nanites.lua']==download")
run('repeat install does not create backup','s.files["/home/bec_nanites.lua"]=download',True)
print('Installer simulation only; no game hardware validation.')
