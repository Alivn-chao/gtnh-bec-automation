"""Only the HTML file changes; partial bindings and all machine state survive."""
import subprocess
import unittest
from pathlib import Path
from test_install import LuaRuntime,SETUP
HERE=Path(__file__).resolve().parents[1]
SCRIPT=(HERE/'update_web.lua').read_text(encoding='utf-8')
OLD=subprocess.check_output(['git','show','81b7724:reinstall_v2/files/lib/web_page.html'],cwd=HERE.parent).decode()
TARGET='/home/bec_v2/lib/web_page.html'
def fixture():
 l=LuaRuntime(unpack_returned_tuples=True);l.execute(SETUP)
 l.globals().files[TARGET]=OLD
 l.globals().files['/home/bec_v2/lib/ochd_bindings.lua']=(HERE/'files/lib/ochd_bindings.lua').read_text(encoding='utf-8')
 l.globals().files['/home/bec_v2/lib/web_session.lua']=(HERE/'files/lib/web_session.lua').read_text(encoding='utf-8')
 l.globals().files['/home/bec_v2/web.lua']=(HERE/'files/web.lua').read_text(encoding='utf-8')
 for n in ['lib/config.lua','lib/engine.lua','lib/bridge.lua','runtime/controller.lua']:l.globals().files['/home/bec_v2/'+n]=(HERE/'files'/n).read_text(encoding='utf-8')
 l.execute("local fs=require('filesystem');fs.get=function()return {spaceTotal=function()return 4194304 end,spaceUsed=function()return used or 1000000 end}end;files['/home/bec_v2/config.dat']='incomplete-keep';files['/home/bec_v2/bindings.draft.dat']='draft-keep';files['/home/bec_v2/state/node-1/production.journal']='pending-keep'")
 return l
class WebUpdateTests(unittest.TestCase):
 def test_update_before_bindings_complete_and_idempotent(self):
  l=fixture();l.execute(SCRIPT)
  self.assertEqual(l.globals().files[TARGET],(HERE/'files/lib/web_page.html').read_text(encoding='utf-8'))
  self.assertEqual(l.globals().files[TARGET+'.before-input-1'],OLD)
  for name,text in [('config.dat','incomplete-keep'),('bindings.draft.dat','draft-keep'),('state/node-1/production.journal','pending-keep')]:self.assertEqual(l.globals().files['/home/bec_v2/'+name],text)
  count=l.globals().count;l.execute(SCRIPT);self.assertEqual(l.globals().count,count)
 def test_ten_port_release_can_update(self):
  l=fixture();l.globals().files[TARGET]=subprocess.check_output(['git','show','933750b:reinstall_v2/files/lib/web_page.html'],cwd=HERE.parent).decode();l.execute(SCRIPT)
  self.assertEqual(l.globals().files[TARGET],(HERE/'files/lib/web_page.html').read_text(encoding='utf-8'))
 def test_unknown_html_is_not_overwritten(self):
  l=fixture();l.globals().files[TARGET]='custom'
  with self.assertRaisesRegex(Exception,'未知本地修改'):l.execute(SCRIPT)
  self.assertEqual(l.globals().files[TARGET],'custom');self.assertEqual(l.globals().count,0)
 def test_low_space_leaves_original_html(self):
  l=fixture();l.execute('used=4100000')
  with self.assertRaisesRegex(Exception,'空间不足'):l.execute(SCRIPT)
  self.assertEqual(l.globals().files[TARGET],OLD);self.assertEqual(l.globals().count,0)
 def test_failed_replace_rolls_back(self):
  l=fixture();l.execute("local fs=require('filesystem');local rename=fs.rename;fs.rename=function(a,b)if a:find('.input-new-',1,true)then return false end;return rename(a,b)end")
  with self.assertRaisesRegex(Exception,'原网页已恢复'):l.execute(SCRIPT)
  self.assertEqual(l.globals().files[TARGET],OLD)
 def test_failed_flush_preserves_original(self):
  l=fixture();l.execute('failFlush=true')
  with self.assertRaises(Exception):l.execute(SCRIPT)
  self.assertEqual(l.globals().files[TARGET],OLD)
if __name__=='__main__':unittest.main()
