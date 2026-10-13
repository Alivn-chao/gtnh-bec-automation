import ast
import runpy
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
BODY=(HERE/'jobs.lua.inc').read_text(encoding='utf-8')
PATCH=(HERE/'patch_v1.lua').read_text(encoding='utf-8')

def literal(path,name):
 tree=ast.parse((ROOT/path).read_text(encoding='utf-8'))
 return next(n.value.value for n in ast.walk(tree) if isinstance(n,ast.Assign)
  and any(isinstance(t,ast.Name) and t.id==name for t in n.targets))

MOCK=r'''
now=0;computer={uptime=function()return now end};MAIN='main';stopping=false
record={requests={},pipeline={},stage='pipeline-converting'}
items={{raw='raw.a',amount=1440,initial=0,delivered=0,attempts=0,batch=144},
 {raw='raw.b',amount=1440,initial=0,delivered=0,attempts=0,batch=144}}
main={};cpus={{storage=1024,busy=false,name='small'},{storage=65536,busy=true,name='large'}}
attempts={};results={};stages={};messages={};moves=0;signals=0
function network()return main end
function save(stage)record.stage=stage;stages[#stages+1]=stage end
print=function(s)messages[#messages+1]=s end
function call(address,method,filter)
 if method=='getCpus' then return cpus end
 if method=='getCraftables' then
  local raw=filter.name
  return {{getStack=function()return {name=raw,isCraftable=true,amount=0,size=0,hasTag=false}end,
   request=function(n)
    local intent;for _,job in ipairs(record.requests)do if job.raw==raw and job.state=='pending'then intent=job end end
    assert(intent and intent.amount==n)
    attempts[raw]=(attempts[raw] or 0)+1
    local outcome=(results[raw] or {})[attempts[raw]] or 'working'
    if outcome=='nil' then return nil,'uncertain' end
    if outcome=='throw' then error('request exception')end
    return {hasFailed=function()return outcome=='reject',failureReason or 'request failed (missing resources?)'end,
     isComputing=function()return outcome=='computing' end,
     isCanceled=function()return outcome=='cancel','cancel'end,
     isDone=function()return outcome=='done' end}
   end}}
 end
 moves=moves+1;error('unexpected hardware call: '..method)
end
'''

class SchedulerTests(unittest.TestCase):
 def setup(self,extra=''):
  r=LuaRuntime(unpack_returned_tuples=True);r.execute(MOCK+extra)
  self.step=r.eval('function()'+BODY+'\nreturn jobsAndRequests end')()
  return r
 def test_rejected_job_requests_manual_supply_without_stopping_other_orders(self):
  r=self.setup("results['raw.a']={'reject','working'}")
  self.step();self.step();g=r.globals()
  self.assertEqual(g.attempts['raw.a'],1);self.assertEqual(g.attempts['raw.b'],1)
  self.assertEqual(g.record.requests[1].state,'rejected')
  self.assertIn('请在 ME 手动申请 1440 mB',g.record.pipeline.cpuWait['raw.a'].reason)
  r.execute('now=1;cpus[2].busy=false');self.step()
  self.assertEqual(g.attempts['raw.a'],1);self.assertEqual(len(g.record.requests),2)
  self.assertEqual(g.record.requests[1].state,'rejected')
  self.assertTrue(g.record.requests[1].manualSupply)
  self.assertEqual(g.moves,0);self.assertEqual(g.signals,0)
 def test_all_busy_waits_and_new_free_cpu_triggers_submission(self):
  r=self.setup('cpus[1].busy=true');self.step()
  self.assertEqual(len(r.globals().record.requests),0)
  self.assertIn('等待合成 CPU 空闲',r.globals().record.pipeline.cpuWait['raw.a'].reason)
  r.execute('now=4000;cpus[2].busy=false');self.step()
  self.assertEqual(len(r.globals().record.requests),2)
 def test_explicit_storage_failure_when_all_idle_displays_capacity(self):
  r=self.setup("cpus[2].busy=false;results['raw.a']={'reject'};failureReason='insufficient storage'")
  self.step();self.step()
  self.assertIn('CPU 容量不足',r.globals().record.pipeline.cpuWait['raw.a'].reason)
 def test_ambiguous_failure_does_not_falsely_assert_capacity(self):
  r=self.setup("cpus[2].busy=false;results['raw.a']={'reject'}")
  self.step();self.step()
  self.assertIn('容量或原料待核对',r.globals().record.pipeline.cpuWait['raw.a'].reason)
 def test_no_cpu_or_zero_storage_displays_capacity_without_request(self):
  for extra in ['cpus={}','cpus={{busy=false,storage=0}}']:
   r=self.setup(extra);self.step()
   self.assertEqual(len(r.globals().record.requests),0)
   self.assertIn('CPU 容量不足',r.globals().record.pipeline.cpuWait['raw.a'].reason)
 def test_missing_storage_on_older_api_still_allows_automatic_selection(self):
  r=self.setup('cpus={{busy=false}}');self.step()
  self.assertEqual(len(r.globals().record.requests),2)
 def test_unreadable_busy_state_waits_without_request(self):
  r=self.setup('cpus={{storage=1024}}');self.step()
  self.assertEqual(len(r.globals().record.requests),0)
  self.assertIn('状态恢复可读',r.globals().record.pipeline.cpuWait['raw.a'].reason)
 def test_manual_job_never_resubmitted_when_cpu_state_changes_or_time_passes(self):
  r=self.setup("results['raw.a']={'reject','reject','working'}")
  self.step();self.step();r.execute('now=29');self.step()
  self.assertEqual(r.globals().attempts['raw.a'],1)
  r.execute('now=30');self.step();self.step();r.execute('now=60');self.step()
  self.assertEqual(r.globals().attempts['raw.a'],1)
  self.assertEqual(len(r.globals().record.requests),2)
 def test_computing_and_long_running_orders_never_replay_or_timeout(self):
  for result in ['computing','working']:
   r=self.setup("results['raw.a']={'"+result+"'}")
   self.step();r.execute('now=90000');self.assertTrue(self.step())
   self.assertEqual(r.globals().attempts['raw.a'],1)
 def test_nil_exception_and_real_cancellation_keep_uncertain_request(self):
  for result in ['nil','throw','cancel']:
   r=self.setup("results['raw.a']={'"+result+"'}")
   with self.assertRaises(Exception):
    self.step();self.step()
   self.assertEqual(r.globals().attempts['raw.a'],1)
   self.assertIn(r.globals().record.requests[1].state,['pending','submitted'])
   self.assertIsNone(r.globals().record.requests[1].preSubmissionFailed)
 def test_has_failed_without_computing_callback_is_not_proof(self):
  r=self.setup("results['raw.a']={'cancel'}")
  self.step();r.execute("items[1].status.hasFailed=function()return true,'missing'end;items[1].status.isComputing=nil")
  with self.assertRaises(Exception):self.step()
  self.assertEqual(r.globals().record.requests[1].state,'submitted')
 def test_external_supply_after_rejection_avoids_new_order(self):
  r=self.setup("results['raw.a']={'reject'}");self.step();self.step()
  r.execute("main['raw.a']=1440;now=31");self.step()
  self.assertEqual(r.globals().attempts['raw.a'],1)
 def test_partial_manual_supply_updates_remaining_without_new_request(self):
  r=self.setup("results['raw.a']={'reject'}");self.step();self.step()
  r.execute("items[1].delivered=144;main['raw.a']=288;now=10000")
  self.step();g=r.globals()
  self.assertEqual(g.record.pipeline.cpuWait['raw.a'].amount,1008)
  self.assertEqual(g.attempts['raw.a'],1)
 def test_done_with_no_harvest_is_still_rejected(self):
  r=self.setup("results['raw.a']={'done'}");self.step();self.step();r.execute('now=4')
  with self.assertRaisesRegex(Exception,'没有收获'):self.step()

class IntegrationTests(unittest.TestCase):
 def test_production_conversion_continue_while_other_request_waits(self):
  mock=literal('fixes/pipeline/test_pipeline.py','mock')
  mock=mock.replace("assert(not released,'assembler released too early')","assert(not released,'old guard after release')")
  mock=mock.replace('assert(not released)\n','\n')
  extra=literal('fixes/production_overlap/test_overlap.py','extra')
  r=LuaRuntime(unpack_returned_tuples=True);r.execute(mock+extra+r'''
local previous=call;rejectCount=0;firstRejected=nil
function call(a,m,...)
 local returns={previous(a,m,...)};local result=returns[1]
 if m=='getCpus' then
  for _,cpu in pairs(result)do cpu.storage=1024 end
  result[#result+1]={busy=now<3,storage=65536}
 elseif m=='getCraftables' then
  local raw=({...})[1].name;local request=result[1].request
  result[1].request=function(n)
   if raw=='raw.b' and not firstRejected then
    firstRejected=now;rejectCount=rejectCount+1;manualAt=3;manualAmount=n
    return {isComputing=function()return false end,hasFailed=function()return true,'missing resources?'end}
   end
   return request(n)
  end
 end
 return table.unpack(returns)
end
local previousTick=tick
function tick(dt)
 previousTick(dt)
 if manualAt and now>=manualAt then main['raw.b']=(main['raw.b'] or 0)+manualAmount;manualAt=nil end
end
''')
  prepare=(ROOT/'fixes/production_overlap/prepare.lua.inc').read_text(encoding='utf-8')
  a=prepare.index(' local function jobsAndRequests()');z=prepare.index(' while not stopping do',a)
  prepare=prepare[:a]+BODY+'\n'+prepare[z:]
  prepare=prepare.replace('(item.job and item.job.state~="done")',
   '(item.job and item.job.state~="done" and not(item.job.state=="rejected" and item.job.preSubmissionFailed==true))')
  prepare=prepare.replace('productionGuard();jobsAndRequests();if stopping then break end',
   'productionGuard();local cpuWaiting=jobsAndRequests();if cpuWaiting then deadline=math.max(deadline,now+1800)end;if stopping then break end')
  r.eval('function()'+prepare+'\nreturn prepareStreaming({a=1440,b=1440})end')()
  g=r.globals();self.assertEqual(g.completed,10);self.assertEqual(g.rejectCount,1)
  self.assertLess(g.firstConversion,3);self.assertTrue(g.ranWhileConverting)
  self.assertEqual(len(g.record.requests),2)

class InstallerTests(unittest.TestCase):
 def fixture(self):
  sys.path.insert(0,str(ROOT/'fixes/fast_cycle'))
  import test_fast
  r=test_fast.fixture();r.execute(test_fast.PATCH)
  ui=(ROOT/'outputs/flicker_fix/bec_ui_paste.lua').read_text(encoding='utf-8')
  r.globals().files['/home/bec_ui.lua']=ui
  for p in ['fixes/ui_speed/patch_v1.lua','fixes/ui_speed/patch_pause.lua']:
   source=(ROOT/p).read_text(encoding='utf-8')
   r.execute(source)
  r.globals().files['/home/bec_nanites.lua']='first10 and IO1/7 module must remain untouched'
  return r
 def test_latest_controller_and_ui_backup_idempotence_no_journal_or_bee_changes(self):
  r=self.fixture();g=r.globals();old=g.files['/home/bec_auto.lua'];ui=g.files['/home/bec_ui.lua']
  r.execute(PATCH)
  for p in ['/home/bec_auto.lua','/home/bec_ui.lua']:r.execute('assert(load(...))',g.files[p])
  self.assertEqual(g.files['/home/bec_auto.lua.before-cpu-wait-1'],old)
  self.assertEqual(g.files['/home/bec_ui.lua.before-cpu-wait-1'],ui)
  for marker in ['BEC_V1_IDLE_RECOVERY_V1:','BEC_V1_BATCH_STOP_V1:','BEC_V1_NANITES_STAGE_V2:','BEC_V1_FAST_CYCLE_V1:']:
   self.assertIn(marker,g.files['/home/bec_auto.lua'])
  self.assertEqual(g.files['/home/bec_nanites.lua'],'first10 and IO1/7 module must remain untouched')
  self.assertEqual(g.files['/home/bec_auto.journal'],'failed recipe preserve')
  writes=g.writes;r.execute(PATCH);self.assertEqual(g.writes,writes)
 def test_second_file_failure_rolls_back_both_files(self):
  r=self.fixture();g=r.globals();old=g.files['/home/bec_auto.lua'];ui=g.files['/home/bec_ui.lua']
  r.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a=='/home/bec_ui.lua.cpu-wait-new-1' then return false end;return rename(a,b)end")
  with self.assertRaisesRegex(Exception,'已还原'):r.execute(PATCH)
  self.assertEqual(g.files['/home/bec_auto.lua'],old);self.assertEqual(g.files['/home/bec_ui.lua'],ui)
 def test_old_submitted_guard_preserved_and_only_proven_rejection_recoverable(self):
  r=self.fixture();r.execute(PATCH);source=r.globals().files['/home/bec_auto.lua']
  self.assertIn('job.state=="rejected" and job.preSubmissionFailed==true',source)
  self.assertIn('原液申请尚未确认完成，禁止重复下单',source)
 def test_resume_requires_full_manual_supply_and_keeps_legacy_submitted_guard(self):
  r=self.fixture();r.execute(PATCH);source=r.globals().files['/home/bec_auto.lua']
  a=source.index('for _,job in ipairs(old.requests or {})do')
  z=source.index('for _,move in ipairs(old.transfers or {})do',a)
  guard=source[a:z]
  r.execute("old={requests={{state='rejected',preSubmissionFailed=true,manualSupply=true,raw='raw.a',amount=1000,securedBefore=0}},pipeline={delivered={['raw.a']=400}}};available=500;function network()return {['raw.a']=available}end;function integer(n)return n end")
  with self.assertRaisesRegex(Exception,'手动补料尚未收齐'):r.execute(guard)
  r.execute('available=600');r.execute(guard)
  r.execute("old.requests[1].state='submitted'")
  with self.assertRaisesRegex(Exception,'尚未确认完成'):r.execute(guard)

class UITests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  old=sys.argv;sys.argv=['test_ui_speed.py',str(ROOT/'outputs/flicker_fix/bec_ui_paste.lua')]
  try:cls.ui=runpy.run_path(str(ROOT/'fixes/ui_speed/test_ui_speed.py'))
  finally:sys.argv=old
  r=InstallerTests().fixture();r.execute(PATCH)
  cls.ui['run'].__globals__['patched']=r.globals().files['/home/bec_ui.lua']
 def test_manual_fluid_amount_visible_in_white_on_red_without_fault(self):
  r=self.ui['run'](self.ui['flip']+r'''
local ser=require('serialization')
local j=ser.unserialize(s.files['/home/bec_auto.journal'])
j.pipeline={cpuWaitSummary='请在 ME 手动申请',cpuWait={['molten.bedrockium']={manual=true,amount=918862848,failure='missing resources?'}}}
s.files['/home/bec_auto.journal']=ser.serialize(j,false)
local gpu=require('component').gpu;local set=gpu.set
local bg,fg=gpu.setBackground,gpu.setForeground
gpu.setBackground=function(v,...)s.testBg=v;return bg(v,...)end
gpu.setForeground=function(v,...)s.testFg=v;return fg(v,...)end
gpu.set=function(x,y,t,...)
 if t:find('手动申请',1,true) then
  assert(t:find('molten.bedrockium',1,true) and t:find('918862848 mB',1,true),'manual order truncated')
  assert(s.testBg==0xb00020 and s.testFg==0xffffff);s.manualVisible=true
 end
 return set(x,y,t,...)
end
''')
  self.assertTrue(r.globals().s.manualVisible);self.assertTrue(r.globals().s.controllerStarted)
  self.assertFalse(any('已暂停 / 待处理' in row for row in r.globals().s.draws.values()))

if __name__=='__main__':unittest.main()
