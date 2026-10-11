if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then
 assert(mode=="resume" or mode=="restock","流水备料未完成，请核对后用resume，不重新下单")
 assert(old.pending==nil and old.configOwned==false,"流水备料有未确认搬运")
 for _,job in ipairs(old.requests or {}) do assert(job.state=="done","流水备料申请未完成，保留日志，禁止重复申请") end
 for _,move in ipairs(old.transfers or {}) do assert(move.ok==true and move.amount==move.requested and integer(move.amount)>0,"流水搬液未完整确认") end
 assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"流水恢复须节点暂停且纠缠装置完成当前转换后停机")
 local req,left=current(true);assert(same(req,old.required) and same(left,old.remaining),"流水恢复订单变化，保留日志核对")
 resolveRawNames(old.target)
 local p=old.pipeline;assert(type(p.base)=="table" and type(p.initial)=="table" and type(p.delivered)=="table","流水守恒记录缺失")
 local stock,sub=field(),network(SUB);local allowed={}
 for _,item in ipairs(old.plan) do
  local raw,name=item.raw,item.name;assert(mapping[name]==raw,"流水恢复原液映射变化")
  allowed[raw]=true
  assert(integer(stock[name] or 0)+integer(sub[raw] or 0)==integer(p.base[name] or 0)+integer(p.initial[raw] or 0)+integer(p.delivered[raw] or 0),"流水恢复库存不守恒: "..raw)
 end
 for name,n in pairs(p.base) do assert((stock[name] or 0)>=n,"流水恢复已有凝聚物减少") end
 for raw in pairs(sub) do assert(allowed[raw],"流水恢复子网有无关原液") end
 -- Normalize in memory only; the archived journal keeps the complete pipeline.
 old.stage="stream-planned";old.secured=sub
 print("流水恢复守恒核对通过，抵扣已转换/剩余原液，不重放旧申请。")
end
