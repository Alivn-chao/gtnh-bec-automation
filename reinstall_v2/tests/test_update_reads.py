"""Focused updater transaction tests in RAM; no physical OC machine writes."""
import ast
from pathlib import Path
import subprocess
import unittest
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
TREE=ast.parse((HERE/'test_install.py').read_text(encoding='utf-8'))
SETUP=next(n.value.value for n in TREE.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='SETUP'for t in n.targets))
SCRIPT=(HERE.parent/'update_reads.lua').read_text(encoding='utf-8')
NAMES=['lib/bridge.lua','runtime/controller.lua','lib/engine.lua','runtime/nanites_cell.lua','lib/config.lua','main.lua']
BASE={name:subprocess.check_output(['git','show','549df6e:reinstall_v2/files/'+name],cwd=ROOT).decode('utf-8')for name in NAMES}

def fixture():
 l=LuaRuntime(unpack_returned_tuples=True);l.execute(SETUP)
 for name,raw in BASE.items():l.globals().files['/home/bec_v2/'+name]=raw
 l.execute(r'''
files['/home/bec_v2/config.dat']='config-keep';files['/home/bec_v2/state/node-1/production.journal']='pending-keep'
local cfg={nodes={{address='node',redstone='pause',pauseSide=1}},groups={{generators={'gen'},nanites={enabled=true,mode='cell-io',loadRedstone='load',returnRedstone='return',loadOutputSide=0,returnOutputSide=0,loadSide=3,returnSide=2,transposer='bee'}}}}
function loadfile(p)assert(p=='/home/bec_v2/lib/config.lua');return function()return {load=function()return cfg end,validate=function()return true end,path=function(p)return '/home/bec_v2/'..p end,read=function()return journalBusy and {stage='moving-cell'}or nil end}end end
local c={invoke=function(a,m,...)
 assert(not m:match('^set')and not m:match('^transfer'),'updater must never control hardware')
 if m=='getOutput'then return a=='pause'and(unpaused and 0 or 15)or(ioBusy and 15 or 0)end
 if m=='getState'then return 'paused-immediate'end
 if m=='getInventorySize'then return 12 end
 if m=='getStackInSlot'then return portBusy and {}or nil end
 if m=='isWorkAllowed'or m=='isMachineActive'then return busy or false end
 error(m)
end}
package.preload.component=function()return c end
local fs=require('filesystem');local rename=fs.rename
fs.rename=function(a,b)renameCalls=(renameCalls or 0)+1;if renameFail and renameCalls==renameFail then return false end;return rename(a,b)end
''')
 return l

class UpdateReadsTests(unittest.TestCase):
 def assertPreserved(self,l):
  self.assertEqual(l.globals().files['/home/bec_v2/config.dat'],'config-keep')
  self.assertEqual(l.globals().files['/home/bec_v2/state/node-1/production.journal'],'pending-keep')
 def test_update_and_idempotent_reentry(self):
  l=fixture();l.execute(SCRIPT)
  for name,before in BASE.items():
   path='/home/bec_v2/'+name
   self.assertEqual(l.globals().files[path+'.before-read-opt-1'],before)
   self.assertEqual(l.globals().files[path],(HERE.parent/'files'/name).read_text(encoding='utf-8'))
  writes=l.globals().count;l.execute(SCRIPT);self.assertEqual(l.globals().count,writes);self.assertPreserved(l)
 def test_published_studio_checkpoint_upgrades_with_originals_preserved(self):
  l=fixture()
  names=['lib/bridge.lua','runtime/controller.lua','lib/engine.lua','runtime/nanites_cell.lua','lib/config.lua','lib/storage.lua','main.lua','web.lua','lib/web_session.lua','lib/web_json.lua','lib/web_page.html']
  previous={name:subprocess.check_output(['git','show','334125a:reinstall_v2/files/'+name],cwd=ROOT).decode('utf-8')for name in names}
  for name,text in previous.items():l.globals().files['/home/bec_v2/'+name]=text
  l.execute(SCRIPT)
  for name,text in previous.items():
   self.assertEqual(l.globals().files['/home/bec_v2/'+name+'.before-read-opt-1'],text)
   self.assertEqual(l.globals().files['/home/bec_v2/'+name],(HERE.parent/'files'/name).read_text(encoding='utf-8'))
  self.assertPreserved(l)
 def test_previous_read_preview_is_accepted(self):
  l=fixture()
  bridge=BASE['lib/bridge.lua']
  bridge=bridge.replace(' local env=setmetatable({}, {__index=_G});env._ENV=env', ' local env=setmetatable({}, {__index=_G});env._ENV=env\n -- Explicit logical read only: always scans every member anew, never memoizes\n -- across a yield, component call, or hardware mutation. This is not an OC API\n -- or an atomic server-side snapshot.\n env.BEC_V2_NODE_SNAPSHOT=nodeSnapshot')
  controller=BASE['runtime/controller.lua']
  current=(HERE.parent/'files/runtime/controller.lua').read_text(encoding='utf-8')
  a=current.index('-- V2 bridge can read all four adjacent fields');b=current.index('local remaining, total',a)
  x=controller.index('local state=call(NODE,"getState") local unavailable=');y=controller.index('local remaining, total',x)
  controller=controller[:x]+current[a:b]+controller[y:]
  l.globals().files['/home/bec_v2/lib/bridge.lua']=bridge
  l.globals().files['/home/bec_v2/runtime/controller.lua']=controller
  l.execute(SCRIPT)
  self.assertEqual(l.globals().files['/home/bec_v2/lib/bridge.lua'],(HERE.parent/'files/lib/bridge.lua').read_text(encoding='utf-8'))
  self.assertPreserved(l)
 def test_unknown_local_program_is_preserved(self):
  l=fixture();l.execute("files['/home/bec_v2/lib/bridge.lua']='custom local version'")
  with self.assertRaisesRegex(Exception,'保留本地修改'):l.execute(SCRIPT)
  self.assertEqual(l.globals().count,0);self.assertPreserved(l)
 def test_running_generators_nodes_and_ports_block_update(self):
  for flag in ('busy','unpaused','ioBusy','journalBusy','portBusy'):
   l=fixture();l.execute(flag+'=true')
   with self.assertRaises(Exception):l.execute(SCRIPT)
   self.assertEqual(l.globals().count,0);self.assertPreserved(l)
 def test_rename_failure_restores_all_originals(self):
  l=fixture();l.execute('renameFail=4')
  with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
  for name,before in BASE.items():self.assertEqual(l.globals().files['/home/bec_v2/'+name],before)
  self.assertPreserved(l)
 def test_stage_flush_failure_leaves_originals_intact(self):
  l=fixture();l.execute('failFlush=true')
  with self.assertRaises(Exception):l.execute(SCRIPT)
  for name,before in BASE.items():self.assertEqual(l.globals().files['/home/bec_v2/'+name],before)
  self.assertPreserved(l)

if __name__=='__main__':unittest.main()
