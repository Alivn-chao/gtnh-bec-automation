local function cacheTarget(copies)
  assert(type(copies)=="number" and copies>=1 and copies==math.floor(copies),"缓存份数必须为正整数")
  local totals,count={},0
  assert(fs.exists("/home/bec/recipes"),"没有已登记配方")
  for filename in fs.list("/home/bec/recipes") do if filename:sub(-4)==".dat" then
    local f=assert(io.open("/home/bec/recipes/"..filename,"r"));local text=f:read("*a");f:close()
    local recipe=ser.unserialize(text)
    assert(type(recipe)=="table" and recipe.state=="converted" and type(recipe.condensates)=="table","配方记录未完成: "..filename)
    local demand={}
    for _,fluid in ipairs(recipe.condensates) do
      assert(mapping[fluid.name],"未登记原液映射: "..tostring(fluid.name))
      demand[fluid.name]=(demand[fluid.name] or 0)+integer(fluid.amount)
    end
    assert(next(demand),"配方没有凝聚物需求: "..filename)
    for name,need in pairs(demand) do
      assert(need*copies<=2147483647,"缓存目标过大")
      totals[name]=math.max(totals[name] or 0,need*copies)
    end
    count=count+1
    print("配方 "..count.."："..filename)
  end end
  assert(count>0,"没有可缓存的已登记配方")
  if fixedStock then
    for name in pairs(totals) do totals[name]=fixedStock end
  end
  if background then
    local previous=io.open(JOURNAL,"r")
    local old
    if previous then old=ser.unserialize(previous:read("*a"));previous:close() end
    if old and old.background and old.incomplete then
      assert(old.stage=="stopped" and old.pending==nil and old.configOwned==false,"后台缓存有未确认操作，保留日志核对")
      totals=old.target
    else
      local stock=field();local selected,lowest
      for name,need in pairs(totals) do
        local available=stock[name] or 0
        if available<need and (not lowest or available<lowest) then selected=name;lowest=available end
      end
      if not selected then return {} end
      totals={[selected]=math.min(fixedStock,lowest+math.floor(16000/(units[selected] or 144))*(units[selected] or 144))}
    end
  end
  local live,stock=network(MAIN),field()
  for kind in pairs(totals) do
    local raw=mapping[kind]
    local candidates={[raw]=true}
    candidates["fluid."..raw]=true
    if kind=="entangled_space" or kind=="entangled_time" then
      local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid"
      candidates[stem]=true;candidates["fluid."..stem]=true
    end
    local found={}
    for name in pairs(live) do if candidates[name] then found[name]=true end end
    for name in pairs(candidates) do
      local rows=call(MAIN,"getCraftables",{name=name})
      assert(type(rows)=="table","原液配方读取失败")
      for _,craft in pairs(rows) do local stack=craft.getStack()
        if type(stack)=="table" and stack.name==name and type(stack.amount)=="number" then found[name]=true end
      end
    end
    local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end
    assert(n<=1,"原液名称不唯一: "..kind)
    assert(n==1 or (stock[kind] or 0)>=totals[kind],"主网没有原液库存或合成样板: "..kind.." / "..raw)
    if n==1 then mapping[kind]=name end
  end
  if fixedStock then
    print("登记配方 "..count.."；每种凝聚物统一目标 "..fixedStock.." mB，只补差额。")
  else print("登记配方 "..count.."；每配方 "..copies.." 份，共用流体按最大用量缓存。") end
  return totals
end
local function cacheMain()
  assert(mode=="preview" or mode=="run","用法: preview / run [每配方份数，默认1]")
  RS=resolve("266f65b5","redstone");GEN=resolve("c1ae3f7c","gt_machine")
  assert(call(GEN,"getName")=="multi.bec.generator","纠缠装置名称不符")
  local target=cacheTarget(cacheCopies)
  if background and next(target)==nil then return end
  local stock=field()
  for name,need in pairs(target) do
    local batch=units[name] or 144
    print(name.." 缓存目标 "..need.."；凝聚物已有 "..(stock[name] or 0)
      .."；待补原液 "..math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch.." mB")
  end
  if mode=="preview" then print("只读规划完成，未申请、搬料、转换或写记录。");return end
  local producer=io.open("/home/bec_auto.journal","r")
  if producer then
    local old=ser.unserialize(producer:read("*a"));producer:close()
    assert(type(old)=="table" and (old.stage=="stopped" or (background and old.stage=="cache-working")) and old.pending==nil and old.configOwned==false,
      "请先在生产界面按 Q 正常停止，不同时运行两个服务")
    for _,job in ipairs(old.requests or {}) do assert(job.state=="done","生产日志还有未确认申请") end
  end
  local nodeState=call(NODE,"getState")
  local blocked={idle=true,["paused-immediate"]=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true}
  assert(nodeState=="idle" or (background and blocked[nodeState]),"预缓存须在节点空闲/已暂停时进行")
  assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false
    and call(GEN,"isMachineActive")==false,"预缓存前须暂停并关闭纠缠装置")
  emptyConfig();tanks(4,nil);tanks(5,nil)
  if fs.exists(JOURNAL) then
    local f=assert(io.open(JOURNAL,"r"));local text=f:read("*a");f:close()
    local old=ser.unserialize(text)
    assert(type(old)=="table" and old.kind=="cache" and old.stage=="stopped"
      and old.pending==nil and old.configOwned==false,"旧缓存有未确认操作，请保留日志核对")
    for _,job in ipairs(old.requests or {}) do assert(job.state=="done","缓存申请仍未确认") end
    archiveJournal(text)
  end
  record={version=1,kind="cache",requests={},transfers={},configOwned=false,target=target,copies=cacheCopies,fixedStock=fixedStock,background=background}
  save("starting");armed=true
  local expected=prepareStreaming(target)
  if not stopping and next(expected) then
    unchanged();save("converting");generator(true)
    local deadline=computer.uptime()+180
    for kind in pairs(target) do
      deadline=deadline+math.ceil((expected[mapping[kind]] or 0)/(units[kind] or 144))*180
    end
    while true do
      unchanged();local ready=true;local now=field()
      for name,need in pairs(target) do if (now[name] or 0)<need then ready=false end end
      if ready then break end
      assert(computer.uptime()<deadline,"缓存转换超时，保留库存与日志")
      tick(0.25)
      if stopping then break end
    end
    generator(false)
  end
  unchanged();generator(false)
  record.incomplete=false
  local final=field()
  for name,need in pairs(target) do if (final[name] or 0)<need then record.incomplete=true end end
  for _,job in ipairs(record.requests) do if job.state~="done" then
    save("craft-paused");print("缓存已暂停，AE申请仍需核对，不重复下单。");return
  end end
  save("stopped")
  print(stopping and "预缓存已暂停，已有原液/凝聚物保留。" or "预缓存完成；凝聚物留在约束场，生产时直接抵扣。")
end
local ok,err=xpcall(cacheMain,debug.traceback)
if not ok then
  if armed then
    pcall(pause,15);pcall(generator,false)
    if record.configOwned then pcall(call,MAIN,"setFluidInterfaceConfiguration",0) end
  end
  print("预缓存停止："..tostring(err));print("保留 /home/bec_cache.journal 和库存，不删除日志重跑。")
end
return ok,err
