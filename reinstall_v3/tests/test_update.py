"""V3 update failures preserve old programs and every in-flight record."""
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(ROOT/'reinstall_v2/tests')]
from test_web_update import fixture
from test_performance import old, FILES

SCRIPT=(ROOT/'reinstall_v3/update.lua').read_text(encoding='utf-8')
class UpdateTests(unittest.TestCase):
    def make(self):
        l=fixture()
        for name in FILES:l.globals().files['/home/bec_v2/'+name]=old(name)
        # This historic updater requires the original companion modules, even
        # when the current source tree has a newer opt-in batch scheduler.
        for name in ['lib/engine.lua','lib/config.lua']:l.globals().files['/home/bec_v2/'+name]=old(name)
        l.globals().files['/home/bec_v2/state/group-1/nanites-cell.journal']='pending-cell-keep'
        l.globals().files['/home/bec_v2/cache.config']='cache-keep'
        return l

    def test_install_idempotence_and_preserve_state_without_gc(self):
        l=self.make();l.execute('collectgarbage=nil');l.execute(SCRIPT)
        for name in FILES:
            path='/home/bec_v2/'+name
            self.assertEqual(l.globals().files[path],(ROOT/'reinstall_v2/files'/name).read_text(encoding='utf-8'))
            self.assertEqual(l.globals().files[path+'.before-v3-performance-1'],old(name))
        count=l.eval('count');l.execute(SCRIPT);self.assertEqual(l.eval('count'),count)
        for name,value in [('config.dat','incomplete-keep'),('bindings.draft.dat','draft-keep'),('state/node-1/production.journal','pending-keep'),('state/group-1/nanites-cell.journal','pending-cell-keep'),('cache.config','cache-keep')]:
            self.assertEqual(l.globals().files['/home/bec_v2/'+name],value)

    def test_every_rename_failure_restores_all_three_programs(self):
        for failure in range(1,7):
            with self.subTest(failure=failure):
                l=self.make()
                l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failure)+"then return false end;return rename(a,b)end")
                with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
                for name in FILES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],old(name))

    def test_unknown_module_low_space_and_flush_failure_never_replace(self):
        for mutation in ["files['/home/bec_v2/runtime/controller.lua']='custom'","files['/home/bec_v2/lib/engine.lua']='custom'",'used=4100000','failFlush=true']:
            with self.subTest(mutation=mutation):
                l=self.make();l.execute(mutation)
                previous={name:l.globals().files['/home/bec_v2/'+name]for name in FILES}
                with self.assertRaises(Exception):l.execute(SCRIPT)
                for name in FILES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],previous[name])

    def test_temp_package_remove_failure_is_optional(self):
        l=self.make();l.globals().files['/home/bec_v3_update.lua']=SCRIPT
        l.execute("require('filesystem').remove=function()return nil end;collectgarbage=nil")
        l.execute(SCRIPT)
        self.assertEqual(l.globals().files['/home/bec_v3_update.lua'],SCRIPT)
        self.assertIn('BEC_V3_PERFORMANCE_1',l.globals().files['/home/bec_v2/runtime/controller.lua'])

if __name__=='__main__':unittest.main()
