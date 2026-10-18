"""Transactional cache UI update, including exact HTML reconstruction."""
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(ROOT/'reinstall_v2/tests'),str(ROOT/'reinstall_v3')]
from test_web_update import fixture
from build_cache_response_update import NAMES,baseline

SCRIPT=(ROOT/'reinstall_v3/update_cache_response.lua').read_text(encoding='utf-8')
OLD={name:baseline(name)for name in NAMES}

class CacheResponseUpdateTests(unittest.TestCase):
    def make(self):
        l=fixture()
        for name in NAMES:l.globals().files['/home/bec_v2/'+name]=OLD[name]
        l.globals().files['/home/bec_v2/cache.config']='cache-settings-keep'
        l.globals().files['/home/bec_v2/state/group-1/cache.journal']='pending-cache-keep'
        return l

    def test_install_idempotent_without_gc_and_keeps_all_state(self):
        l=self.make();l.execute('collectgarbage=nil');l.execute(SCRIPT)
        for name in NAMES:
            p='/home/bec_v2/'+name
            self.assertEqual(l.globals().files[p],(ROOT/'reinstall_v2/files'/name).read_text(encoding='utf-8'))
            self.assertEqual(l.globals().files[p+'.before-v3-cache-1'],OLD[name])
        count=l.eval('count');l.execute(SCRIPT);self.assertEqual(l.eval('count'),count)
        for name,value in [('config.dat','incomplete-keep'),('bindings.draft.dat','draft-keep'),('state/node-1/production.journal','pending-keep'),('cache.config','cache-settings-keep'),('state/group-1/cache.journal','pending-cache-keep')]:
            self.assertEqual(l.globals().files['/home/bec_v2/'+name],value)
        self.assertLess(len(SCRIPT.encode()),100000)

    def test_all_ten_rename_failures_restore_all_five_files(self):
        for failure in range(1,11):
            with self.subTest(failure=failure):
                l=self.make();l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n=="+str(failure)+"then return false end;return rename(a,b)end")
                with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
                for name in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],OLD[name])

    def test_unknown_files_low_space_flush_failure_do_not_replace(self):
        for mutation in ["files['/home/bec_v2/lib/cache.lua']='custom'","files['/home/bec_v2/lib/web_page.html']='custom'",'used=4100000','failFlush=true']:
            with self.subTest(mutation=mutation):
                l=self.make();l.execute(mutation)
                before={name:l.globals().files['/home/bec_v2/'+name]for name in NAMES}
                with self.assertRaises(Exception):l.execute(SCRIPT)
                for name in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],before[name])

    def test_optional_temp_removal_and_crlf_source(self):
        l=self.make()
        for name in NAMES:l.globals().files['/home/bec_v2/'+name]=OLD[name].replace('\n','\r\n')
        l.globals().files['/home/bec_v3_cache_update.lua']=SCRIPT
        l.execute("require('filesystem').remove=function()return nil end;collectgarbage=nil")
        l.execute(SCRIPT)
        for name in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],(ROOT/'reinstall_v2/files'/name).read_text(encoding='utf-8'))

if __name__=='__main__':unittest.main()
