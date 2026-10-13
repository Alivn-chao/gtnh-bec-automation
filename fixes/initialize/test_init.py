import sys
import unittest
import unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
sys.path.insert(0,str(ROOT/'fixes/production_reset'))
import test_reset as previous
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
RESET=(HERE/'reset.lua').read_text(encoding='utf-8')
PATCH=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
literal=previous.literal
DELAY=r'''
local c=require('component');local invoke=c.invoke
s.processing=false;s.captured=0;s.convertDelay=2;s.rawBefore=s.raw
c.invoke=function(a,m,...)
 if s.processing and not s.stallCycle and s.now>=s.finishAt then s.stock=s.stock+s.captured;s.processing=false;s.captured=0 end
 if a=='237a9cac-118a-4b74-8755-0d0b0ad216c0' and m=='getStoredCondensate'then return {entangled_bedrockium=s.stock}end
 if a=='c1ae3f7c-f714-4c27-baf3-392d94a0aa50' then
  if m=='setWorkAllowed'then
   s.enabled=(...)
   if s.enabled and s.raw>0 and not s.converterBlocked then
    s.processing=true;s.captured=s.raw;s.raw=0;s.finishAt=s.now+s.convertDelay;s.conversions=s.conversions+1
   end
   return
  end
  if m=='isMachineActive'then return s.processing end
 end
 return invoke(a,m,...)
end
'''
class InitTests(unittest.TestCase):
 def fixture(self,extra=''):
  r=previous.ResetTests().fixture(DELAY+extra);return r
 def run_init(self,r):return r.eval('function()'+RESET+'\nend')()
 def test_old_reset_reproduces_false_failure_during_delayed_output(self):
  r=self.fixture()
  ok,why=previous.ResetTests().run_worker(r)
  self.assertFalse(ok);self.assertIn('数量不守恒',why)
  self.assertEqual(r.globals().s.raw,0);self.assertTrue(r.globals().s.processing)
 def test_init_rebases_stale_checkpoint_and_drains_real_inflight_output(self):
  r=self.fixture();g=r.globals()
  previous.ResetTests().run_worker(r)
  old=g.s.files['/home/bec_auto.journal'];checkpoint=g.s.files['/home/bec_auto.journal.failed-reset']
  g.s.files['/home/bec_cache.journal']='old unreadable cache requests'
  g.s.files['/home/bec_cache.reset']='obsolete expected quantity'
  g.s.files['/home/bec_cache.config']='individual targets preserve'
  ok,why=self.run_init(r);self.assertTrue(ok,why)
  self.assertEqual(g.s.files['/home/bec_auto.journal.before-initialize-1'],old)
  self.assertEqual(g.s.files['/home/bec_auto.journal.failed-reset.before-initialize-1'],checkpoint)
  for name in ['bec_cache.journal','bec_cache.reset','bec_auto.journal.failed-reset']:
   self.assertIsNone(g.s.files['/home/'+name])
  self.assertEqual(g.s.files['/home/bec_cache.config'],'individual targets preserve')
  self.assertEqual(g.s.stock,5000288);self.assertEqual(g.s.raw,0);self.assertFalse(g.s.enabled)
  self.assertEqual(g.s.cpuReads,0);self.assertEqual(g.s.requests,0)
  r.execute("local j=require('serialization').unserialize(s.files['/home/bec_auto.journal']);assert(j.stage=='watching' and next(j.requests)==nil and next(j.transfers)==nil and j.pipeline==nil and j.pending==nil)")
 def test_new_conversion_accepts_temporary_input_output_gap(self):
  r=self.fixture();ok,why=self.run_init(r);self.assertTrue(ok,why)
  self.assertEqual(r.globals().s.stock,5000288);self.assertEqual(r.globals().s.conversions,1)
 def test_actual_stock_overrides_wrong_old_expected_and_pending(self):
  r=self.fixture("production.pending={amount=918862848};production.pipeline.delivered={};s.files['/home/bec_auto.journal']=require('serialization').serialize(production,false);s.raw=576")
  ok,why=self.run_init(r);self.assertTrue(ok,why)
  self.assertEqual(r.globals().s.stock,5000576);self.assertEqual(r.globals().s.moves,0)
 def test_repeat_initialize_creates_new_audit_and_no_more_conversion(self):
  r=self.fixture();self.assertTrue(self.run_init(r)[0]);self.assertTrue(self.run_init(r)[0])
  self.assertEqual(r.globals().s.conversions,1);self.assertIsNotNone(r.globals().s.files['/home/bec_initialize-2.dat'])
 def test_quit_while_conversion_active_preserves_material_and_retry_reads_actual(self):
  r=self.fixture(r'''
local req=require;local e=req('event');local pull=e.pull
e.pull=function(n,...)local result={pull(n,...)};if s.processing and not s.quitSent then s.quitSent=true;return 'key_down','keyboard',113 end;return table.unpack(result)end
require=function(n)if n=='event'then return e end;return req(n)end
''')
  original=r.globals().s.files['/home/bec_auto.journal']
  self.assertFalse(self.run_init(r)[0]);self.assertFalse(r.globals().s.enabled)
  self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],original)
  ok,why=self.run_init(r);self.assertTrue(ok,why);self.assertEqual(r.globals().s.stock,5000288)
 def test_real_converter_stall_reports_raw_and_stops_without_fresh_journal(self):
  r=self.fixture('s.converterBlocked=true');before=r.globals().s.files['/home/bec_auto.journal']
  ok,why=self.run_init(r);self.assertFalse(ok);self.assertIn('molten.bedrockium 288 mB',why)
  self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],before);self.assertFalse(r.globals().s.enabled)
 def test_fresh_journal_swap_failure_preserves_original(self):
  r=self.fixture()
  r.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a:find('.initialize-new-',1,true)then return false end;return rename(a,b)end;local prev=require;require=function(n)if n=='filesystem'then return fs end;return prev(n)end")
  before=r.globals().s.files['/home/bec_auto.journal'];self.assertFalse(self.run_init(r)[0])
  self.assertEqual(r.globals().s.files['/home/bec_auto.journal'],before)
 def test_initialize_then_actual_controller_feeds_only_current_deficit(self):
  r=LuaRuntime(unpack_returned_tuples=True)
  r.execute(previous.BASE.replace('/home/bec_auto_once.journal','/home/bec_auto.journal')+r'''
s.total=1;s.simultaneous=true;s.now=1
s.stock={entangled_chromaticglass=144,entangled_transcendentmetal=144}
s.mainStock={['molten.chromaticglass']=144,['molten.transcendentmetal']=144}
s.files['/home/bec_auto.journal']='old broken bookkeeping'
s.files['/home/bec_cache.journal']='old blocked cache'
''')
  ok,why=self.run_init(r);self.assertTrue(ok,why)
  r.eval('function(...)'+(ROOT/'bec_auto.lua').read_text(encoding='utf-8')+'\nend')('resume')
  s=r.globals().s
  self.assertEqual(s.completed,1);self.assertEqual(s.moves,2);self.assertEqual(s.requests,0)
  self.assertEqual(s.output,15);self.assertFalse(s.enabled)
  self.assertEqual(s.files['/home/bec_auto.journal.before-initialize-1'],'old broken bookkeeping')

class InstallerTests(unittest.TestCase):
 def fixture(self,old_reset=True):
  r=previous.InstallerTests().fixture()
  if old_reset:r.execute(previous.PATCH)
  r.globals().files['/home/bec_cache.lua']=(ROOT/'fixes/cache_bulk/bec_cache_custom.lua').read_text(encoding='utf-8')
  return r
 def test_actual_latest_ui_controller_cache_install_backup_and_idempotence(self):
  for old_reset in [True,False]:
   r=self.fixture(old_reset);g=r.globals();before={p:g.files[p]for p in ['/home/bec_auto.lua','/home/bec_ui.lua','/home/bec_cache.lua']}
   r.execute(PATCH)
   for p,t in before.items():
    self.assertEqual(g.files[p+'.before-initialize-ui-1'],t);r.execute('assert(load(...))',g.files[p])
   self.assertIn('BEC_V1_UI_INITIALIZE_V1:',g.files['/home/bec_ui.lua'])
   self.assertNotIn('local function productionResetWorker',g.files['/home/bec_ui.lua'])
   self.assertIn('BEC_V1_CPU_WAIT_V1:',g.files['/home/bec_auto.lua'])
   self.assertEqual(g.files['/home/bec_auto.journal'],'failed recipe preserve')
   self.assertEqual(g.files['/home/bec_nanites.lua'],'first10 and IO1/7 module must remain untouched')
   writes=g.writes;r.execute(PATCH);self.assertEqual(g.writes,writes)
 def test_ui_failure_rolls_back_controller_cache_and_ui(self):
  r=self.fixture();g=r.globals();before={p:g.files[p]for p in ['/home/bec_auto.lua','/home/bec_ui.lua','/home/bec_cache.lua']}
  r.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a=='/home/bec_ui.lua.initialize-ui-new-1'then return false end;return rename(a,b)end")
  with self.assertRaisesRegex(Exception,'已还原'):r.execute(PATCH)
  for p,t in before.items():self.assertEqual(g.files[p],t)
 def test_missing_cpu_wait_patch_is_installed_as_part_of_update(self):
  sys.path.insert(0,str(ROOT/'fixes/cpu_wait'));import test_wait as cpu
  r=cpu.InstallerTests().fixture()
  r.execute((ROOT/'fixes/cache_resume/patch_reset_button.lua').read_text(encoding='utf-8'))
  self.assertNotIn('BEC_V1_CPU_WAIT_V1:',r.globals().files['/home/bec_auto.lua'])
  r.execute(PATCH)
  self.assertIn('BEC_V1_CPU_WAIT_V1:',r.globals().files['/home/bec_auto.lua'])
  self.assertIn('BEC_V1_UI_INITIALIZE_V1:',r.globals().files['/home/bec_ui.lua'])
  self.assertEqual(r.globals().files['/home/bec_auto.journal'],'failed recipe preserve')
 def test_real_ui_mouse_z_initializes_then_resumes_once(self):
  installer=self.fixture();installer.execute(PATCH);ui=installer.globals().files['/home/bec_ui.lua']
  r=LuaRuntime(unpack_returned_tuples=True)
  r.globals().pyWidth=lambda t:sum(2 if unicodedata.east_asian_width(x)in('W','F')else 1 for x in t)
  r.globals().pySub=lambda t,a,b:t[int(a)-1:int(b)if b>=0 else len(t)+int(b)+1]
  r.execute(previous.BASE.replace('/home/bec_auto_once.journal','/home/bec_auto.journal')+literal('test_ui.py','GPU')+literal('fixes/ui_speed/test_ui_speed.py','extra')+previous.MOCK+DELAY+r'''
s.attempts=0
s.controller=function(mode)
 s.attempts=s.attempts+1
 if s.attempts==1 then print('程序停止: 转换期间数量不守恒');return end
 assert(mode=='resume');s.resumed=true
 local old=require('serialization').unserialize(s.files['/home/bec_auto.journal'])
 assert(old.stage=='watching' and old.pipeline==nil and #old.requests==0 and old.initialized)
 local _,_,ch=require('event').pull(.1);assert(ch==113)
end
local e=require('event');local oldPull=e.pull;s.clicked=false
e.pull=function(n,...)
 if (n or 0)>0 and s.attempts==1 and not s.clicked then s.clicked=true;return 'touch','screen',10,28,0 end
 if (n or 0)>0 and s.resumed then return 'key_down','keyboard',113 end
 return oldPull(n,...)
end
''')
  r.eval('function(...)'+ui+'\nend')('resume');s=r.globals().s
  self.assertTrue(s.resumed);self.assertEqual(s.attempts,2);self.assertEqual(s.stock,5000288)
  self.assertEqual(s.requests,0);self.assertFalse(s.enabled)
  self.assertTrue(any('初始化 / 重新投料' in t for t in s.draws.values()))

class CPUWaitTests(unittest.TestCase):
 def test_all_busy_longer_than_timeout_then_free_cpu_completes_without_fault(self):
  mock=literal('fixes/pipeline/test_pipeline.py','mock').replace('assert(not released)\n','\n')
  extra=literal('fixes/production_overlap/test_overlap.py','extra').replace("assert(now<100,'loop stalled')","assert(now<8000,'loop stalled')")
  r=LuaRuntime(unpack_returned_tuples=True)
  r.execute(mock+extra+r'''
stock={a=288,b=288}
function serviceNaniteStage()return true end
local original=call;local oldTick=tick
function call(a,m,...)
 if m=='getCpus' and now<7000 then return {{busy=true,storage=65536},{busy=true,storage=65536}}end
 return original(a,m,...)
end
function tick(dt)
 if completed>=2 and not released and now<7000 then dt=100 end
 oldTick(dt)
 if now<7000 then assert(#submissions==0,'requested with no free CPU');assert(completed<=2)end
end
''')
  installer=InstallerTests().fixture();installer.execute(PATCH)
  auto=installer.globals().files['/home/bec_auto.lua']
  a=auto.index('-- BEC_V1_PRODUCTION_OVERLAP_V3:');z=auto.index('\nend',auto.index(' return expected',a))+4
  # Installed overlap function, including its actual CPU wait and extended deadline.
  body=auto[a:z]
  r.eval('function()'+body+'\nreturn prepareStreaming({a=1440,b=1440})end')()
  g=r.globals();self.assertEqual(g.completed,10);self.assertEqual(len(g.submissions),2)
  self.assertGreaterEqual(g.submissions[1].time,7000)
  self.assertLess(g.submissions[1].amount,1440)
 def sequential(self,cache=False,setup=''):
  installer=InstallerTests().fixture();installer.execute(PATCH)
  source=installer.globals().files['/home/bec_cache.lua'if cache else '/home/bec_auto.lua']
  a=source.index('-- BEC_V1_SEQUENTIAL_CPU_WAIT_V1:');z=source.index("assert(computer.uptime()<deadline,'持续收料超时，保留子网已搬入原液')",a)
  body=source[a:z]+"assert(computer.uptime()<deadline,'持续收料超时，保留子网已搬入原液')"
  r=LuaRuntime(unpack_returned_tuples=True)
  r.execute(r'''
now=0;computer={uptime=function()return now end};MAIN='main';raw='raw';need=144;previous={};remaining=144
record={requests={},stage='stream-planned'};deadline=1800;attempts=0;priority=false;submissions=0;messages={};available=0
function save(stage)record.stage=stage end
function print(t)messages[#messages+1]=t end
function tanks()return 0 end
function bufferedInlet()return 0 end
function network()return {raw=available}end
function productionWaiting()return priority end
function handoff()for _,j in ipairs(record.requests)do assert(j.state=='done' or(j.state=='rejected' and j.preSubmissionFailed))end;handed=true;return true end
function call(a,m,...)
 if m=='getCpus'then if unknown then error('unavailable')end;return {{busy=now<7000,storage=65536}}end
 if m=='getCraftables'then return {{getStack=function()return {name='raw',amount=0,size=0,hasTag=false,isCraftable=true}end,request=function(n)
  submissions=submissions+1;assert(record.requests[#record.requests].state=='pending')
  return {isComputing=function()return false end,hasFailed=function()return reject,'missing resources?'end,isCanceled=function()return false end,isDone=function()return false end}
 end}}end
 error(m)
end
'''+setup)
  step=r.eval('function()while true do '+body+'\nbreak end end')
  return r,step
 def test_fallback_and_cache_busy_wait_remains_live_then_submits_once(self):
  for cache in [False,True]:
   r,step=self.sequential(cache)
   for now in [0,1801,6999]:
    r.globals().now=now;step();self.assertEqual(r.globals().submissions,0)
    self.assertGreater(r.globals().deadline,now)
    self.assertIn('等待合成 CPU 空闲',r.globals().record.supplyWait.cpuWaitSummary)
   r.globals().now=7000;step();step();self.assertEqual(r.globals().submissions,1)
 def test_unreadable_cpu_waits_instead_of_throwing(self):
  r,step=self.sequential(setup='unknown=true;now=20000');step()
  self.assertEqual(r.globals().submissions,0);self.assertIn('状态恢复可读',r.globals().record.supplyWait.cpuWaitSummary)
 def test_rejected_submission_waits_for_manual_supply_and_can_yield_cache(self):
  for cache in [False,True]:
   r,step=self.sequential(cache,setup='reject=true;now=7000')
   step();step();r.globals().now=20000;step()
   self.assertEqual(r.globals().submissions,1)
   self.assertIn('手动申请 144 mB',r.globals().record.supplyWait.cpuWaitSummary)
   if cache:r.globals().priority=True;step();self.assertTrue(r.globals().handed)
   else:
    r.execute("available=144;previous.raw=144;remaining=0");step()
    self.assertEqual(r.globals().submissions,1);self.assertIsNone(r.globals().record.supplyWait)

if __name__=='__main__':unittest.main()
