import ast
import sys
import unittest
import unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
BODY=(HERE/'reset.lua').read_text(encoding='utf-8')
PATCH=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
def literal(path,name):
 tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
 return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign)
  and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))
BASE=literal('test_auto_once.py','MOCK')+literal('test_stream.py','EXTRA')+literal('test_stream.py','STREAM')
MOCK=r'''
local ser=require('serialization')
s.enabled=false;s.raw=288;s.stock=5000000;s.conversions=0;s.cpuReads=0;s.nodeState='paused-immediate'
production={version=1,kind='continuous',stage='pipeline-converting',pending=nil,configOwned=false,
 requests={{raw='molten.bedrockium',amount=918862848,state='submitted',securedBefore=0}},
 transfers={{raw='molten.bedrockium',ok=true,amount=288,requested=288}},
 target={entangled_bedrockium=918862848},plan={{raw='molten.bedrockium',name='entangled_bedrockium',amount=918862848,batch=144}},
 pipeline={base={entangled_bedrockium=5000000},initial={},delivered={['molten.bedrockium']=288}}}
s.files['/home/bec_auto.journal']=ser.serialize(production,false)
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 if m=='getCpus' then s.cpuReads=s.cpuReads+1;error('CPU tasks unavailable')end
 if m=='getFluidInterfaceConfiguration'then return nil end
 if m=='getState'then return s.nodeState end
 if m=='getRequiredCondensate'then return {entangled_bedrockium=18874368}end
 if m=='getConsumedCondensate'then return {entangled_bedrockium=12345}end
 if a=='237a9cac-118a-4b74-8755-0d0b0ad216c0' then
  if m=='isWorkAllowed'then return true end
  if m=='getStoredCondensate'then
   if s.enabled and not s.stalled then s.stock=s.stock+s.raw;s.raw=0 end
   return {entangled_bedrockium=s.stock}
  end
 end
 if a=='86311657-33d1-41b5-a0d9-0aee7b5c2c50' and m=='getFluidsInNetwork' then
  return s.raw>0 and {{name='molten.bedrockium',amount=s.raw}}or {}
 end
 if a=='c1ae3f7c-f714-4c27-baf3-392d94a0aa50' then
  if m=='getName'then return 'multi.bec.generator'end
  if m=='isWorkAllowed'then return s.enabled end
  if m=='isMachineActive'then return false end
  if m=='setWorkAllowed'then s.enabled=(...);if s.enabled then s.conversions=s.conversions+1 end;return end
 end
 return invoke(a,m,...)
end
'''
class ResetTests(unittest.TestCase):
 def fixture(self,extra=''):
  r=LuaRuntime(unpack_returned_tuples=True);r.execute(BASE+MOCK+extra);return r
 def run_worker(self,r,arg='confirmed-not-submitted'):
  return r.eval('function(...)'+BODY+'\nend')(arg)
 def test_explicit_failed_order_preserved_without_fake_completion_and_inventory_retained(self):
  r=self.fixture();g=r.globals();before=g.s.files['/home/bec_auto.journal']
  ok,why=self.run_worker(r);self.assertTrue(ok,why)
  old=r.eval("require('serialization').unserialize(s.files['/home/bec_auto.journal'])")
  self.assertEqual(old.stage,'watching');self.assertIsNone(old.pipeline);self.assertIsNone(old.plan)
  self.assertEqual(len(old.requests),0)
  self.assertEqual(old.retainedRequests[1].request.state,'submitted')
  self.assertEqual(old.retainedRequests[1].request.amount,918862848)
  self.assertEqual(old.retainedRequests[1].disposition,'user-confirmed-not-submitted')
  self.assertEqual(g.s.files[old.failedRequestReset.backup],before)
  self.assertEqual(g.s.raw,0);self.assertEqual(g.s.stock,5000288)
  self.assertFalse(g.s.enabled);self.assertEqual(g.s.cpuReads,0)
  writes=g.s.writes;self.assertTrue(self.run_worker(r)[0]);self.assertEqual(g.s.writes,writes)
 def test_no_confirmation_does_not_change_journal_or_hardware(self):
  r=self.fixture();before=r.globals().s.files['/home/bec_auto.journal']
  self.assertFalse(self.run_worker(r,'')[0]);self.assertEqual(r.globals().s.conversions,0)
  self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],before)
 def test_later_independent_failure_archives_completed_checkpoint(self):
  r=self.fixture('s.raw=0');self.assertTrue(self.run_worker(r)[0])
  previous=r.globals().s.files['/home/bec_auto.journal.failed-reset']
  r.execute("production.requests[1].amount=288;production.plan[1].amount=288;s.files['/home/bec_auto.journal']=require('serialization').serialize(production,false)")
  self.assertTrue(self.run_worker(r)[0])
  self.assertEqual(r.globals().s.files['/home/bec_auto.journal.failed-reset.before-reset-1'],previous)
  self.assertIsNotNone(r.globals().s.files['/home/bec_auto.journal.before-failed-reset-2'])
 def test_another_journal_cannot_take_over_unfinished_checkpoint(self):
  r=self.fixture('s.stalled=true');self.assertFalse(self.run_worker(r)[0])
  r.execute("production.requests[1].amount=288;s.files['/home/bec_auto.journal']=require('serialization').serialize(production,false);s.stalled=false")
  before=r.globals().s.files['/home/bec_auto.journal']
  self.assertFalse(self.run_worker(r)[0]);self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],before)
 def test_crash_after_journal_commit_finishes_checkpoint_without_reconverting(self):
  r=self.fixture();self.assertTrue(self.run_worker(r)[0]);converted=r.globals().s.conversions
  r.execute("local ser=require('serialization');local p='/home/bec_auto.journal.failed-reset';local j=ser.unserialize(s.files[p]);j.stage='converting';s.files[p]=ser.serialize(j,false)")
  self.assertTrue(self.run_worker(r)[0]);self.assertEqual(r.globals().s.conversions,converted)
  self.assertEqual(r.eval("require('serialization').unserialize(s.files['/home/bec_auto.journal.failed-reset']).stage"),'done')
 def test_uncertain_move_unknown_request_or_active_node_cannot_be_reset(self):
  for extra in ['production.pending={}',"production.requests[1].state='pending'",'production.transfers[1].amount=144',"s.nodeState='crafting'",'production.naniteStage={}']:
   r=self.fixture(extra+";s.files['/home/bec_auto.journal']=require('serialization').serialize(production,false)")
   before=r.globals().s.files['/home/bec_auto.journal'];self.assertFalse(self.run_worker(r)[0])
   self.assertEqual(r.globals().s.conversions,0);self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],before)
 def test_no_raw_never_starts_converter_and_settled_jobs_are_retained(self):
  r=self.fixture("s.raw=0;production.requests[2]={raw='molten.bedrockium',amount=144,state='done'};s.files['/home/bec_auto.journal']=require('serialization').serialize(production,false)")
  self.assertTrue(self.run_worker(r)[0]);self.assertEqual(r.globals().s.conversions,0)
  old=r.eval("require('serialization').unserialize(s.files['/home/bec_auto.journal'])")
  self.assertEqual(len(old.requests),1);self.assertEqual(old.requests[1].state,'done')
 def test_interrupted_conversion_keeps_original_and_can_continue(self):
  r=self.fixture('s.stalled=true');before=r.globals().s.files['/home/bec_auto.journal']
  self.assertFalse(self.run_worker(r)[0]);self.assertFalse(r.globals().s.enabled)
  self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],before)
  r.execute('s.stalled=false');self.assertTrue(self.run_worker(r)[0])
  self.assertEqual(r.globals().s.stock,5000288)
 def test_partial_conversion_resume_uses_only_remaining(self):
  r=self.fixture('s.stalled=true');self.assertFalse(self.run_worker(r)[0])
  r.execute('s.stalled=false;s.stock=s.stock+144;s.raw=144')
  self.assertTrue(self.run_worker(r)[0]);self.assertEqual(r.globals().s.stock,5000288)
 def test_partial_unknown_transfer_or_quantity_change_refused(self):
  r=self.fixture('s.raw=289');before=r.globals().s.files['/home/bec_auto.journal']
  self.assertFalse(self.run_worker(r)[0]);self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],before)
 def test_replace_failure_restores_exact_original(self):
  r=self.fixture();before=r.globals().s.files['/home/bec_auto.journal']
  r.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a:find('before-failed-reset',1,true)and a:sub(-4)=='.new'then return false end;return rename(a,b)end;local previous=require;require=function(n)if n=='filesystem'then return fs end;return previous(n)end")
  self.assertFalse(self.run_worker(r)[0]);self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],before)
 def test_recovery_of_rewritten_journal_passes_existing_watching_rules(self):
  r=self.fixture('s.raw=0');self.assertTrue(self.run_worker(r)[0])
  r.execute("local old=require('serialization').unserialize(s.files['/home/bec_auto.journal']);assert(old.stage=='watching' and old.plan==nil and type(old.target)=='table');for _,job in ipairs(old.requests)do assert(job.state=='done')end;for _,move in ipairs(old.transfers)do assert(move.ok==true and move.amount>0)end")
 def test_actual_controller_resume_recalculates_from_stock_without_replaying_old_order(self):
  r=LuaRuntime(unpack_returned_tuples=True)
  r.execute(BASE.replace('/home/bec_auto_once.journal','/home/bec_auto.journal')+r'''
s.total=1;s.simultaneous=true;s.now=1;s.mainStock={}
s.stock={entangled_chromaticglass=288,entangled_transcendentmetal=288}
local old={version=1,kind='continuous',stage='pipeline-converting',configOwned=false,
 target={entangled_chromaticglass=918862848},plan={{raw='molten.chromaticglass',name='entangled_chromaticglass',batch=144,amount=918862848}},
 requests={{raw='molten.chromaticglass',amount=918862848,state='submitted'}},transfers={},
 pipeline={initial={},delivered={}}}
s.files['/home/bec_auto.journal']=require('serialization').serialize(old,false)
''')
  self.assertTrue(self.run_worker(r)[0])
  r.eval('function(...)'+(ROOT/'bec_auto.lua').read_text(encoding='utf-8')+'\nend')('resume')
  s=r.globals().s
  self.assertEqual(s.completed,1);self.assertEqual(s.moves,0);self.assertEqual(s.requests,0)
  self.assertEqual(s.output,15);self.assertFalse(s.enabled)
  self.assertTrue(any('已停止常驻服务' in row for row in s.logs.values()))

class InstallerTests(unittest.TestCase):
 def fixture(self):
  sys.path.insert(0,str(ROOT/'fixes/cpu_wait'));import test_wait as cpu
  r=cpu.InstallerTests().fixture();r.execute(cpu.PATCH)
  r.execute((ROOT/'fixes/cache_resume/patch_reset_button.lua').read_text(encoding='utf-8'))
  return r
 def test_install_preserves_latest_ui_and_controller_with_backup_and_idempotence(self):
  r=self.fixture();g=r.globals();old=g.files['/home/bec_ui.lua'];auto=g.files['/home/bec_auto.lua']
  r.execute(PATCH);r.execute('assert(load(...))',g.files['/home/bec_ui.lua'])
  for marker in ['BEC_V1_CPU_WAIT_UI_V1:','BEC_V1_UI_CACHE_RESET_V3','BEC_V1_UI_PRODUCTION_RESET_V1:']:
   self.assertIn(marker,g.files['/home/bec_ui.lua'])
  self.assertEqual(g.files['/home/bec_ui.lua.before-production-reset-1'],old)
  self.assertEqual(g.files['/home/bec_auto.lua'],auto)
  writes=g.writes;r.execute(PATCH);self.assertEqual(g.writes,writes)
 def test_install_failure_restores_ui(self):
  r=self.fixture();old=r.globals().files['/home/bec_ui.lua']
  r.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a:find('production-reset-new',1,true)then return false end;return rename(a,b)end")
  with self.assertRaisesRegex(Exception,'已还原'):r.execute(PATCH)
  self.assertEqual(r.globals().files['/home/bec_ui.lua'],old)
 def test_real_ui_mouse_reset_and_resume_once(self):
  installer=self.fixture();installer.execute(PATCH)
  ui=installer.globals().files['/home/bec_ui.lua']
  r=LuaRuntime(unpack_returned_tuples=True)
  r.globals().pyWidth=lambda t:sum(2 if unicodedata.east_asian_width(x)in('W','F')else 1 for x in t)
  r.globals().pySub=lambda t,a,b:t[int(a)-1:int(b)if b>=0 else len(t)+int(b)+1]
  r.execute(BASE.replace('/home/bec_auto_once.journal','/home/bec_auto.journal')+literal('test_ui.py','GPU')+literal('fixes/ui_speed/test_ui_speed.py','extra')+MOCK+r'''
s.attempts=0
s.controller=function(mode)
 s.attempts=s.attempts+1
 if s.attempts==1 then print('程序停止: 原液申请尚未确认完成，禁止重复下单');return end
 assert(mode=='resume');s.resumed=true
 local old=require('serialization').unserialize(s.files['/home/bec_auto.journal'])
 assert(old.stage=='watching' and old.pipeline==nil and #old.requests==0)
 assert(old.retainedRequests[1].request.state=='submitted')
 local _,_,ch=require('event').pull(.1);assert(ch==113)
end
local e=require('event');local oldPull=e.pull;s.clicked=false
e.pull=function(n,...)
 if (n or 0)>0 and s.attempts==1 and not s.clicked then s.clicked=true;return 'touch','screen',10,28,0 end
 if (n or 0)>0 and s.resumed then return 'key_down','keyboard',113 end
 return oldPull(n,...)
end
''')
  r.eval('function(...)'+ui+'\nend')('resume')
  s=r.globals().s
  self.assertTrue(s.resumed);self.assertEqual(s.attempts,2)
  self.assertEqual(s.stock,5000288);self.assertEqual(s.raw,0);self.assertFalse(s.enabled)
  self.assertEqual(s.requests,0)
  self.assertTrue(any('确认未下单' in text for text in s.draws.values()))

if __name__=='__main__':unittest.main()
