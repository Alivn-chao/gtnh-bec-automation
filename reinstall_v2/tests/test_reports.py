"""Reuse report behavior tests and test per-player repository isolation."""
import importlib.util
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
path=ROOT/'fixes/v2_reports/test_reports.py'
spec=importlib.util.spec_from_file_location('original_report_tests',path)
original=importlib.util.module_from_spec(spec);spec.loader.exec_module(original)
original.SOURCE=(ROOT/'reinstall_v2/files/lib/reports.lua').read_text(encoding='utf-8')

class SharedReports(original.ReportTests):pass

class DestinationTests(unittest.TestCase):
    def test_local_setup_saves_selected_repository_and_masks_token(self):
        lua,*_=original.fixture()
        lua.execute("""
        loadfile=function(p)assert(p=='/home/bec_v2/lib/config.lua');return function()return C end end
        package.preload.term=function()return {read=function(_,_,mask)assert(mask=='*');return 'ghp_UNIT_TEST_FAKE_TOKEN_ONLY' end}end
        io.read=function()return 'AnotherPlayer/logs' end;io.write=function()end
        """)
        lua.execute((ROOT/'reinstall_v2/files/report_setup.lua').read_text(encoding='utf-8'))
        self.assertEqual(lua.eval("C.read(C.path('github-upload.dat')).owner"),'AnotherPlayer')
        self.assertEqual(lua.eval("C.read(C.path('github-upload.dat')).repo"),'logs')
        self.assertIsNotNone(lua.globals().files['/home/bec_v2/github-upload.dat.previous'])

    def test_each_player_uses_their_own_repository(self):
        lua,remote,calls,_=original.fixture()
        lua.execute("local p=C.path('github-upload.dat');local v=C.read(p);v.owner='Player-123';v.repo='my.bec-logs';C.write(p,v);R.capture(1,E,'test')")
        original.pump(lua)
        self.assertTrue(all('/repos/Player-123/my.bec-logs/'in url for _,url in calls))
        self.assertEqual(lua.eval("C.read(C.path('diagnostics/index.dat')).reports[1].status"),'uploaded')

    def test_offline_report_acquires_destination_after_token_setup(self):
        lua,remote,calls,_=original.fixture()
        lua.execute("local p=C.path('github-upload.dat');local old=files[p];files[p]=nil;R.capture(1,E,'offline');files[p]=old")
        original.pump(lua)
        self.assertEqual(sum(method=='PUT'for method,_ in calls),1)

    def test_changed_credentials_never_redirect_an_existing_report(self):
        lua,remote,calls,_=original.fixture()
        lua.execute("R.capture(1,E,'old destination');local p=C.path('github-upload.dat');local v=C.read(p);v.owner='other';C.write(p,v)")
        original.pump(lua)
        self.assertEqual(calls,[])
        self.assertEqual(lua.eval("C.read(C.path('diagnostics/index.dat')).reports[1].status"),'pending')

    def test_destination_injection_never_makes_network_request(self):
        for value in ['../escape','foo/bar','bad?query','']:
            lua,remote,calls,_=original.fixture();lua.globals().bad=value
            lua.execute("local p=C.path('github-upload.dat');local v=C.read(p);v.owner=bad;C.write(p,v)")
            original.pump(lua)
            self.assertEqual(calls,[])

if __name__=='__main__':unittest.main()
