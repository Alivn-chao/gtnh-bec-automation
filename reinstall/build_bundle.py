"""Assemble the verified V1 snapshot plus delivered patches; do not ship patch history."""
import json
import subprocess
import sys
import zlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
OUT=HERE/'files'

ENV=r'''
files={}
local fs={exists=function(p)return files[p]~=nil end,rename=function(a,b)
 assert(files[a] and not files[b],a..' -> '..b);files[b]=files[a];files[a]=nil;return true end}
local c={list=function()return pairs({control='gt_machine'})end,
 methods=function()return {getRequiredCondensate=false,getParallelRecipesInProgress=false,getState=false,setWorkAllowed=false,isWorkAllowed=false}end,
 invoke=function(a,m,x)
  if m=='getOutput'then return a=='266f65b5-20be-4543-8f2f-bfd2d0816611'and 15 or 0 end
  if m=='getInventoryName'then return x==0 and 'minecraft:chest'or 'tile.appliedenergistics2.BlockIOPort'end
  if m=='getInventorySize'then return x==0 and 27 or 12 end
  if m=='getStackInSlot'then return nil end
  if m=='getRequiredCondensate'then return {}end
  if m=='getParallelRecipesInProgress'then return 0 end
  if m=='getState'then return 'idle'end
  return false
 end}
local ser={unserialize=function()return {version=2,kind='cell-io',stage='done'}end}
require=function(n)if n=='filesystem'then return fs elseif n=='serialization'then return ser else return c end end
io={open=function(p,m)
 if m=='r'and files[p]==nil then return nil end
 local t=m=='w'and ''or files[p]
 return {read=function()return t end,write=function(_,s)t=t..s;return true end,flush=function()files[p]=t;return true end,close=function()end}
end}
local function module()return {passiveStages=true,fastStages=true,preview=function()end,needsSwitch=function()return false end}end
loadfile=function()return module end
local actualLoad=load
load=function(s,...)
 local f,e=actualLoad(s,...);assert(f,e)
 if s:find('M.fastStages=true',1,true)then return module end
 return f
end
print=function()end
'''

def build():
    r=LuaRuntime(unpack_returned_tuples=True);r.execute(ENV)
    seeds={'bec_auto.lua':HERE/'seeds/bec_auto.lua','bec_ui.lua':HERE/'seeds/bec_ui.lua',
           'bec_cache_ui.lua':HERE/'seeds/bec_cache_ui.lua',
           'bec_cache.lua':ROOT/'fixes/cache_bulk/bec_cache.lua',
           'bec_nanites.lua':ROOT/'fixes/nanites_io/bec_nanites.lua'}
    for name,path in seeds.items():r.globals().files['/home/'+name]=path.read_text(encoding='utf-8')
    patches=['fixes/process_reset/patch_v1.lua','fixes/cache_resume/patch_v1.lua',
             'fixes/pipeline/patch_v1.lua','fixes/cache_bulk/patch_priority.lua',
             'fixes/cache_bulk/patch_custom.lua','fixes/order_window/patch_v1.lua',
             'fixes/production_overlap/patch_v1.lua','fixes/nanites_stage/patch_v1.lua',
             'fixes/batch_stop/patch_v1.lua','fixes/idle_recovery/patch_v1.lua',
             'fixes/fast_cycle/patch_v1.lua','fixes/nanites_perf/patch_first10.lua',
             'fixes/ui_speed/patch_v1.lua','fixes/ui_speed/patch_pause.lua',
             'fixes/ui_speed/patch_targets.lua','fixes/cpu_wait/patch_v1.lua',
             'fixes/cache_resume/patch_reset_button.lua','fixes/initialize/patch_v1.lua']
    for patch in patches:
        try:r.execute((ROOT/patch).read_text(encoding='utf-8'))
        except Exception as exc:raise RuntimeError(patch)from exc
    bundle={name:r.globals().files['/home/'+name]for name in seeds}
    for name in ['bec_auto.lua','bec_cache.lua']:
        text=bundle[name]
        import re
        text,n=re.subn(r'(local function archiveJournal\(contents,\s*suffix\))',
                      r'\1\nassert(loadfile("/home/bec_history.lua"))().prune(JOURNAL..(suffix or ".stopped-"),2)\n',text)
        assert n==1,(name,n)
        bundle[name]=text
    bundle['bec_nanites.lua']=bundle['bec_nanites.lua'].replace('local function archive()',
       'local function archive()\nassert(loadfile("/home/bec_history.lua"))().prune(PATH..".before-run-",2)')
    for name,path in {'bec_patterns.lua':'bec_patterns.lua','bec_pattern.lua':'bec_pattern.lua',
                      'bec_check.lua':'bec_check.lua','bec_bee_restart.lua':'fixes/nanites_io/restart.lua',
                      'bec_initialize.lua':'fixes/initialize/reset.lua','bec_clean.lua':'tools/clean_history.lua',
                      'bec_history.lua':'reinstall/history.lua','bec_start.lua':'reinstall/start.lua'}.items():
        bundle[name]=(ROOT/path).read_text(encoding='utf-8')
    for name in ['bec_hd.lua','automation_demo.lua']:
        bundle[name]=(HERE/'seeds'/name).read_text(encoding='utf-8')
    bundle['bec_hd.config']='{version=1,node="b04787f9-5423-4b03-8549-c786d4ef38d0",field="237a9cac-118a-4b74-8755-0d0b0ad216c0"}\n'
    bundle['bec_cache.config']='{version=1,target=5000000,overrides={}}\n'
    OUT.mkdir(parents=True,exist_ok=True)
    validator=LuaRuntime(unpack_returned_tuples=True)
    entries=[]
    for name,text in sorted(bundle.items()):
        text=text.replace('\r\n','\n')
        validator.execute('assert(load(...))',text if name.endswith('.lua')else 'return '+text)
        data=text.encode('utf-8');(OUT/name).write_bytes(data)
        entries.append({'name':name,'size':len(data),'checksum':zlib.adler32(data)&0xffffffff})
    (HERE/'manifest.json').write_text(json.dumps(entries,indent=2)+'\n',encoding='utf-8')
    manifest='{\n'+',\n'.join('{name=%s,size=%d,checksum=%d}'%(json.dumps(e['name']),e['size'],e['checksum'])for e in entries)+'\n}'
    installer=(HERE/'installer.lua.inc').read_text(encoding='utf-8').replace('MANIFEST_BODY',manifest)
    validator.execute('assert(load(...))',installer)
    (HERE/'install.lua').write_text(installer,encoding='utf-8')
    print(f'{len(entries)} files, {sum(e["size"]for e in entries)} bytes, all Lua 5.2 syntax verified')
    return bundle

if __name__=='__main__':build()
