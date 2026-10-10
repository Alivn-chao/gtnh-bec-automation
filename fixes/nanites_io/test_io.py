import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'work' / 'lua_runtime'))
from lupa.lua52 import LuaRuntime

SOURCE = Path(__file__).with_name('bec_nanites_io_test.lua').read_text(encoding='utf-8')
SETUP = r'''
T='13070035-3a3f-4468-b896-1c084288fdc9'
S='4e31083a-e153-40e4-bf3f-e5ada363819d'
N='4bfbed4a-5d62-4311-9d34-5761103e76ce'
P='266f65b5-20be-4543-8f2f-bfd2d0816611'
NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
PATH='/home/bec_nanites_io_test.journal'
CELL='appliedenergistics2:item.ItemExtremeStorageCell.Singularity'
inv={[0]={},[2]={},[3]={}}
files={['/home/bec_nanites.journal']='old-filling-record',
 ['/home/bec_auto.journal']='production-record', ['/home/bec_cache.journal']='cache-record'}
heldCount, now, moves, writes, highs, lagRemaining=0,0,0,0,0,0
rs={[S]=0,[N]=0}
allowed, broken, partial, lag, interfere, diskFull=false,false,false,false,false,false
local function contents(cell,n)
 cell.storedItemCount=n
 cell.getAvailableItems=n>0 and {{name='gregtech:gt.metaitem.03',damage=4581,size=n,hasTag=false}} or {}
end
function disk(n)
 local v={name=CELL,size=1};contents(v,n);return v
end
inv[0][9]=disk(19612)
local function encode(v)
 if type(v)=='table' then
  local t={};for k,x in pairs(v) do t[#t+1]='['..encode(k)..']='..encode(x) end
  return '{'..table.concat(t,',')..'}'
 elseif type(v)=='string' then return string.format('%q',v)
 else return tostring(v) end
end
package.preload.serialization=function() return {
 serialize=function(v,pretty) assert(pretty==false);return encode(v) end,
 unserialize=function(s) return assert(load('return '..s,'test-data','t',{}))() end
} end
package.preload.filesystem=function() return {exists=function(p) return files[p]~=nil end} end
io.open=function(p,mode)
 if mode=='r' then
  if not files[p] then return nil end
  return {read=function() return files[p] end,close=function() end}
 end
 assert(mode=='w' and p:match('^/home/bec_nanites_io_test%.journal'))
 return {write=function(_,text)
   if diskFull and text:find('moving%-cell') then error('disk full') end
   writes=writes+1;files[p]=text;return true
  end,flush=function() return true end,close=function() end}
end
package.preload.computer=function() return {uptime=function() return now end} end
os.sleep=function(n) now=now+n end
print=function() end
package.preload.component=function() return {
 type=function(a) return a==T and 'transposer' or (a==NODE and 'bec_io_node' or 'redstone') end,
 invoke=function(a,m,x,y,n,source,dest)
  if a==T then
   if m=='getInventoryName' then return x==0 and 'tile.CompressedChest' or 'tile.appliedenergistics2.BlockIOPort' end
   if m=='getInventorySize' then return x==0 and 243 or 12 end
   if m=='getStackInSlot' then return inv[x][y] end
   if m=='transferItem' then
    assert(n==1 and inv[x][source] and not inv[y][dest])
    assert((x==0 and (y==2 or y==3) and dest==1) or
      ((x==2 or x==3) and y==0 and source>=7))
    moves=moves+1;inv[y][dest]=inv[x][source];inv[x][source]=nil
    if broken then error('lost response after cell moved') end
    return 1
   end
  elseif a==NODE then
   if m=='isWorkAllowed' then return allowed end
   if m=='getState' then return heldCount>0 and 'paused-immediate' or 'nanite-tier-too-low' end
   if m=='getRequiredTier' then return {tier=1,name='Carbon'} end
   if m=='getProvidedTier' then return heldCount>0 and {tier=4,name='Transcendent'} or nil end
   if m=='getAvailableNanites' then
    if lagRemaining>0 then lagRemaining=lagRemaining-1;return 0 end
    return heldCount
   end
  else
   if m=='getOutput' then return a==P and (x==1 and 15 or 0) or (x==0 and rs[a] or 0) end
   if m=='setOutput' then
    assert((a==S or a==N) and x==0);rs[a]=y
    if y==15 then
     highs=highs+1
     local side=a==S and 3 or 2
     local d=assert(inv[side][1]);local count
     if side==3 then
      count=partial and math.floor(d.storedItemCount/2) or d.storedItemCount
      heldCount=heldCount+count;contents(d,d.storedItemCount-count)
     else
      count=partial and math.floor(heldCount/2) or heldCount
      contents(d,count);heldCount=heldCount-count
     end
     inv[side][1]=nil;inv[side][7]=d
     if lag then lagRemaining=3 end
     if interfere then allowed=true end
    end
    return true
   end
  end
  error('unexpected callback '..m)
 end
} end
'''


class CellTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(SETUP)

    def run_action(self, mode):
        self.lua.execute('assert(load(...))(' + repr(mode) + ')', SOURCE)

    def record(self):
        return self.lua.eval("require('serialization').unserialize(files[PATH])")

    def assert_stopped(self):
        self.assertEqual(self.lua.eval('rs[S]'), 0)
        self.assertEqual(self.lua.eval('rs[N]'), 0)

    def assert_old_records(self):
        self.assertEqual(self.lua.eval("files['/home/bec_nanites.journal']"), 'old-filling-record')
        self.assertEqual(self.lua.eval("files['/home/bec_auto.journal']"), 'production-record')
        self.assertEqual(self.lua.eval("files['/home/bec_cache.journal']"), 'cache-record')

    def test_preview_readonly(self):
        self.run_action('preview')
        self.assertEqual(self.lua.globals().moves, 0)
        self.assertEqual(self.lua.globals().writes, 0)
        self.assertEqual(self.lua.globals().highs, 0)

    def test_load_return_two_one_cell_moves_per_action(self):
        self.run_action('load')
        self.assertEqual(self.lua.globals().heldCount, 19612)
        self.assertEqual(self.lua.eval('inv[0][9].storedItemCount'), 0)
        self.assertEqual(self.lua.globals().moves, 2)
        self.assertEqual(self.record()['stage'], 'done')
        self.run_action('return')
        self.assertEqual(self.lua.globals().heldCount, 0)
        self.assertEqual(self.lua.eval('inv[0][9].storedItemCount'), 19612)
        self.assertEqual(self.lua.globals().moves, 4)
        self.assertEqual(self.record()['stage'], 'done')
        self.assert_stopped()
        self.assert_old_records()

    def test_node_cache_delay_is_not_count_loss(self):
        self.lua.execute('lag=true')
        self.run_action('load')
        self.assertEqual(self.lua.globals().heldCount, 19612)
        self.assertEqual(self.record()['stage'], 'done')

    def test_over_cap_never_moves(self):
        self.lua.execute('inv[0][9]=disk(40000)')
        with self.assertRaisesRegex(Exception, '超过30720'):
            self.run_action('load')
        self.assertEqual(self.lua.globals().moves, 0)
        self.assertEqual(self.lua.globals().highs, 0)

    def test_at_cap(self):
        self.lua.execute('inv[0][9]=disk(30720)')
        self.run_action('load')
        self.assertEqual(self.lua.globals().heldCount, 30720)

    def test_other_item_rejected(self):
        self.lua.execute("inv[0][9].getAvailableItems[1].damage=999")
        with self.assertRaisesRegex(Exception, '只允许T4'):
            self.run_action('load')
        self.assertEqual(self.lua.globals().moves, 0)

    def test_busy_and_existing_cell_rejected(self):
        for setup, error in [('allowed=true', '允许生产'), ('inv[2][1]=disk(0)', '已有硬盘')]:
            self.setUp()
            self.lua.execute(setup)
            with self.assertRaisesRegex(Exception, error):
                self.run_action('load')
            self.assertEqual(self.lua.globals().moves, 0)

    def test_partial_output_stays_for_inspection_not_replayed(self):
        self.lua.execute('partial=true')
        with self.assertRaisesRegex(Exception, '数量未完成或超时'):
            self.run_action('load')
        self.assertEqual(self.lua.globals().heldCount, 9806)
        self.assertEqual(self.lua.eval('inv[3][7].storedItemCount'), 9806)
        self.assertEqual(self.lua.globals().moves, 1)
        self.assert_stopped()
        with self.assertRaisesRegex(Exception, '旧搬盘测试未完成'):
            self.run_action('load')
        self.assertEqual(self.lua.globals().moves, 1)
        self.assert_old_records()

    def test_lost_transfer_response_keeps_pending(self):
        self.lua.execute('broken=true')
        with self.assertRaisesRegex(Exception, 'lost response'):
            self.run_action('load')
        self.assertEqual(self.record()['pending']['dest'], 1)
        self.assertEqual(self.lua.globals().moves, 1)
        self.assert_stopped()
        with self.assertRaisesRegex(Exception, '旧搬盘测试未完成'):
            self.run_action('load')

    def test_journal_failure_before_transfer(self):
        self.lua.execute('diskFull=true')
        with self.assertRaisesRegex(Exception, 'disk full'):
            self.run_action('load')
        self.assertEqual(self.lua.globals().moves, 0)
        self.assertEqual(self.lua.globals().highs, 0)
        self.assert_stopped()

    def test_manual_start_aborts_and_cuts_port_power(self):
        self.lua.execute('interfere=true')
        with self.assertRaisesRegex(Exception, '允许生产'):
            self.run_action('load')
        self.assert_stopped()
        self.assertNotEqual(self.record()['stage'], 'done')

    def test_return_requires_prior_success(self):
        with self.assertRaisesRegex(Exception, '上一轮'):
            self.run_action('return')
        self.assertEqual(self.lua.globals().moves, 0)


if __name__ == '__main__':
    unittest.main()
