"""Explicit single-slot replacement preserves completed registrations and old batches."""
import unittest
import test_web_patterns as web

PREP=r'''
H.handle('patterns',{mode='run',revision=H.snapshot().revision},600)
for i=1,11 do H.step()end
assert(H.snapshot().patterns.status=='done')
oldText=s.files[cfg.recipeDirectory..'/result_0_1.dat']
for _,n in pairs(nodes)do n.done=true;n.workAllowed=false end
original.inputs[1].name='new-ordinary';original.inputs[2].amount=288
patterns[1]=require('serialization').unserialize(require('serialization').serialize(original,false))
function same(a,b)
 if type(a)~=type(b)then return false end;if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
second=require('serialization').unserialize(require('serialization').serialize(patterns[2],false))
function replace(slot)
 H.handle('patterns',{mode='replace',slot=slot or 1,revision=H.snapshot().revision},601)
 for i=1,11 do H.step()end
end
'''

class PatternReplaceTests(unittest.TestCase):
 def make(self):
  l=web.WebPatternsTests().setup();l.execute(PREP);return l

 def test_explicit_replacement_archives_old_and_only_touches_selected_slot(self):
  l=self.make();l.execute(r'''
replace()
assert(H.snapshot().patterns.status=='done',H.snapshot().patterns.message)
local path=cfg.recipeDirectory..'/result_0_1.dat';local r=C.read(path)
assert(r.state=='converted'and r.ordinaryInputs[1].name=='new-ordinary'and r.condensates[1].amount==288)
assert(#patterns[1].inputs==1 and same(patterns[2],second))
local found=false;for p,t in pairs(s.files)do if p:find(path..'.backup-',1,true)and t==oldText then found=true end end;assert(found,'old complete registration lost')
local writes=patternWrites;replace();assert(patternWrites==writes,'already converted pattern was replayed')
''')

 def test_normal_run_still_refuses_silent_replacement(self):
  l=self.make();l.execute(r'''
local writes=patternWrites;H.handle('patterns',{mode='run',revision=H.snapshot().revision},602);H.step()
assert(H.snapshot().patterns.status=='failed'and patternWrites==writes)
assert(s.files[cfg.recipeDirectory..'/result_0_1.dat']==oldText)
''')

 def test_preview_shows_changed_registration_without_mutation(self):
  l=self.make();l.execute(r'''
local writes=patternWrites;H.handle('patterns',{mode='preview',revision=H.snapshot().revision},603);for i=1,11 do H.step()end
assert(H.snapshot().patterns.status=='done'and H.snapshot().patterns.rows[1]:find('与旧登记不同',1,true))
assert(patternWrites==writes and s.files[cfg.recipeDirectory..'/result_0_1.dat']==oldText)
''')

 def test_failed_clear_restores_new_pattern_and_old_active_registration(self):
  l=self.make();l.execute(r'''
failClear=true;replace();local p=H.snapshot().patterns
assert(p.status=='failed'and p.message:find('lost reply',1,true))
assert(#patterns[1].inputs==2 and patterns[1].inputs[2].amount==288)
assert(same(C.read(cfg.recipeDirectory..'/result_0_1.dat'),require('serialization').unserialize(oldText)),'old registration not restored')
''')

 def test_rejects_missing_condensates_or_raw_fluids_before_any_change(self):
  for change in ["patterns[1].inputs[2]=nil", "patterns[1].inputs[2].name='water'"]:
   l=self.make();l.execute(change+r'''
local writes=patternWrites;replace();assert(H.snapshot().patterns.status=='failed'and patternWrites==writes)
assert(s.files[cfg.recipeDirectory..'/result_0_1.dat']==oldText)
''')

 def test_unfinished_batch_or_pending_journal_is_not_bypassed(self):
  for path,record in [('state/group-1/cell-feed.journal',"{stage='waiting-nodes'}"),
                      ('state/group-1/cohort.dat',"{stage='working'}"),
                      ('state/group-1/cache.journal',"{stage='stopped',pending={}}"),
                      ('state/node-1/production.journal',"{stage='watching'}")]:
   l=self.make();l.execute(f"C.write(C.path('{path}'),{record})"+r'''
local writes=patternWrites;replace();assert(H.snapshot().patterns.status=='failed'and patternWrites==writes)
assert(s.files[cfg.recipeDirectory..'/result_0_1.dat']==oldText)
''')

 def test_incomplete_old_conversion_cannot_be_overwritten(self):
  l=self.make();l.execute(r'''
local path=cfg.recipeDirectory..'/result_0_1.dat';local r=C.read(path);r.state='needs_manual_restore';C.write(path,r)
local before=s.files[path];local writes=patternWrites;replace()
assert(H.snapshot().patterns.status=='failed'and patternWrites==writes and s.files[path]==before)
''')

 def test_invalid_slot_rejected_before_worker_starts(self):
  for slot in ['nil','0','10','1.5',"'1'"]:
   l=self.make();l.execute(f"assert(not pcall(H.handle,'patterns',{{mode='replace',slot={slot},revision=H.snapshot().revision}},604))")

 def test_nei_290_source_fluids_become_condensate_demand_without_raw_inputs(self):
  l=self.make();l.execute(r'''
original.inputs={{name='new-ordinary',size=256},
 {name='molten.hypogen',amount=576,size=576},
 {name='molten.infinity',amount=18432,size=18432},
 {name='molten.celestialtungsten',amount=294912,size=294912},
 {name='molten.neutronium',amount=294912,size=294912}}
patterns[1]=require('serialization').unserialize(require('serialization').serialize(original,false));replace()
assert(H.snapshot().patterns.status=='done',H.snapshot().patterns.message)
local r=C.read(cfg.recipeDirectory..'/result_0_1.dat');assert(#r.ordinaryInputs==1 and #patterns[1].inputs==1)
local expected={entangled_hypogen=576,entangled_infinity=18432,entangled_celestialtungsten=294912,entangled_neutronium=294912}
for _,v in ipairs(r.condensates)do assert(expected[v.name]==v.amount);expected[v.name]=nil end;assert(not next(expected))
assert(r.original.inputs[2].name=='molten.hypogen','original NEI pattern not retained')
''')

 def test_source_aliases_supported_and_rollback_restores_raw_names(self):
  l=self.make();l.execute(r'''
original.inputs[2].name='fluid.temporalfluid';original.inputs[2].amount=144
patterns[1]=require('serialization').unserialize(require('serialization').serialize(original,false))
failClear=true;replace();assert(H.snapshot().patterns.status=='failed'and patterns[1].inputs[2].name=='fluid.temporalfluid')
assert(same(C.read(cfg.recipeDirectory..'/result_0_1.dat'),require('serialization').unserialize(oldText)))
''')

if __name__=='__main__':unittest.main()
