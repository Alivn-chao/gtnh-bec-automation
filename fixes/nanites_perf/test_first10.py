import unittest
import subprocess
from pathlib import Path
from test_perf import fixture, SOURCE
from test_empty_recovery import setup

PATCH=Path(__file__).with_name('patch_first10.lua').read_text(encoding='utf-8')

def installer():
    lua=setup();lua.globals().files['/home/bec_nanites.lua']=SOURCE
    lua.execute(r'''
      files[PATH]=require('serialization').serialize({version=2,kind='cell-io',stage='done'},false)
      local fs=require('filesystem')
      fs.rename=function(a,b)
        if failInstall and a:find('.first10-new-',1,true)then return false end
        assert(files[a] and not files[b]);files[b]=files[a];files[a]=nil;return true
      end
    ''')
    return lua

class First10Tests(unittest.TestCase):
    def patched_source(self):
        lua=installer();lua.execute(PATCH);return lua.globals().files['/home/bec_nanites.lua']

    def test_real_exchange_ignores_invalid_disk_outside_first10(self):
        lua=fixture();source=self.patched_source()
        lua.execute(r'''
          inv[0][11]={name='invalid item'}
          local c=require('component');local orig=c.invoke
          c.invoke=function(a,m,x,y,...)
            if a==T and x==0 and m=='getStackInSlot'then assert(y<=10,'Read outside first10')end
            if a==T and (x==2 or x==3) and m=='getStackInSlot'then assert(y==1 or y==7,'Read outside IO 1/7')end
            if a==T and m=='getAllStacks'then error('Full inventory bulk scan')end
            return orig(a,m,x,y,...)
          end
        ''')
        worker=lua.eval('function(...)'+source+'\nend')()
        self.assertTrue(worker.ensure(lua.table_from({'stage':True,'passive':True})))
        self.assertEqual(lua.globals().moves,4)
        self.assertEqual(lua.globals().heldCount,19612)

    def test_no_empty_cell_within_range_refuses_before_moving(self):
        lua=fixture();lua.execute('inv[0][9]=nil;inv[0][11]=disk(0)')
        worker=lua.eval('function(...)'+self.patched_source()+'\nend')()
        with self.assertRaisesRegex(Exception,'空数字奇点盘'):
            worker.ensure(lua.table_from({'stage':True,'passive':True}))
        self.assertEqual(lua.globals().moves,0)

    def test_installer_backs_up_changes_only_module_and_is_idempotent(self):
        lua=installer();old_auto=lua.globals().files['/home/bec_auto.journal']
        lua.execute(PATCH);modified=lua.globals().files['/home/bec_nanites.lua']
        self.assertIn('BEC_NANITES_BANK_FIRST10_V1',modified)
        self.assertIn('BEC_NANITES_IO_SLOTS_1_7_V1',modified)
        self.assertEqual(lua.globals().files['/home/bec_nanites.lua.before-first10-1'],SOURCE)
        self.assertEqual(lua.globals().files['/home/bec_auto.journal'],old_auto)
        lua.execute(PATCH)
        self.assertEqual(lua.globals().files['/home/bec_nanites.lua'],modified)

    def test_install_failure_restores_original(self):
        lua=installer();lua.execute('failInstall=true')
        with self.assertRaisesRegex(Exception,'original restored'):lua.execute(PATCH)
        self.assertEqual(lua.globals().files['/home/bec_nanites.lua'],SOURCE)

    def test_pending_move_blocks_installation(self):
        lua=installer();lua.execute("files[PATH]=require('serialization').serialize({stage='moving-cell'},false)")
        with self.assertRaisesRegex(Exception,'Recover the failed cell move'):lua.execute(PATCH)
        self.assertEqual(lua.globals().files['/home/bec_nanites.lua'],SOURCE)

    def test_upgrade_from_already_installed_first10_patch(self):
        old_patch=subprocess.check_output(['git','show','8e010ad2:fixes/nanites_perf/patch_first10.lua'],cwd=Path(__file__).resolve().parents[2]).decode('utf-8')
        lua=installer();lua.execute(old_patch);prior=lua.globals().files['/home/bec_nanites.lua']
        lua.execute(PATCH)
        self.assertIn('BEC_NANITES_IO_SLOTS_1_7_V1',lua.globals().files['/home/bec_nanites.lua'])
        self.assertEqual(lua.globals().files['/home/bec_nanites.lua.before-first10-2'],prior)

    def test_occupied_other_output_slot_blocks_installation(self):
        lua=installer();lua.execute('inv[2][8]=disk(0)')
        with self.assertRaisesRegex(Exception,'Empty both IO ports'):lua.execute(PATCH)
        self.assertEqual(lua.globals().files['/home/bec_nanites.lua'],SOURCE)

if __name__=='__main__':unittest.main()
