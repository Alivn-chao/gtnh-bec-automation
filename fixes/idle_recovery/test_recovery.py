import sys
import unittest
from pathlib import Path
from lupa.lua52 import LuaRuntime
HERE=Path(__file__).parent
ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'fixes/batch_stop'))
import test_batch as batchtests
BODY=(HERE/'recover.lua.inc').read_text(encoding='utf-8')
MOCK=r'''
mode='resume';contents='original journal bytes';JOURNAL='/home/bec_auto.journal'
NODE='node';RS='rs';GEN='gen';SUB='sub';sides={top=1};stopping=false;writes={};requests=0;moves=0
state='idle';req=nil;parallel=0
consumed={entangled_chromaticglass=61488,entangled_infinity=36864,entangled_transcendentmetal=18432}
stock={entangled_chromaticglass=29520,entangled_infinity=4742208,entangled_transcendentmetal=4678416}
sub={};mapping={entangled_chromaticglass='glass',entangled_infinity='infinity',entangled_transcendentmetal='metal'}
old={stage='pipeline-converting',configOwned=false,requests={},transfers={},required={entangled_chromaticglass=73728,entangled_infinity=36864,entangled_transcendentmetal=18432},target={},plan={},pipeline={overlap=true,base={entangled_chromaticglass=238464,entangled_infinity=4852800,entangled_transcendentmetal=4733712},initial={},delivered={},startConsumed={},recipe={entangled_chromaticglass=1152,entangled_infinity=576,entangled_transcendentmetal=288}}}
for name,raw in pairs(mapping)do old.plan[#old.plan+1]={name=name,raw=raw}end
function integer(n)assert(type(n)=='number' and n>=0 and n%1==0);return n end
function same(a,b)for k,v in pairs(a)do if b[k]~=v then return false end end;for k,v in pairs(b)do if a[k]~=v then return false end end;return true end
function call(a,m,...)
 if m=='getOutput'then return 15 end
 if m=='isWorkAllowed' or m=='isMachineActive'then return false end
 if m=='getState'then return state end
 if m=='getRequiredCondensate'then return req end
 if m=='getConsumedCondensate'then return consumed end
 if m=='getParallelRecipesInProgress'then return parallel end
 error('unexpected call: '..m)
end
function resolveRawNames()end
function field()return stock end
function network()return sub end
function generator(v)assert(v==false,'unexpected conversion')end
function tick()error('unexpected wait')end
fs={exists=function(p)return writes[p]~=nil end}
ser={serialize=function(v,pretty)assert(pretty==false);if v.kind then audit=v end;return 'audit bytes' end}
function writeVerified(path,s)assert(s=='audit bytes');writes[path]=s end
print=function()end
'''
class RecoveryTests(unittest.TestCase):
 def run_body(self,setup='',body=BODY):
  r=LuaRuntime(unpack_returned_tuples=True);r.execute(MOCK+setup);r.execute(body);return r
 def test_exact_screenshot_accounts_128_completed_and_partial_64_separately(self):
  r=self.run_body();g=r.globals()
  self.assertEqual(g.audit.completedBeforeRetained,128)
  self.assertEqual(g.audit.retainedConsumed.entangled_chromaticglass,61488)
  self.assertEqual(g.audit.missingAgainstRecorded.entangled_chromaticglass,12240)
  self.assertEqual(g.audit.missingAgainstRecorded.entangled_infinity,0)
  self.assertEqual(g.audit.missingAgainstRecorded.entangled_transcendentmetal,0)
  self.assertEqual(g.audit.sourceJournal,'original journal bytes')
  self.assertEqual(g.old.stage,'watching');self.assertIsNone(g.old.plan);self.assertIsNone(g.old.pipeline)
  self.assertEqual(g.stock.entangled_chromaticglass,29520)
  self.assertEqual(g.requests,0);self.assertEqual(g.moves,0)
 def test_old_published_recovery_reproduces_screenshot_error(self):
  old=(ROOT/'fixes/production_overlap/recover.lua.inc').read_text(encoding='utf-8')
  with self.assertRaisesRegex(Exception,'下一配方已有消耗'):self.run_body(body=old)
 def test_normal_idle_complete_batch_retained_consumption(self):
  r=self.run_body('consumed.entangled_chromaticglass=73728;stock.entangled_chromaticglass=17280')
  self.assertEqual(r.globals().audit.completedBeforeRetained,128)
  self.assertEqual(r.globals().audit.missingAgainstRecorded.entangled_chromaticglass,0)
 def test_active_same_recipe_uses_existing_rule(self):
  r=self.run_body("state='paused-immediate';req=old.required;parallel=64")
  self.assertEqual(r.globals().old.stage,'watching');self.assertIsNone(r.globals().audit)
 def test_active_other_recipe_and_unknown_loss_rejected_without_archive(self):
  for setup,reason in [("state='paused-immediate';req={different=144};parallel=1",'下一配方已有消耗'),
   ('stock.entangled_chromaticglass=stock.entangled_chromaticglass-1','不守恒'),
   ('consumed.entangled_chromaticglass=73729','超过已记录需求'),
   ('consumed.foreign=1','旧配方以外'),
   ("old.pending={raw='glass',amount=1}",'未确认搬液'),
   ("old.requests={{state='submitted'}}",'尚未确认完成')]:
   r=LuaRuntime(unpack_returned_tuples=True);r.execute(MOCK+setup)
   with self.assertRaisesRegex(Exception,reason):r.execute(BODY)
   self.assertEqual(len(r.globals().writes),0);self.assertEqual(r.globals().old.stage,'pipeline-converting')
 def test_unique_audit_paths_preserve_prior_audit(self):
  r=self.run_body("writes[JOURNAL..'.idle-recovery-1']='prior'")
  self.assertEqual(r.globals().writes['/home/bec_auto.journal.idle-recovery-1'],'prior')
  self.assertEqual(r.globals().writes['/home/bec_auto.journal.idle-recovery-2'],'audit bytes')

class InstallationTests(unittest.TestCase):
 def runtime(self):
  r=batchtests.InstallerTests().setup_runtime()
  r.execute((ROOT/'fixes/batch_stop/patch_v1.lua').read_text(encoding='utf-8'))
  return r
 def test_all_existing_patches_preserved_and_backup_idempotence(self):
  r=self.runtime();old=r.globals().files['/home/bec_auto.lua'];p=(HERE/'patch_v1.lua').read_text(encoding='utf-8')
  r.execute(p);new=r.globals().files['/home/bec_auto.lua'];r.execute('assert(load(...))',new)
  for marker in ['BEC_V1_NANITES_STAGE_V2','BEC_V1_BATCH_STOP_V1:','BEC_V1_PRODUCTION_OVERLAP_V3:']:
   self.assertIn(marker,new)
  self.assertEqual(new.count('BEC_V1_IDLE_RECOVERY_V1:'),1)
  self.assertEqual(r.globals().files['/home/bec_auto.lua.before-idle-recovery-1'],old)
  self.assertEqual(r.globals().files['/home/bec_auto.journal'],'failed recipe preserve')
  n=r.globals().writes;r.execute(p);self.assertEqual(r.globals().writes,n)
 def test_replace_failure_restores_controller_and_journal(self):
  r=self.runtime();old=r.globals().files['/home/bec_auto.lua']
  r.execute("local f=require('filesystem');local rename=f.rename;f.rename=function(a,b)if a:find('idle-recovery-new',1,true)then return false end;return rename(a,b)end")
  with self.assertRaisesRegex(Exception,'已还原'):r.execute((HERE/'patch_v1.lua').read_text(encoding='utf-8'))
  self.assertEqual(r.globals().files['/home/bec_auto.lua'],old)
if __name__=='__main__':unittest.main()
