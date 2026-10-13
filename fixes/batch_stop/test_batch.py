import ast
import unittest
from pathlib import Path
from lupa.lua52 import LuaRuntime
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).parent
def literal(path,name):
 tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
 return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
body=(HERE/'batch.lua.inc').read_text(encoding='utf-8').replace('CONTROL_BODY',(HERE/'control.lua.inc').read_text(encoding='utf-8'))
MOCK=r'''
NODE='node';RS='rs';sides={top=1};record={stage='watching'}
state='paused-immediate';work=true;output=15;completed=0;started=1;writes={};saved=0
local methods={getRequiredCondensate=false,getParallelRecipesInProgress=false,getState=false,setWorkAllowed=false,isWorkAllowed=false}
c={list=function()return pairs({control='gt_machine',node='bec_io_node'})end,
 methods=function(a)return a=='control' and methods or {getState=false}end}
function same(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end;for k,v in pairs(b)do if a[k]~=v then return false end end;return true end
function call(a,m,v)
 if m=='getState'then return state end
 if m=='getParallelRecipesInProgress'then return state=='idle' and 0 or 64 end
 if m=='getRequiredCondensate'then return state~='idle' and {glass=12240} or nil end
 if m=='getOutput'then return output end
 if m=='isWorkAllowed'then return work end
 if m=='setWorkAllowed'then work=v;writes[#writes+1]=v;return end
 error(m)
end
function save()saved=saved+1 end
function pause(n)output=n end
function prepareStreaming(target)pause(0);finish();return {}end
function finish()
 assert(output==0);completed=completed+1;state='idle'
 if work then started=started+1;state='crafting' end
end
function accept()
 assert(work and output==15);started=started+1;state='paused-immediate'
end
'''
class RuntimeTests(unittest.TestCase):
 def runtime(self,extra=''):
  r=LuaRuntime(unpack_returned_tuples=True);r.execute(MOCK+extra)
  r.execute(body+'\nTEST={between=batchBetween,work=batchWork}')
  return r
 def test_fast_batch_finishes_but_cannot_chain(self):
  r=self.runtime();r.execute('prepareStreaming({glass=12240})')
  g=r.globals();self.assertEqual(g.completed,1);self.assertEqual(g.started,1);self.assertEqual(g.state,'idle');self.assertFalse(g.work)
 def test_next_batch_accepts_only_while_paused_then_latches_off(self):
  r=self.runtime();r.execute('prepareStreaming({});pause(15);TEST.between();accept();TEST.between();prepareStreaming({})')
  g=r.globals();self.assertEqual(g.completed,2);self.assertEqual(g.started,2);self.assertFalse(g.work);self.assertEqual(g.state,'idle')
 def test_active_low_nanite_requirement_does_not_pause_or_abort(self):
  r=self.runtime();r.execute("state='nanite-tier-too-low';TEST.work(false);pause(0)")
  self.assertEqual(r.globals().output,0);self.assertEqual(r.globals().state,'nanite-tier-too-low')
 def test_no_control_or_multiple_controls_refuses_before_write(self):
  for extra in ["c.methods=function()return {}end", "c.list=function()return pairs({control=1,control2=1})end;local m=c.methods('control');c.methods=function()return m end"]:
   r=self.runtime(extra)
   with self.assertRaisesRegex(Exception,'唯一可启停'):r.execute('prepareStreaming({})')
   self.assertEqual(len(r.globals().writes),0)
 def test_wrong_node_and_failed_readback_refuse(self):
  r=self.runtime("local orig=call;function call(a,m,...)if a=='control' and m=='getParallelRecipesInProgress'then return 1 end;return orig(a,m,...)end")
  with self.assertRaisesRegex(Exception,'并行不一致'):r.execute('prepareStreaming({})')
  self.assertEqual(len(r.globals().writes),0)
  r=self.runtime("local orig=call;function call(a,m,...)if m=='setWorkAllowed'then return end;return orig(a,m,...)end")
  with self.assertRaisesRegex(Exception,'回读不符'):r.execute('prepareStreaming({})')
  self.assertEqual(r.globals().record.batchStop.phase,'pending')
 def test_refuses_accepting_next_recipe_without_pause(self):
  r=self.runtime();r.execute("state='idle';output=0")
  with self.assertRaisesRegex(Exception,'立即暂停'):r.globals().TEST.between()
  self.assertEqual(len(r.globals().writes),0)

class InstallerTests(unittest.TestCase):
 def setup_runtime(self):
  r=LuaRuntime(unpack_returned_tuples=True);r.execute(literal('fixes/process_reset/test_reset.py','installer'))
  text=(ROOT/'bec_auto.lua').read_text(encoding='utf-8').replace('end\nlocal function serve()','end local function serve()').replace('local old=ser.unserialize(contents)\n','local old=ser.unserialize(contents) local streaming=false\n')
  r.globals().files['/home/bec_auto.lua']='-- /home/bec_nanites.lua\n'+text
  r.globals().files['/home/bec_auto.journal']='failed recipe preserve'
  for path in ['fixes/pipeline/patch_v1.lua','fixes/production_overlap/patch_v1.lua','fixes/nanites_stage/patch_v1.lua']:
   r.execute('loadfile=function()return function()return {passiveStages=true,needsSwitch=function()return false end}end end')
   r.execute((ROOT/path).read_text(encoding='utf-8'))
  r.execute("local c=require('component');c.list=function()return pairs({control='gt_machine'})end;c.methods=function()return {getRequiredCondensate=false,getParallelRecipesInProgress=false,getState=false,setWorkAllowed=false,isWorkAllowed=false}end")
  return r
 def test_real_installed_controller_syntax_backup_idempotence(self):
  r=self.setup_runtime();original=r.globals().files['/home/bec_auto.lua'];p=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
  r.execute(p);modified=r.globals().files['/home/bec_auto.lua'];r.execute('assert(load(...))',modified)
  self.assertIn('BEC_V1_NANITES_STAGE_V2',modified);self.assertEqual(modified.count('batchBetween()\n'),2)
  self.assertEqual(r.globals().files['/home/bec_auto.lua.before-batch-stop-1'],original)
  self.assertEqual(r.globals().files['/home/bec_auto.journal'],'failed recipe preserve')
  n=r.globals().writes;r.execute(p);self.assertEqual(r.globals().writes,n)
 def test_failed_replace_restores_original(self):
  r=self.setup_runtime();original=r.globals().files['/home/bec_auto.lua']
  r.execute("local f=require('filesystem');local rename=f.rename;f.rename=function(a,b)if a:find('batch-stop-new',1,true)then return false end;return rename(a,b)end")
  with self.assertRaisesRegex(Exception,'已还原'):r.execute((HERE/'patch_v1.lua').read_text(encoding='utf-8'))
  self.assertEqual(r.globals().files['/home/bec_auto.lua'],original)
if __name__=='__main__':unittest.main()
