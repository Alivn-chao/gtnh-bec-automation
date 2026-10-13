from pathlib import Path
folder=Path(__file__).parent
body=(folder.parent/'production_overlap/recover.lua.inc').read_text(encoding='utf-8')
body=body.replace(' local sameRecipe=p.recipe and same(normalized,p.recipe)', ''' -- BEC_V1_IDLE_RECOVERY_V1: Beta 3 keeps the last consumed table when idle.
 local idleRetained=call(NODE,"getState")=="idle" and req==nil and parallel==0
 local sameRecipe=p.recipe and same(normalized,p.recipe)
 local idleAudit
 if idleRetained and p.overlap then
  assert(type(consumed)=="table" and type(old.required)=="table" and type(p.recipe)=="table","空闲末批消耗记录缺失")
  for name,n in pairs(consumed)do
   assert(p.recipe[name]~=nil or integer(n)==0,"空闲消耗有旧配方以外的流体: "..name)
   assert(integer(n)<=integer(old.required[name] or 0),"空闲末批消耗超过已记录需求: "..name)
  end
  idleAudit={kind="idle-retained-consumption",sourceJournal=contents,retainedConsumed=consumed,
   recordedRequired=old.required,field=stock,subnet=sub,missingAgainstRecorded={}}
  for name,n in pairs(old.required)do idleAudit.missingAgainstRecorded[name]=integer(n)-integer(consumed[name] or 0)end
 end''')
body=body.replace('local used=sameRecipe and integer(consumed[name] or 0) or 0', 'local used=(sameRecipe or idleRetained) and integer(consumed[name] or 0) or 0')
body=body.replace('if not sameRecipe then for _,n in pairs(consumed)', 'if not sameRecipe and not idleRetained then for _,n in pairs(consumed)')
body=body.replace(' old.stage="watching";old.plan=nil;old.pipeline=nil', ''' if idleAudit then
  -- The retained batch is separate from fully completed prior recipe units.
  -- Never count its partial consumption as delivered products or replay it.
  idleAudit.completedBeforeRetained=completed
  idleAudit.finalField=field()
  local index=1;while fs.exists(JOURNAL..".idle-recovery-"..index)do index=index+1 end
  local auditPath=JOURNAL..".idle-recovery-"..index
  writeVerified(auditPath,ser.serialize(idleAudit,false))
  print("空闲末批消耗核对通过；之前完整消耗 "..tostring(completed).." 份；末批单独记录: "..auditPath)
  print("末批缺口相对原记录: "..ser.serialize(idleAudit.missingAgainstRecorded,false).."；不伪造成品，不重放旧单。")
 end
 old.stage="watching";old.plan=nil;old.pipeline=nil''')
(folder/'recover.lua.inc').write_text(body,encoding='utf-8')
template=(folder/'installer.lua.inc').read_text(encoding='utf-8')
(folder/'patch_v1.lua').write_text(template.replace('RECOVER_BODY',body),encoding='utf-8')
