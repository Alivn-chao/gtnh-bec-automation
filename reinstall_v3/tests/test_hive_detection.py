"""Detection deduplication on the real physical-hive source and V2 bridge."""
import subprocess
import unittest
from pathlib import Path
import test_cell_bridge as cell_bridge

ROOT=Path(__file__).resolve().parents[2]
V2=ROOT/'reinstall_v2/files'
BASE=ROOT/'fixes/hive_refresh/files/runtime/nanites_cell.lua'
NEW=ROOT/'fixes/hive_detection/files/runtime/nanites_cell.lua'

def world(baseline=False):
 f=cell_bridge.BridgeCellTests();f.setUp();l=f.lua
 l.globals().files['/home/bec_v2/runtime/nanites_cell.lua']=(BASE if baseline is True else NEW).read_text(encoding='utf-8')
 l.globals().files['/home/bec_v2/lib/hive_transposer.lua']=(V2/'lib/hive_transposer.lua').read_text(encoding='utf-8')
 l.globals().files['/home/bec_v2/lib/representative.lua']=(V2/'lib/representative.lua').read_text(encoding='utf-8')
 if baseline:
  revision='3c02005'if baseline=='dedup'else'd4f5bb8'
  for name in ('bridge','representative'):
   l.globals().files['/home/bec_v2/lib/'+name+'.lua']=subprocess.check_output(['git','show',revision+':reinstall_v2/files/lib/'+name+'.lua'],cwd=ROOT).decode('utf-8')
 l.execute(r'''
members(16)
task.fixedBatch={count=16};cfg.groups[1].cellFeed={enabled=false,representativeChecks=true}
local c=require('component');local invoke=c.invoke
calls,bankReads,arrayReads=0,0,0
c.invoke=function(a,m,...)
 calls=calls+1;local args={...}
 if a=='pause16'and m=='getOutput'and unpaused then return 0 end
 if a==T and m=='getStackInSlot'and args[1]==0 then bankReads=bankReads+1 end
 if(a==NODE or a:match('^member'))and(m=='getAvailableNanites'or m=='getProvidedTier')then
  arrayReads=arrayReads+1
  if stale and highs<refreshAt or arrayUntil and now<arrayUntil then return m=='getAvailableNanites'and 0 or nil end
 end
 if a==T and args[1]==4 then
  if m=='getInventoryName'then return 'gt.blockmachines'end
  if m=='getInventorySize'then return 3 end
  if m=='getStackInSlot'then
   if args[2]==3 and heldCount>0 then local v={};for k,x in pairs(heldItem)do v[k]=x end;v.size=math.min(heldCount,64);return v end
   return nil
  end
 end
 return invoke(a,m,...)
end
cfg.groups[1].nanites.hiveSource='transposer';cfg.groups[1].nanites.hatchSide=4
Bridge=loadfile('/home/bec_v2/lib/bridge.lua')()
''')
 return f,l

def prepare_switch(l):
 l.execute("need=5;inv[0][10]=disk(128,'SixPhasedCopper',101);calls=0;bankReads=0;arrayReads=0")

class HiveDetectionTests(unittest.TestCase):
 def test_same_switch_keeps_counts_and_reads_less(self):
  rows=[]
  for baseline in (True,'dedup',False):
   f,l=world(baseline);self.assertTrue(f.run_worker());prepare_switch(l)
   self.assertTrue(f.run_worker())
   self.assertEqual(l.globals().moves,6);self.assertEqual(l.globals().heldCount,128)
   self.assertEqual(l.eval('inv[0][9].storedItemCount'),19612)
   rows.append({k:int(l.globals()[k])for k in ('calls','bankReads','arrayReads')})
  print('physical-hive 16-node switch callbacks, before/after:',rows)
  self.assertLess(rows[2]['calls'],rows[1]['calls']*.5)
  self.assertEqual(rows[0]['bankReads']-rows[2]['bankReads'],10)
  self.assertEqual([r['arrayReads']for r in rows],[64,32,2])

 def test_late_pause_generator_or_cancel_change_blocks_transfer(self):
  for mutation in ('unpaused=true','generatorBusy=true','task.cancel=true'):
   f,l=world();self.assertTrue(f.run_worker());prepare_switch(l)
   l.globals().mutation=mutation
   l.execute(r'''
local open=io.open
io.open=function(path,mode)
 local f=open(path,mode);if f and mode=='w'then local write=f.write
  f.write=function(self,text)
   local result=write(self,text)
   if text:find('moving%-cell')then assert(load(mutation))()end
   return result
  end
 end;return f
end
''')
   with self.assertRaises(Exception):f.run_worker()
   self.assertEqual(l.globals().moves,2)
   self.assertEqual(l.eval('rs[S]+rs[N]'),0)

 def test_stale_cache_still_forces_one_recovery_and_reload(self):
  f,l=world();self.assertTrue(f.run_worker())
  l.execute('stale=true;refreshAt=highs+2')
  self.assertTrue(f.run_worker());self.assertEqual(l.globals().moves,6)
  self.assertFalse(f.run_worker());self.assertEqual(l.globals().moves,6)

 def test_bank_change_after_recovery_is_checked_before_loading(self):
  f,l=world();self.assertTrue(f.run_worker());prepare_switch(l)
  l.execute(r'''
local c=require('component');local invoke=c.invoke
c.invoke=function(a,m,...)
 local args={...};local value=invoke(a,m,...)
 if a==T and m=='transferItem'and args[1]==2 and args[2]==0 then inv[0][10]=disk(256,'Carbon',100)end
 return value
end
''')
  with self.assertRaises(Exception):f.run_worker()
  self.assertEqual(l.globals().moves,4);self.assertEqual(l.globals().heldCount,0)
  self.assertEqual(l.eval('inv[0][9].storedItemCount'),19612)
  self.assertEqual(l.eval('rs[S]+rs[N]'),0)

 def test_unknown_transfer_result_is_not_replayed(self):
  f,l=world();self.assertTrue(f.run_worker());prepare_switch(l);l.execute('broken=true')
  with self.assertRaises(Exception):f.run_worker()
  self.assertEqual(l.globals().moves,3)
  with self.assertRaisesRegex(Exception,'旧蜂群IO未完成'):f.run_worker()
  self.assertEqual(l.globals().moves,3)

 def test_delayed_array_confirmation_waits_without_more_moves(self):
  f,l=world();l.execute(r'''
arrayUntil=2
local worker=coroutine.create(function()return Bridge.environment(cfg,1,engine)()end)
for i=1,60 do
 local ok,value,deadline=coroutine.resume(worker);assert(ok,tostring(value))
 if coroutine.status(worker)=='dead'then assert(value);break end
 now=math.max(now,deadline or now+.1)
end
assert(coroutine.status(worker)=='dead'and now>=2)
''')
  self.assertEqual(l.globals().moves,2)

 def test_unrecognized_array_still_stops_with_verifying_record(self):
  f,l=world();l.execute(r'''
arrayUntil=1000
local worker=coroutine.create(function()return Bridge.environment(cfg,1,engine)()end)
local failure
for i=1,400 do
 local ok,value,deadline=coroutine.resume(worker)
 if not ok then failure=tostring(value);break end
 assert(coroutine.status(worker)~='dead','unrecognized array was released')
 now=math.max(now,deadline or now+.1)
end
assert(failure and failure:find('观测阵列仍未识别',1,true),tostring(failure))
assert(require('serialization').unserialize(files['/home/bec_v2/state/group-1/nanites-cell.journal']).stage=='verifying-array')
''')
  self.assertEqual(l.globals().moves,2);self.assertEqual(l.eval('rs[S]+rs[N]'),0)

if __name__=='__main__':unittest.main()
