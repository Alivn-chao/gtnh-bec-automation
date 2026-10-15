import base64
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'fixes/nanites_io'))
from test_io import LuaRuntime,SETUP
HERE=Path(__file__).parent
SOURCE=(HERE/'reports.lua').read_text(encoding='utf-8')

def fixture():
    lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(SETUP)
    lua.execute(r'''
      files={};times={};dirs={};writes=0;mutations=0
      local fs=require('filesystem')
      fs.exists=function(p)return files[p]~=nil or dirs[p]~=nil end
      fs.isDirectory=function(p)return dirs[p]~=nil end
      fs.lastModified=function(p)return times[p]or 1 end
      fs.remove=function(p)files[p]=nil;return true end
      fs.list=function(dir)
        local rows={};for p in pairs(files)do if p:sub(1,#dir+1)==dir..'/'then
          local name=p:sub(#dir+2);if not name:find('/',1,true)then rows[#rows+1]=name end
        end end;table.sort(rows);local i=0;return function()i=i+1;return rows[i]end
      end
      fs.rename=function(a,b)
        if renameFail and a:find(renameFail,1,true)then return false end
        assert(files[a]and not files[b]);files[b]=files[a];files[a]=nil;return true
      end
      io.open=function(p,m)
        if m=='r'then
          if files[p]==nil then return end
          return {read=function(_,n)if n=='*a'then return files[p]end;return files[p]:sub(1,n)end,close=function()end}
        end
        assert(m=='w');files[p]=''
        return {write=function(_,s)files[p]=s;return true end,flush=function()return true end,close=function()end}
      end
      C={path=function(p)return '/home/bec_v2/'..p end}
      C.read=function(p)
        if not files[p]then return end
        return require('serialization').unserialize(files[p])
      end
      C.write=function(p,v)
        if failIndex and p:find('index.dat',1,true)then error('disk full')end
        files[p]=require('serialization').serialize(v,false);writes=writes+1
      end
      cfg={nodes={{name='node1',address='node1',group=1,redstone='rs1',pauseSide=1}},groups={{generators={'gen1'}}}}
      C.load=function()return cfg end
      E={tasks={{status='fault',fault=true}},logs={'program failed'}}
      local c=require('component')
      c.invoke=function(a,m,...)error('Unexpected hardware call '..m)end
      c.internet={request=function(url,body,headers,method)
        local code,text=server(url,body,headers,method);local consumed=false
        return {finishConnect=function()return not delayConnect end,
          read=function()if consumed then return nil end;consumed=true;return text end,
          response=function()return code end,close=function()end}
      end}
      require('computer').address=function()return 'abcdefab-1234-5678-90ab-123456789abc'end
      os.time=function()return 123456789 end
      files[C.path('github-upload.dat')]=require('serialization').serialize({version=1,
        owner='Alivn-chao',repo='gtnh-bec-automation',token='github_pat_UNITTEST_ONLY_FAKE_TOKEN'},false)
    ''')
    remote={};calls=[];errors={}
    def server(url,body,headers,method):
        calls.append((method,url))
        if errors.get('status'):return errors['status'],'error'
        key=url.split('?')[0]
        if method=='PUT':
            data=json.loads(body);remote[key]=base64.b64decode(data['content']).decode('utf-8')
            if errors.get('lost_put'):raise RuntimeError('lost response')
            return 201,'{}'
        return (200,remote[key])if key in remote else (404,'missing')
    lua.globals().server=server
    lua.globals().reportModule=lua.eval('function(...)'+SOURCE+'\nend')()
    lua.execute('R=reportModule(cfg,C)')
    return lua,remote,calls,errors

def pump(lua,n=80):
    for _ in range(n):lua.execute('R.step();now=now+0.05')

class ReportTests(unittest.TestCase):
    def test_upload_verify_then_mark_uploaded_and_redact(self):
        lua,remote,calls,_=fixture()
        lua.execute("R.capture(1,E,'failure github_pat_UNITTEST_ONLY_FAKE_TOKEN')")
        pump(lua)
        self.assertEqual([m for m,_ in calls],['GET','PUT','GET'])
        self.assertNotIn('github_pat_UNITTEST_ONLY_FAKE_TOKEN',next(iter(remote.values())))
        self.assertIn('REDACTED',next(iter(remote.values())))
        self.assertEqual(lua.eval("C.read(C.path('diagnostics/index.dat')).reports[1].status"),'uploaded')

    def test_lost_put_response_is_idempotent_after_restart(self):
        lua,remote,calls,errors=fixture();errors['lost_put']=True
        lua.execute("R.capture(1,E,'failure')");pump(lua)
        self.assertEqual(len(remote),1)
        self.assertEqual(lua.eval("C.read(C.path('diagnostics/index.dat')).reports[1].status"),'pending')
        errors.clear();lua.execute('R=reportModule(cfg,C)');pump(lua)
        self.assertEqual(sum(m=='PUT'for m,_ in calls),1)
        self.assertEqual(lua.eval("C.read(C.path('diagnostics/index.dat')).reports[1].status"),'uploaded')

    def test_failed_upload_keeps_pending_and_caps_at_five(self):
        lua,_,_,errors=fixture();errors['status']=403
        for _ in range(8):lua.execute("R.capture(1,E,'failure')")
        pump(lua)
        self.assertEqual(lua.eval("#C.read(C.path('diagnostics/index.dat')).reports"),5)
        self.assertEqual(lua.eval("C.read(C.path('diagnostics/index.dat')).overflow"),3)
        self.assertEqual(lua.eval("C.read(C.path('diagnostics/index.dat')).reports[1].status"),'pending')

    def test_success_keeps_only_latest_three_uploaded_reports(self):
        lua,remote,_,_=fixture()
        for _ in range(6):
            lua.execute("R.capture(1,E,'failure')");pump(lua)
        self.assertEqual(len(remote),6)
        self.assertEqual(lua.eval("#C.read(C.path('diagnostics/index.dat')).reports"),3)
        self.assertIsNone(lua.globals().files['/home/bec_v2/diagnostics/abcdefab1234-1-123456789.txt'])

    def test_network_timeout_is_bounded_without_sleeping(self):
        lua,_,calls,_=fixture();lua.execute("delayConnect=true;R.capture(1,E,'failure')")
        pump(lua,500)
        self.assertEqual(len(calls),1)
        self.assertIn('超时',lua.globals().R.status)

    def test_no_credentials_still_saves_report_without_network(self):
        lua,_,calls,_=fixture();lua.execute("files[C.path('github-upload.dat')]=nil;R.capture(1,E,'failure')")
        pump(lua);self.assertEqual(calls,[])
        self.assertEqual(lua.eval("#C.read(C.path('diagnostics/index.dat')).reports"),1)

    def test_safe_history_pruning_protects_pending_current_and_previous(self):
        lua,_,_,_=fixture()
        lua.execute(r'''
          local dir=C.path('state/node-1');dirs[dir]=true
          for i=1,7 do local p=dir..'/production.journal.stopped-'..i
            C.write(p,{stage='stopped',transfers={{ok=true}},requests={{state='done'}}});times[p]=i
          end
          C.write(dir..'/production.journal.stopped-8',{stage='stopped',pending={uncertain=true}})
          C.write(dir..'/production.journal.before-resume-1',{stage='watching'})
          C.write(dir..'/production.journal',{stage='streaming'});files[dir..'/production.journal.previous']='keep'
          C.write(dir..'/production.journal.stopped-9',{stage='stopped',transfers={{ok=false}}})
        ''')
        pump(lua)
        for i in range(1,5):self.assertIsNone(lua.globals().files[f'/home/bec_v2/state/node-1/production.journal.stopped-{i}'])
        for name in ['stopped-5','stopped-6','stopped-7','stopped-8','stopped-9','before-resume-1']:
            self.assertIsNotNone(lua.globals().files['/home/bec_v2/state/node-1/production.journal.'+name])
        self.assertEqual(lua.globals().files['/home/bec_v2/state/node-1/production.journal.previous'],'keep')

    def test_base64_matches_python_with_binary_and_unicode(self):
        lua,_,_,_=fixture()
        for s in ['a','ab','abc','中文\nquote"']:
            self.assertEqual(lua.globals().reportModule.base64(s),base64.b64encode(s.encode()).decode())

class InstallerTests(unittest.TestCase):
    def setup_install(self):
        lua,*_=fixture()
        for path in ['lib/engine.lua','main.lua']:
            source=subprocess.check_output(['git','show','origin/codex/bec-v2-cell-io:experimental/bec_v2/'+path],cwd=ROOT).decode('utf-8')
            lua.globals().files['/home/bec_v2/'+path]=source
        lua.execute(r'''
          local c=require('component');c.invoke=function(a,m)
            if a=='rs1'and m=='getOutput'then return 15 end
            if a=='gen1'and(m=='isWorkAllowed'or m=='isMachineActive')then return false end
            error('unexpected machine write '..m)
          end
          loadfile=function(p)assert(p=='/home/bec_v2/lib/config.lua');return function()return C end end
        ''')
        return lua

    def test_actual_v2_install_compiles_and_preserves_config_and_journals(self):
        lua=self.setup_install();lua.execute((HERE/'patch_v1.lua').read_text(encoding='utf-8'))
        for path in ['lib/engine.lua','main.lua','lib/reports.lua','report_setup.lua']:
            lua.execute('assert(load(...))',lua.globals().files['/home/bec_v2/'+path])
        before=lua.globals().files['/home/bec_v2/lib/engine.lua']
        lua.execute((HERE/'patch_v1.lua').read_text(encoding='utf-8'))
        self.assertEqual(lua.globals().files['/home/bec_v2/lib/engine.lua'],before)

    def test_four_file_failure_rolls_back_installed_programs(self):
        lua=self.setup_install();before=lua.globals().files['/home/bec_v2/lib/engine.lua']
        lua.execute("renameFail='reports.lua.reports-new-'")
        with self.assertRaisesRegex(Exception,'originals restored'):lua.execute((HERE/'patch_v1.lua').read_text(encoding='utf-8'))
        self.assertEqual(lua.globals().files['/home/bec_v2/lib/engine.lua'],before)

if __name__=='__main__':unittest.main()
