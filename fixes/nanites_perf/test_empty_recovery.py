import unittest
from pathlib import Path
from test_perf import fixture

SCRIPT=Path(__file__).with_name('recover_empty_move.lua').read_text(encoding='utf-8')

def setup():
    lua=fixture()
    lua.execute(r'''
      local ser=require('serialization')
      files[PATH]=ser.serialize({version=2,kind='cell-io',stage='moving-cell',beforeReading=30720,
        requiredTier=1,requiredFamily='Carbon',pending={from=0,to=2,source=2,dest=1,count=0}},false)
      files['/home/bec_auto.journal']=ser.serialize({stage='watching',pipeline={keep=123},
        naniteStage={stage='switching',required={name='Carbon',tier=1}}},false)
      originalIO=files[PATH];originalAuto=files['/home/bec_auto.journal'];inv[0][2]=disk(0)
      local oldOpen=io.open
      io.open=function(p,m)
        if m=='w'then return {write=function(_,s)
          if failAuto and p=='/home/bec_auto.journal'then error('auto write failed')end
          files[p]=s;return true end,flush=function()return true end,close=function()end}
        end
        return oldOpen(p,m)
      end
      local c=require('component');local orig=c.invoke
      c.invoke=function(a,m,x,...)
        assert(m~='setOutput' and m~='transferItem','Recovery attempted machine mutation')
        if a=='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'then
          if m=='isWorkAllowed' or m=='isMachineActive'then return false end
        end
        if a==T and x==0 then
          if m=='getInventorySize'then return 27 end
          if m=='getInventoryName'then return bus and 'gt.blockmachines' or 'minecraft:chest' end
        end
        if a==NODE and m=='getAvailableNanites'then return math.min(heldCount,30720)end
        return orig(a,m,x,...)
      end
    ''')
    return lua

class RecoveryTests(unittest.TestCase):
    def test_verified_unmoved_recovers_both_markers_keeps_production(self):
        lua=setup();lua.execute(SCRIPT)
        self.assertEqual(lua.eval("require('serialization').unserialize(files[PATH]).stage"),'done')
        self.assertTrue(lua.eval("require('serialization').unserialize(files['/home/bec_auto.journal']).naniteStage==nil"))
        self.assertEqual(lua.eval("require('serialization').unserialize(files['/home/bec_auto.journal']).pipeline.keep"),123)
        self.assertEqual(lua.globals().files['/home/bec_nanites_io.journal.before-empty-move-recovery-1'],lua.globals().originalIO)
        self.assertEqual(lua.globals().files['/home/bec_auto.journal.before-empty-move-recovery-1'],lua.globals().originalAuto)
        lua.execute(SCRIPT)
        self.assertEqual(lua.globals().moves,0)
        self.assertEqual(lua.globals().heldCount,37604)

    def test_destination_occupied_rejects_without_journal_change(self):
        lua=setup();lua.execute('inv[2][1]=disk(0)')
        with self.assertRaisesRegex(Exception,'IO contains a disk'):lua.execute(SCRIPT)
        self.assertEqual(lua.globals().files[lua.globals().PATH],lua.globals().originalIO)

    def test_changed_source_or_hive_rejects(self):
        for change in ['inv[0][2]=nil','heldCount=64','bus=true']:
            lua=setup();lua.execute(change)
            with self.assertRaises(Exception):lua.execute(SCRIPT)
            self.assertEqual(lua.globals().files[lua.globals().PATH],lua.globals().originalIO)

    def test_interrupted_second_journal_can_finish_without_moving(self):
        lua=setup();lua.execute('failAuto=true')
        with self.assertRaisesRegex(Exception,'auto write failed'):lua.execute(SCRIPT)
        lua.execute('failAuto=false');lua.execute(SCRIPT)
        self.assertTrue(lua.eval("require('serialization').unserialize(files['/home/bec_auto.journal']).naniteStage==nil"))
        self.assertEqual(lua.globals().moves,0)

if __name__=='__main__':unittest.main()
