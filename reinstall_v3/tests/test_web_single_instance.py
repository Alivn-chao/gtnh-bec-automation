"""A duplicate web launch must not publish, release, pause, or start hardware."""
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(ROOT/'reinstall_v2/tests')]
from test_read_optimization import fixture

class WebSingleInstanceTests(unittest.TestCase):
    def make(self):
        l=fixture()
        l.globals().webSource=(ROOT/'reinstall_v2/files/web.lua').read_text(encoding='utf-8')
        l.execute("s.files['/home/bec_v2/lib/web_page.html']='<html></html>'")
        l.execute(r'''
local c=require('component')
c.list=function()local done=false;return function()if not done then done=true;return 'panel','hd_panel'end end end
c.methods=function()return {setWebApp=false,publish=false}end
panel={setWebApp=function()uploads=(uploads or 0)+1;return true end,publish=function()return true end,release=function()releases=(releases or 0)+1;return true end}
c.proxy=function()return panel end
local originalRequire=require
local events={pull=function()if parked then coroutine.yield('parked')end;return 'key_down','keyboard',113,16 end}
require=function(name)if name=='event'then return events end;return originalRequire(name)end
local loader=loadfile
loadfile=function(p)
 if p=='/home/bec_v2/lib/web_json.lua'then return function()return {}end end
 if p=='/home/bec_v2/lib/web_session.lua'then return function()return function()
  created=(created or 0)+1;if failInit then error('initialization failed')end
  lastH={snapshot=function()return {phase='idle',logs={}}end,engine=function()return {logs={'live log'}}end,close=function()closed=(closed or 0)+1;return {}end};return lastH
 end end end
 return loader(p)
end
function launch()return assert(load(webSource,'@/home/bec_v2/web.lua','t',_G))()end
''')
        return l

    def test_duplicate_is_rejected_before_session_or_panel_changes(self):
        l=self.make();l.execute(r'''
parked=true;first=coroutine.create(launch);assert(coroutine.resume(first));assert(panel._becWebOwner and created==1 and uploads==1)
assert(lastH.snapshot().phase=='idle'and panel._becWebOwner.state.phase=='idle'and panel._becWebOwner.logs[1]=='live log')
local ok,err=pcall(launch);assert(not ok and tostring(err):find('已经运行',1,true))
assert(created==1 and uploads==1 and not releases and not closed)
parked=false;assert(coroutine.resume(first));assert(coroutine.status(first)=='dead'and not panel._becWebOwner)
assert(closed==1 and releases==1)
launch();assert(created==2 and closed==2 and releases==2 and not panel._becWebOwner)
''')

    def test_dead_owner_can_be_replaced(self):
        l=self.make();l.execute(r'''
local dead=coroutine.create(function()end);assert(coroutine.resume(dead));panel._becWebOwner={root=dead}
parked=true;first=coroutine.create(launch);assert(coroutine.resume(first));parked=false;assert(coroutine.resume(first))
assert(created==1 and releases==1 and not panel._becWebOwner)
''')

    def test_initialization_failure_releases_lease_for_retry(self):
        l=self.make();l.execute("failInit=true;local ok=pcall(launch);assert(not ok and not panel._becWebOwner and not uploads);failInit=false;launch();assert(created==2 and releases==1)")

if __name__=='__main__':unittest.main()
