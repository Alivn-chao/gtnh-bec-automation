import pathlib,sys,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'work/lua_runtime'))
from lupa.lua52 import LuaRuntime
SOURCE=(ROOT/'fixes/crash_recovery/bec_recover.lua').read_text(encoding='utf-8-sig')
MOCK=r'''
files={};writes=0
local node={address='node',redstone='rs',pauseSide=5,group=1}
local bee={enabled=true,mode='cell-io',hiveSource='transposer',transposer='tp',loadRedstone='load',returnRedstone='ret',bankSide=0,loadSide=3,returnSide=2,hatchSide=4,loadOutputSide=0,returnOutputSide=0}
files['/home/bec_v2/config.dat']={nodes={node},groups={{nanites=bee,generators={'gen'},subInterface='sub'}}}
files['/home/bec_v2/state/group-1/cohort.dat']={stage='interrupted',version=2,leader=1,normalized={fluid=288},members={1},entries={}}
files['/home/bec_v2/state/group-1/nanites-cell.journal']={stage='loading',kind='cell-io',version=2,binding={'tp','load','ret',0,3,2,0,0},requiredFamily='Transcendent',requiredTier=4,operationTotal=23737}
files['/home/bec_v2/state/node-1/production.journal']={stage='starting',transfers={},requests={}}
local tp={getInventorySize=function(side)return side==0 and 10 or 3 end,getStackInSlot=function(side,i)
 if side~=0 then return badInventory and {name='unexpected'} or nil end
 if i==1 then return {name='appliedenergistics2:item.ItemExtremeStorageCell.Singularity',size=1,storedItemCount=23737,getAvailableItems={{name='gregtech:gt.metaitem.03',damage=4581,size=23737}}}end
end}
package.preload.component=function()return {
 list=function()return function()end end,proxy=function()return tp end,
 invoke=function(a,m,...)
  if m=='getOutput'then return a=='rs'and 15 or 0 end
  if m=='isWorkAllowed'or m=='isMachineActive'then return false end
  if m=='getState'then return 'nanite-tier-too-low'end
  if m=='getRequiredCondensate'then return {fluid=73728}end
  if m=='getConsumedCondensate'then return badConsumption and {fluid=1}or {}end
  if m=='getParallelRecipesInProgress'then return 256 end
  if m=='getFluidsInNetwork'then return {}end
  error(m)
 end}end
package.preload.computer=function()return {uptime=function()return 100 end}end
package.preload.filesystem=function()return {exists=function(p)return files[p]~=nil end}end
package.preload.serialization=function()return {}end
loadfile=function()return function()return {path=function(p)return '/home/bec_v2/'..p end,read=function(p)return files[p]end,write=function(p,v)writes=writes+1;files[p]=v end}end end
print=function()end
'''
class Recovery(unittest.TestCase):
 def runtime(self):
  l=LuaRuntime();l.execute(MOCK);return l
 def test_preview_never_writes(self):
  l=self.runtime();l.execute(SOURCE,'preview');self.assertEqual(l.globals().writes,0)
 def test_apply_backs_up_before_rebase(self):
  l=self.runtime();l.execute(SOURCE,'apply');self.assertEqual(l.eval("files['/home/bec_v2/state/group-1/cohort.dat'].stage"),'stopped');self.assertEqual(l.eval("files['/home/bec_v2/diagnostics/crash-recovery-100.cohort.dat'].stage"),'interrupted');self.assertGreater(l.globals().writes,5)
 def reject(self,setup):
  l=self.runtime();l.execute(setup)
  with self.assertRaises(Exception):l.execute(SOURCE,'apply')
  self.assertEqual(l.globals().writes,0)
 def test_consumption_blocks(self):self.reject('badConsumption=true')
 def test_io_contents_block(self):self.reject('badInventory=true')
 def test_unknown_request_blocks(self):self.reject("files['/home/bec_v2/state/node-1/production.journal'].requests={{state='unknown'}}")
 def test_pending_cell_blocks(self):self.reject("files['/home/bec_v2/state/group-1/nanites-cell.journal'].pending={from=0,to=3}")
 def test_stopped_unknown_request_blocks(self):self.reject("files['/home/bec_v2/state/node-1/production.journal']={stage='stopped',requests={{state='unknown'}}}")
 def test_stopped_partial_transfer_blocks(self):self.reject("files['/home/bec_v2/state/node-1/production.journal']={stage='stopped',transfers={{ok=true,requested=100,amount=50}}}")
if __name__=='__main__':unittest.main()
