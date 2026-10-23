-- Conservative recovery for a crash before production supply or cell insertion.
-- This does not restore missing Minecraft items or replay AE orders.
local mode=...;mode=mode or 'preview'
assert(mode=='preview'or mode=='apply','Usage: lua /home/bec_recover.lua [preview|apply]')
local c=require('component');local clock=require('computer');local fs=require('filesystem');local ser=require('serialization')
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local cfg=C.read(C.path('config.dat'));assert(#cfg.groups==1,'Only the reviewed single-group layout is supported')
local function confirmed(journal)
 if not journal then return end
 assert(not journal.configOwned and not journal.pending,'Unresolved configuration or operation')
 for _,v in pairs(journal.transfers or {})do assert(v.ok==true and v.amount==v.requested,'Unconfirmed or partial fluid transfer')end
 for _,v in pairs(journal.requests or {})do assert(v.state=='done'or v.state=='rejected'and v.preSubmissionFailed==true,'Unconfirmed AE request')end
end
for a in c.list('hd_panel',true)do local o=rawget(c.proxy(a),'_becWebOwner');assert(not o or o.closed or coroutine.status(o.root)=='dead','Exit BEC web with Q before recovery')end
local g=cfg.groups[1];local bee=g.nanites
assert(bee and bee.enabled and bee.mode=='cell-io'and bee.hiveSource=='transposer','Physical hatch inventory binding required')
local cohortPath=C.path('state/group-1/cohort.dat');local cellPath=C.path('state/group-1/nanites-cell.journal')
local cohort=assert(C.read(cohortPath),'No interrupted cohort')
assert(cohort.stage=='interrupted'and cohort.version==2,'Only an interrupted cohort can be reviewed')
local cell=assert(C.read(cellPath),'No cell journal')
assert(cell.kind=='cell-io'and cell.version==2 and not cell.pending and not cell.holding,'Cell transfer or held inventory is unresolved')
assert(cell.stage=='loading'or cell.stage=='done'and cell.crashRecovery,'Only the verified pre-insertion loading boundary is supported')
local binding={bee.transposer,bee.loadRedstone,bee.returnRedstone,bee.bankSide,bee.loadSide,bee.returnSide,bee.loadOutputSide,bee.returnOutputSide}
for i,v in ipairs(binding)do assert(cell.binding[i]==v,'Cell binding changed')end
local tp=c.proxy(bee.transposer);local nodes,bank,pending={},{},{}
for i,n in ipairs(cfg.nodes)do
 assert(n.group==1,'Unexpected group')
 assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15 and c.invoke(n.address,'isWorkAllowed')==false,'All nodes must be paused with next-order intake closed')
 local state=c.invoke(n.address,'getState');local req=c.invoke(n.address,'getRequiredCondensate')
 local used=c.invoke(n.address,'getConsumedCondensate')or {}
 local row={index=i,address=n.address,state=state,required=req,consumed=used}
 if state=='idle'then assert(req==nil or type(req)=='table'and not next(req),'Idle node still has a requirement')
 else
  assert(state=='paused-immediate'or state=='nanite-tier-too-low','A node is still running')
  assert(type(req)=='table'and next(req)and not next(used),'Current recipe has consumption; manual reconciliation required')
  local p=c.invoke(n.address,'getParallelRecipesInProgress');assert(type(p)=='number'and p>0,'Unreadable parallel count')
  for k,v in pairs(req)do assert(cohort.normalized[k]==v/p,'Current recipe differs from interrupted cohort')end
  for k,v in pairs(cohort.normalized)do assert(req[k]==v*p,'Current recipe demand differs')end
  row.parallel=p;pending[#pending+1]=i
 end
 nodes[#nodes+1]=row
 local journal=C.read(C.path('state/node-'..i..'/production.journal'))
 confirmed(journal)
 if journal and journal.stage~='stopped'then
  assert(i==cohort.leader and journal.stage=='starting'and not journal.configOwned and not journal.pending,'Unfinished production work')
  for _,k in ipairs({'transfers','requests','secured','expected','topups'})do assert(not journal[k]or not next(journal[k]),'Unresolved production '..k)end
 end
end
for _,a in ipairs(g.generators)do assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'Generator is active')end
local sub=c.invoke(g.subInterface,'getFluidsInNetwork');assert(type(sub)=='table'and not next(sub),'Subnet fluid inventory is not empty')
for _,pair in ipairs({{bee.loadRedstone,bee.loadOutputSide},{bee.returnRedstone,bee.returnOutputSide}})do assert(c.invoke(pair[1],'getOutput',pair[2])==0,'IO port is enabled')end
for _,side in ipairs({bee.loadSide,bee.returnSide,bee.hatchSide})do
 local size=tp.getInventorySize(side);assert(type(size)=='number'and size>0,'Inventory unavailable')
 for i=1,size do assert(tp.getStackInSlot(side,i)==nil,'IO port or physical hatch is not empty')end
end
local total=0
for i=1,tp.getInventorySize(bee.bankSide)do local a=tp.getStackInSlot(bee.bankSide,i);if a then
 assert(i<=10 and a.name=='appliedenergistics2:item.ItemExtremeStorageCell.Singularity'and a.size==1,'Unmanaged bank item')
 local items=a.getAvailableItems;assert(type(items)=='table','Cell contents unavailable');local count=0
 for _,v in pairs(items)do assert(v.name=='gregtech:gt.metaitem.03'and type(v.size)=='number'and v.size>0,'Unexpected cell contents');count=count+v.size end
 assert(count==a.storedItemCount,'Cell count mismatch');bank[#bank+1]={slot=i,count=count,items=items}
 for _,v in pairs(items)do if v.damage==4581 and cell.requiredFamily=='Transcendent'and cell.requiredTier==4 then total=total+v.size end end
end end
assert(total==cell.operationTotal and total>=64,'Pre-insertion cell amount cannot be reconciled')
local cache=C.read(C.path('state/group-1/cache.journal'));assert(not cache or cache.stage=='stopped','Cache worker journal is unfinished')
confirmed(cache)
print('Checks passed. Current pending nodes: '..table.concat(pending,', '))
print('Old cohort will be archived as abandoned after crash, NOT marked completed. No transfers or AE requests will be replayed.')
if mode~='apply'then print('Preview only. To apply: lua /home/bec_recover.lua apply');return end
local proof={version=1,reason='server-crash-pre-supply-rebase',at=clock.uptime(),nodes=nodes,bank=bank,oldCohort=cohort,oldCell=cell,pending=pending}
local prefix=C.path('diagnostics/crash-recovery-'..math.floor(clock.uptime()));local suffix=0
while fs.exists(prefix..'.proof.dat')do suffix=suffix+1;prefix=C.path('diagnostics/crash-recovery-'..math.floor(clock.uptime())..'-'..suffix)end
C.write(prefix..'.proof.dat',proof)
local leaderPath=C.path('state/node-'..cohort.leader..'/production.journal');local leader=C.read(leaderPath)
if leader then C.write(prefix..'.production.dat',leader)end
C.write(prefix..'.cohort.dat',cohort);C.write(prefix..'.cell.dat',cell)
cell.stage='done';cell.crashRecovery=prefix;C.write(cellPath,cell)
if leader and leader.stage=='starting'then leader.stage='stopped';leader.crashRecovery=prefix;C.write(leaderPath,leader)end
C.write(cohortPath,{version=2,stage='stopped',leader=cohort.leader,members={},entries={},normalized=cohort.normalized,crashRecovery=prefix})
print('RECOVERY_APPLIED. Backup/proof: '..prefix)
print('Open BEC web and click Start. Missing/cancelled AE orders are not recreated by this command.')
