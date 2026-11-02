"""2.9.0 patch transaction, clean-boundary guard and rollback."""
from pathlib import Path
import subprocess
import unittest
from test_web_update import fixture

ROOT=Path(__file__).resolve().parents[2]
NAMES=['lib/config.lua','lib/cell_feed.lua','web.lua','cache_zero_recover.lua']
OLD={name:subprocess.check_output(['git','show','ff5da13:reinstall_v2/files/'+name],cwd=ROOT).decode()for name in NAMES}
SCRIPT=(ROOT/'reinstall_v3/update_290.lua').read_text(encoding='utf-8')


class ReleaseUpdateTests(unittest.TestCase):
 def make(self):
  l=fixture()
  for name,text in OLD.items():l.globals().files['/home/bec_v2/'+name]=text
  l.execute(r'''
journals={};cfg={groups={{generators={'gen'}}},nodes={{address='node',redstone='pause',pauseSide=1}}}
function loadfile(path)
 assert(path=='/home/bec_v2/lib/config.lua')
 return function()return {load=function()return cfg end,path=function(p)return '/home/bec_v2/'..p end,read=function(p)return journals[p]end}end
end
local c={}
c.list=function()local once=false;return function()if webActive and not once then once=true;return 'panel'end end end
c.proxy=function()return {_becWebOwner={root=coroutine.create(function()end)}}end
c.invoke=function(a,m,...)
 assert(not m:match('^set')and not m:match('^transfer'),'updater must not operate machines')
 if m=='getState'then return active and 'crafting'or 'idle'end
 if m=='getOutput'then return unpaused and 0 or 15 end
 if m=='isWorkAllowed'or m=='isMachineActive'then return active or false end
 error(m)
end
package.preload.component=function()return c end;package.loaded.component=nil
''')
  return l

 def test_install_and_idempotence_preserve_config_recipes_and_journals(self):
  l=self.make();l.execute("files['/home/bec_v2/recipes/a.dat']='recipe-keep';collectgarbage=nil")
  l.execute(SCRIPT)
  for name in NAMES:
   self.assertEqual(l.globals().files['/home/bec_v2/'+name],(ROOT/'reinstall_v2/files'/name).read_text(encoding='utf-8'))
   self.assertEqual(l.globals().files['/home/bec_v2/'+name+'.before-release290-1'],OLD[name])
  count=l.globals().count;l.execute(SCRIPT);self.assertEqual(l.globals().count,count)
  for name,text in [('config.dat','incomplete-keep'),('bindings.draft.dat','draft-keep'),('state/node-1/production.journal','pending-keep'),('recipes/a.dat','recipe-keep')]:
   self.assertEqual(l.globals().files['/home/bec_v2/'+name],text)

 def test_each_rename_failure_rolls_back_all_programs(self):
  for failure in range(1,2*len(NAMES)+1):
   l=self.make();l.globals().failure=failure
   l.execute("local fs=require('filesystem');local rename=fs.rename;local n=0;fs.rename=function(a,b)n=n+1;if n==failure then return false end;return rename(a,b)end")
   with self.assertRaisesRegex(Exception,'旧程序已恢复'):l.execute(SCRIPT)
   for name in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],OLD[name])

 def test_active_web_nodes_pending_batches_and_requests_are_refused(self):
  for mutation in (
   'webActive=true','active=true','unpaused=true',
   "journals['/home/bec_v2/state/group-1/cell-feed.journal']={stage='waiting-nodes'}",
   "journals['/home/bec_v2/state/group-1/cache.journal']={stage='stopped',requests={{state='submitted'}}}",
   "journals['/home/bec_v2/state/group-1/nanites-cell.journal']={stage='moving-cell'}",
  ):
   l=self.make();l.execute(mutation)
   with self.assertRaises(Exception):l.execute(SCRIPT)
   for name in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],OLD[name])

 def test_unknown_version_low_space_or_flush_failure_preserves_originals(self):
  for mutation in ("files['/home/bec_v2/web.lua']='custom'",'used=4100000','failFlush=true'):
   l=self.make();l.execute(mutation);before={name:l.globals().files['/home/bec_v2/'+name]for name in NAMES}
   with self.assertRaises(Exception):l.execute(SCRIPT)
   for name in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],before[name])

 def test_deployed_290_base_can_upgrade_without_changing_config(self):
  l=self.make()
  for name in NAMES:l.globals().files['/home/bec_v2/'+name]=subprocess.check_output(['git','show','0848982:reinstall_v2/files/'+name],cwd=ROOT).decode()
  l.execute(SCRIPT)
  for name in NAMES:self.assertEqual(l.globals().files['/home/bec_v2/'+name],(ROOT/'reinstall_v2/files'/name).read_text(encoding='utf-8'))


if __name__=='__main__':unittest.main()
