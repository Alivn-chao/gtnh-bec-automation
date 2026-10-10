import unittest
from pathlib import Path
from test_module import LuaRuntime, SETUP, EXT, SOURCE

INSTALL=Path(__file__).with_name('install.lua').read_text(encoding='utf-8')
MOCK=r'''
files['/home/bec_nanites.lua']='old module'
local fs=require('filesystem')
fs.rename=function(a,b)
 if failRename or failInstall and a:find('pending',1,true) then return nil,'blocked' end
 assert(files[a] and not files[b]);files[b]=files[a];files[a]=nil;return true
end
io.open=function(p,mode)
 if mode=='r' then
  if not files[p] then return nil end
  return {read=function() return files[p] end,close=function() end}
 end
 assert(p:match('^/home/bec_nanites%.lua%.'))
 if failBackup and p:find('before_cellio',1,true) then return nil,'disk full' end
 return {write=function(_,text) files[p]=text;return true end,
   flush=function() return true end,close=function() end}
end
package.preload.internet=function() return {request=function(url)
 local body=badDownload and '404' or download;local i=1
 return function() if i>#body then return end;local s=body:sub(i,i+1023);i=i+1024;return s end
end} end
'''


class InstallTests(unittest.TestCase):
 def setUp(self):
  self.lua=LuaRuntime(unpack_returned_tuples=True)
  self.lua.globals().download=SOURCE
  self.lua.execute(SETUP+EXT+MOCK)

 def install(self): self.lua.execute(INSTALL)

 def test_install_with_backup_without_moving_or_journal_changes(self):
  self.install()
  self.assertEqual(self.lua.eval("files['/home/bec_nanites.lua']"),SOURCE)
  self.assertEqual(self.lua.eval("files['/home/bec_nanites.lua.before_cellio-1']"),'old module')
  self.assertEqual(self.lua.globals().moves,0)
  self.assertEqual(self.lua.globals().highs,0)
  self.assertEqual(self.lua.eval("files['/home/bec_nanites.journal']"),'old-filling-record')
  self.assertIsNone(self.lua.eval('files[PATH]'))

 def test_repeat_install_no_extra_backup(self):
  self.install();self.install()
  self.assertIsNone(self.lua.eval("files['/home/bec_nanites.lua.before_cellio-2']"))

 def test_download_and_backup_errors_preserve_original(self):
  for flag in ['badDownload','failBackup','failRename']:
   self.setUp();self.lua.execute(flag+'=true')
   with self.assertRaises(Exception): self.install()
   self.assertEqual(self.lua.eval("files['/home/bec_nanites.lua']"),'old module')

 def test_failed_install_rolls_back(self):
  self.lua.execute('failInstall=true')
  with self.assertRaisesRegex(Exception,'已恢复旧模块'): self.install()
  self.assertEqual(self.lua.eval("files['/home/bec_nanites.lua']"),'old module')

 def test_running_machine_blocks_install(self):
  self.lua.execute('allowed=true')
  with self.assertRaisesRegex(Exception,'仍允许工作'): self.install()
  self.assertIsNone(self.lua.eval("files['/home/bec_nanites.lua.before_cellio-1']"))


if __name__=='__main__': unittest.main()
