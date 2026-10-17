"""Web events exercise actual workshop conversion, rollback and stop boundaries."""
import json,unittest
from test_read_optimization import fixture
from test_web_session import SETUP
EXTRA=r'''
cfg.workshopInterface='workshop';C.write(C.path('config.dat'),cfg);H=factoryWeb(C,B,{})
local c=require('component');local invoke=c.invoke;local methods=c.methods
patternReads,patternWrites=0,0
local ser=require('serialization')
local function clone(x)return ser.unserialize(ser.serialize(x,false))end
original={isCraftable=false,inputs={{name='ordinary',size=1},{name='entangled_test',amount=144}},outputs={{name='result',size=1,damage=0,label='Result'}}}
patterns={[1]=clone(original),[2]=clone(original)}
c.methods=function(a)if a=='workshop'then return {getInterfacePattern=false,clearInterfacePatternInput=false,setInterfacePatternInput=false}else return methods(a)end end
c.invoke=function(a,m,...)
 if a~='workshop'then return invoke(a,m,...)end
 local slot,index,item=...;assert(m=='getInterfacePattern'or m=='clearInterfacePatternInput'or m=='setInterfacePatternInput','only workshop methods allowed')
 if m=='getInterfacePattern'then patternReads=patternReads+1;return patterns[slot]and clone(patterns[slot])end
 patternWrites=patternWrites+1
 if m=='clearInterfacePatternInput'then table.remove(patterns[slot].inputs,index);if failClear then error('lost reply')end;return true end
 if m=='setInterfacePatternInput'then patterns[slot].inputs[index]=clone(original.inputs[index]);return true end
end
'''
class WebPatternsTests(unittest.TestCase):
 def setup(self):
  l=fixture();l.execute(SETUP+EXTRA);return l
 def test_preview_is_read_only_and_results_reach_snapshot(self):
  l=self.setup();l.execute(r'''
H.handle('patterns',{mode='preview',revision=H.snapshot().revision},200)
for i=1,11 do H.step()end
local p=H.snapshot().patterns;assert(p.status=='done'and p.slot==9 and #p.rows==9)
assert(p.rows[1]:find('entangled_test',1,true)and p.rows[9]:find('空槽',1,true))
assert(patternWrites==0 and #patterns[1].inputs==2)
for path in pairs(s.files)do assert(not path:find('/recipes/',1,true),'preview wrote recipe record')end
''')
 def test_run_converts_and_registers_real_recipe_without_repeating(self):
  l=self.setup();l.execute(r'''
H.handle('patterns',{mode='run',revision=H.snapshot().revision},201)
for i=1,11 do H.step()end
assert(H.snapshot().patterns.status=='done'and #patterns[1].inputs==1 and #patterns[2].inputs==1)
local r=C.read(cfg.recipeDirectory..'/result_0_1.dat');assert(r.state=='converted'and r.condensates[1].amount==144)
local writes=patternWrites;H.handle('patterns',{mode='run',revision=H.snapshot().revision},202);for i=1,11 do H.step()end
assert(H.snapshot().patterns.status=='done'and patternWrites==writes)
''')
 def test_stop_and_close_stop_between_whole_slot_transactions(self):
  for close in [False,True]:
   l=self.setup();l.execute("H.handle('patterns',{mode='run',revision=H.snapshot().revision},203);H.step()")
   l.execute("H.close()"if close else "H.handle('patterns',{mode='stop'},204);H.step()")
   l.execute("assert(H.snapshot().patterns.status=='stopped');assert(#patterns[1].inputs==1 and #patterns[2].inputs==2)")
 def test_failure_restores_pattern_and_is_visible_as_failure(self):
  l=self.setup();l.execute(r'''
failClear=true;H.handle('patterns',{mode='run',revision=H.snapshot().revision},205);H.step()
local p=H.snapshot().patterns;assert(p.status=='failed'and p.message:find('lost reply',1,true))
assert(#patterns[1].inputs==2 and #patterns[2].inputs==2)
local r=C.read(cfg.recipeDirectory..'/result_0_1.dat');assert(r.state=='restored')
''')
 def test_edit_start_and_duplicate_run_are_blocked_while_worker_exists(self):
  l=self.setup();l.execute(r'''
H.handle('patterns',{mode='preview',revision=H.snapshot().revision},206)
assert(not pcall(H.handle,'start',{revision=H.snapshot().revision},207))
assert(not pcall(H.handle,'save_field',{revision=H.snapshot().revision,key='n1.address',value='changed'},208))
assert(not pcall(H.handle,'patterns',{mode='run',revision=H.snapshot().revision},209))
H.handle('patterns',{mode='stop'},210);H.step();assert(patternWrites==0)
''')
 def test_external_configuration_change_and_disk_low_stop_before_next_slot(self):
  for change in ["s.files[C.path('config.dat')]='changed'","diskUsed=4194304-100000"]:
   l=self.setup();l.execute("H.handle('patterns',{mode='run',revision=H.snapshot().revision},211);H.step();"+change+";H.step()")
   l.execute("assert(H.snapshot().patterns.status=='failed'and #patterns[2].inputs==2)")
 def test_running_production_and_unapplied_draft_cannot_process(self):
  l=self.setup();l.execute(r'''
H.running=true;assert(not pcall(H.handle,'patterns',{mode='run',revision=H.snapshot().revision},212));H.running=false
H.handle('save_field',{revision=H.snapshot().revision,key='workshopInterface',value='other'},213)
assert(not pcall(H.handle,'patterns',{mode='run',revision=H.snapshot().revision},214));assert(patternWrites==0)
''')
 def test_maximum_result_rows_with_sixteen_nodes_fit_snapshot_limits(self):
  l=fixture();l.execute('cfg.nodes={};nodes={};outputs={};configure(16)'+SETUP+EXTRA)
  l.execute("H.handle('patterns',{mode='preview',revision=H.snapshot().revision},215);for i=1,11 do H.step()end;local p=H.snapshot().patterns;for i=1,9 do p.rows[i]=string.rep('x',380)end;for i=1,6 do p.logs[i]=string.rep('x',220)end")
  def convert(v):
   if hasattr(v,'items'):return {str(k):convert(x)for k,x in v.items()}
   return v
  snapshot=l.eval('H.snapshot()')
  # Largest cache page can coexist with full pattern logs and a scanner page.
  snapshot.cache.rows=l.table_from([l.table_from(dict(name='entangled_'+str(i),label='Fluid '+str(i),stock=1000,target=144000,override=1000))for i in range(8)])
  snapshot.scan=l.table_from(dict(role='node',token=1,status='done',page=0,total=512,checked=2048,message='',removed=0,baseline=True,rows=l.table_from([l.table_from(dict(address='a'*36,kind='bec_io_node',name='node',fresh=True,used='n1.address'))for _ in range(6)])))
  d=convert(snapshot)
  d.update(transportAt=123456.25,transportBusy=True,transportProtocol=1,reply=dict(token='1234567890123-100',name='apply_bindings',ok=False,message='x'*400))
  def count(v):return 1+sum(count(x)for x in v.values())if isinstance(v,dict)else 1
  self.assertLessEqual(count(d),512)
  self.assertLess(len(json.dumps(d,ensure_ascii=False).encode()),16384)
if __name__=='__main__':unittest.main()
