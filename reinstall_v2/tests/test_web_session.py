"""OC HTML events exercise real binding transactions and the real V2 engine."""
import json
import unittest
from test_read_optimization import fixture

SETUP=r'''
local fs=require('filesystem')
fs.get=function()return {spaceTotal=function()return 4194304 end,spaceUsed=function()return diskUsed or 500000 end}end
fs.lastModified=function()return 0 end
-- RAM fixture's default fs.list is intentionally empty; storage tests install
-- their own exact directory listing.
C.write(C.path('config.dat'),cfg)
B=loadfile('/home/bec_v2/lib/ochd_bindings.lua')()
factoryWeb=loadfile('/home/bec_v2/lib/web_session.lua')()
H=factoryWeb(C,B,{})
'''

class WebSessionTests(unittest.TestCase):
 def setup(self):
  l=fixture();l.execute(SETUP);return l
 def test_draft_partial_input_persists_across_reopen_without_hardware_mutation(self):
  l=self.setup();l.execute(r'''
local expected=s.files[C.path('config.dat')]
local snapshot=H.snapshot()
H.handle('save_field',{revision=snapshot.revision,key='n1.address',value='partial-uuid'},101)
assert(s.files[C.path('config.dat')]==expected)
H=factoryWeb(C,B,{})
assert(H.snapshot().values['n1.address']=='partial-uuid')
assert(releaseCount==0 and nodes.node1.workAllowed==nil)
''')
 def test_revision_conflict_and_unknown_key_are_rejected(self):
  l=self.setup();l.execute(r'''
local r=H.snapshot().revision
H.handle('save_field',{revision=r,key='n1.address',value='partial'},102)
local ok=pcall(H.handle,'save_field',{revision=r,key='n1.redstone',value='x'},103);assert(not ok)
ok=pcall(H.handle,'save_field',{revision=H.snapshot().revision,key='lua',value='os.execute()'},104);assert(not ok)
''')
 def test_start_runs_real_cohort_and_reports_live_stage_elapsed(self):
  l=self.setup();l.execute(r'''
H.handle('start',{revision=H.snapshot().revision},105)
assert(H.running)
local measured=false
for tick=1,200 do
 H.step();local snapshot=H.snapshot()
 if snapshot.phase=='produce'then assert(snapshot.elapsed>=0 and snapshot.flow.gate>=0);measured=true end
 s.now=s.now+.1
 if releaseCount==2 and not H.engine().groupOwner[1]then break end
end
assert(releaseCount==2 and measured,table.concat(H.engine().logs,' / '))
local before=H.snapshot().elapsed;s.now=s.now+20;assert(H.snapshot().elapsed==before)
H.handle('pause',{},106);H.step();assert(not H.running)
''')
 def test_low_disk_prevents_start_and_pauses_running_engine(self):
  l=self.setup();l.execute(r'''
diskUsed=4194304-100000
local ok=pcall(H.handle,'start',{revision=H.snapshot().revision},107);assert(not ok and releaseCount==0)
diskUsed=500000;H.handle('start',{revision=H.snapshot().revision},108);H.step()
diskUsed=4194304-100000;s.now=s.now+11;H.step()
assert(not H.running and H.engine().diskLow)
assert(outputs['rs1-']==15 and nodes.node1.workAllowed==false)
''')
 def test_dirty_draft_cannot_start_old_configuration(self):
  l=self.setup();l.execute(r'''
H.handle('save_field',{revision=H.snapshot().revision,key='n1.address',value='partial'},109)
local ok=pcall(H.handle,'start',{revision=H.snapshot().revision},110);assert(not ok and releaseCount==0)
''')
 def test_phase_timing_ignores_same_stage_journal_saves_inside_gate_confirmation(self):
  l=self.setup();l.execute(r'''
H.handle('start',{revision=H.snapshot().revision},111)
for tick=1,200 do
 H.step();s.now=s.now+.05
 if releaseCount==2 and not H.engine().groupOwner[1]then break end
end
local t=H.engine().tasks[1];assert(t.flow.gate>=.19,'gate confirmation time disappeared')
local seen=false
for _,row in ipairs(t.timeline)do
 if row.phase=='gate'then seen=true
 elseif seen then assert(row.phase~='detect','journal checkpoint reset gate to recipe detection')end
end
assert(seen)
''')
 def test_external_formal_change_cannot_start_cached_engine(self):
  l=self.setup();l.execute(r'''
local revision=H.snapshot().revision
cfg.cacheTarget=999;C.write(C.path('config.dat'),cfg)
local ok=pcall(H.handle,'start',{revision=revision},112)
assert(not ok and not H.running and releaseCount==0)
''')
 def test_recent_batch_display_uses_start_time_not_node_index(self):
  l=self.setup();l.execute(r'''
H.handle('start',{revision=H.snapshot().revision},114)
local e=H.engine();e.groupOwner[1]=nil
e.tasks[1].startedAt=20;e.tasks[1].endedAt=30;e.tasks[1].phase='finish';e.tasks[1].members={1}
e.tasks[2].startedAt=1;e.tasks[2].endedAt=4;e.tasks[2].phase='finish';e.tasks[2].members={2}
local snapshot=H.snapshot();assert(snapshot.elapsed==10 and snapshot.leader==1)
''')
 def test_low_disk_draft_failure_keeps_original_draft_and_config(self):
  l=self.setup();l.execute(r'''
local original=s.files[C.path('config.dat')];diskUsed=4194304-100000
local ok=pcall(H.handle,'save_field',{revision=H.snapshot().revision,key='n1.address',value='partial'},113)
assert(not ok and s.files[C.path('config.dat')]==original and not s.files[C.path('bindings.draft.dat')])
''')
 def test_sixteen_node_snapshot_fits_mod_limits(self):
  l=fixture();l.execute('cfg.nodes={};nodes={};outputs={};configure(16)'+SETUP)
  snapshot=l.eval('H.snapshot()')
  def convert(v):
   if hasattr(v,'items'):return {str(k):convert(x)for k,x in v.items()}
   return v
  d=convert(snapshot)
  def count(v):return 1+sum(count(x)for x in v.values())if isinstance(v,dict)else 1
  self.assertLessEqual(count(d),512)
  self.assertLess(len(json.dumps(d,ensure_ascii=False).encode()),16384)

if __name__=='__main__':unittest.main()
