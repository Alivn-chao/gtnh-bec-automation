local c = require("component") local ser = require("serialization") local computer = require("computer")
local fs = require("filesystem") local sides = require("sides") local event = require("event")
local mode, cacheCopies = ... mode=mode or "preview" local fixedStock
local background=mode=="background-stock" if mode=="preview-stock" or mode=="run-stock" or background then fixedStock=tonumber(cacheCopies)
assert(fixedStock and fixedStock>=1 and fixedStock<=2147483647 and fixedStock==math.floor(fixedStock),"统一库存需指定正整数mB") mode=mode=="preview-stock" and "preview" or "run" cacheCopies=1
else cacheCopies=tonumber(cacheCopies) or 1 end local JOURNAL = "/home/bec_cache.journal" local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50" local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad" local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0"
local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0" local GATE_ADDRESS = "cf2a0c4a-ab8d-4958-b1df-253094d6690c" local RS, GEN, GATE, armed, record
local stopping=false local mapping = { entangled_infinity = "molten.infinity",
entangled_chromaticglass = "molten.chromaticglass", entangled_transcendentmetal = "molten.transcendentmetal", entangled_dimshiftedsuperfluid = "dimensionallyshiftedsuperfluid",
entangled_neutronium="molten.neutronium",entangled_cosmicneutronium="molten.cosmicneutronium", entangled_bedrockium="molten.bedrockium",entangled_celestialtungsten="molten.celestialtungsten", entangled_hypogen="molten.hypogen",entangled_phononmedium="phononmedium",
entangled_quarkgluonplasma="quarkgluonplasma",entangled_spacetime="molten.spacetime", entangled_time="molten.temporalfluid",entangled_space="molten.spatialfluid", entangled_cosmicsolder="boundlesscosmicsolder",
entangled_mhdcsm="molten.magnetohydrodynamicallyconstrainedstarmatter", entangled_magmatter="molten.magmatter",entangled_universium="molten.universium", entangled_eternity="molten.eternity"
} local units={entangled_dimshiftedsuperfluid=1000,entangled_phononmedium=1000, entangled_quarkgluonplasma=1000,entangled_cosmicsolder=1000}
local function call(a, m, ...) return c.invoke(a, m, ...) end local function method(a, m) assert(c.methods(a)[m] ~= nil, "组件缺少方法: " .. m)
end local function resolve(prefix, kind) local address, count = nil, 0
for a, t in c.list() do if a:sub(1, #prefix) == prefix and t == kind then address, count = a, count + 1
end end assert(count == 1, "目标组件缺失或不唯一: " .. prefix)
return address end local function integer(v)
assert(type(v) == "number" and v >= 0 and v == math.floor(v), "库存/需求数量无效") return v end
local function same(a, b) for k, v in pairs(a) do if b[k] ~= v then return false end end for k, v in pairs(b) do if a[k] ~= v then return false end end
return true end local function network(a)
local rows, result = call(a, "getFluidsInNetwork"), {} assert(type(rows) == "table", "网络库存不可读") for _, f in pairs(rows) do
assert(type(f) == "table", "流体条目无效") local n = integer(f.amount or f.size or 0) if n > 0 then
assert(type(f.name) == "string", "流体名称缺失") result[f.name] = (result[f.name] or 0) + n end
end return result end
local matchedOutputs, perRecipe local function tick(seconds) local _,_,character=event.pull(seconds,"key_down")
if character==113 or character==81 then stopping=true end end local function archiveJournal(contents,suffix)
suffix=suffix or ".stopped-" local index=1 while fs.exists(JOURNAL..suffix..index) do index=index+1 end
local backup=JOURNAL..suffix..index assert(fs.rename(JOURNAL,backup),"旧常驻日志归档失败") local f=assert(io.open(backup,"r"));local actual=f:read("*a");f:close()
assert(actual==contents and not fs.exists(JOURNAL),"旧常驻日志归档验证失败") end local function field()
assert(call(STORAGE, "isWorkAllowed") == true, "约束场必须保持开启") local v = call(STORAGE, "getStoredCondensate") assert(type(v) == "table", "凝聚物库存不可读")
for _, n in pairs(v) do integer(n) end return v end
local function writeVerified(path, contents) local f = assert(io.open(path, "w")) local ok, err = f:write(contents)
local flushed, flushErr = f:flush() f:close() assert(ok and flushed, tostring(err or flushErr or "日志写入失败"))
local r = assert(io.open(path, "r")) local actual = r:read("*a"); r:close() assert(actual == contents and type(ser.unserialize(actual)) == "table", "日志回读失败")
end local function save(stage) record.stage = stage
if fs.exists(JOURNAL) then local f = assert(io.open(JOURNAL, "r")) local old = f:read("*a"); f:close()
writeVerified(JOURNAL .. ".previous", old) end writeVerified(JOURNAL, ser.serialize(record, false))
end local function pause(value) call(RS, "setOutput", sides.top, value)
assert(call(RS, "getOutput", sides.top) == value, "红石输出回读不符") end local function generator(enabled)
call(GEN, "setWorkAllowed", enabled) assert(call(GEN, "isWorkAllowed") == enabled, "纠缠装置启停回读不符") end
local function gateFilters(required) assert(type(required)=="table","门过滤需求不可读") local result={}
for name,n in pairs(required) do assert(mapping[name] and integer(n)>0,"门过滤需求无效: "..tostring(name)) result[#result+1]=name
end table.sort(result) assert(#result>0,"禁止写入全空过滤；全空会放行全部凝聚物")
return result end local function verifyGate(expected)
local count=integer(call(GATE,"getCondensateFilterCount")) assert(count>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters")
assert(type(actual)=="table" and same(actual,expected), "麦克斯韦门过滤回读不符；检查门的流体输入仓是否自动覆盖 OC 过滤") assert(call(GATE,"isWorkAllowed")==true,"麦克斯韦门未启用，保持暂停")
assert(call(GATE,"isMachineActive")==true,"麦克斯韦门未运行；检查结构和供电，保持暂停") end local function configureGate(required)
assert(call(RS,"getOutput",sides.top)==15 and call(NODE,"getState")=="paused-immediate", "切换门过滤前节点必须立即暂停") local expected=gateFilters(required)
assert(integer(call(GATE,"getCondensateFilterCount"))>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters") assert(type(actual)=="table","麦克斯韦门过滤不可读")
record.gateIntent={address=GATE,filters=expected};save(record.stage) if not same(actual,expected) then call(GATE,"setCondensateFilters",expected) end for i=1,3 do
verifyGate(expected) assert(call(NODE,"getState")=="paused-immediate","设置过滤时订单状态变化") if i<3 then tick(0.1) end
end print("麦克斯韦门过滤: "..table.concat(expected,", ")) return expected
end local function tanks(side, name) local count, amount = integer(call(TRANS, "getTankCount", side)), 0
assert(count > 0, "接口没有流体槽") for i = 1, count do local f = call(TRANS, "getFluidInTank", side, i)
assert(type(f) == "table", "接口缓存不可读") if type(f[1]) == "table" then f = f[i] or f[1] end local n = integer(f.amount or 0)
if n > 0 then assert(name and f.name == name, "接口有未处理流体缓存") amount = amount + n
end end return amount
end local function emptyConfig() for slot = 0, 5 do
assert(call(MAIN, "getFluidInterfaceConfiguration", slot) == nil, "供液接口已有配置") end end
local function waitUntil(seconds, condition, guard) local deadline = computer.uptime() + seconds while true do
local ready, snapshot = condition() if ready then return end if guard then guard(snapshot) end
assert(computer.uptime() < deadline, "等待超时，停止") os.sleep(0.25) end
end local function bulkPorts() local allowed,ports={},{}
for _,raw in pairs(mapping) do allowed[raw]=true;allowed["fluid."..raw]=true end
for _,raw in ipairs({"spatialfluid","fluid.spatialfluid","temporalfluid","fluid.temporalfluid"}) do allowed[raw]=true end for address,kind in c.list("transposer") do if kind=="transposer" and address~=TRANS then
local sources,receivers={},{} for side=0,5 do local ok,count=pcall(call,address,"getTankCount",side)
if ok and count==1 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==2147483647 then
local f=call(address,"getFluidInTank",side,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end if type(f)=="table" and allowed[f.name] then sources[#sources+1]={from=side,raw=f.name} end
end elseif ok and count==6 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1)
if readable and capacity==16000 then receivers[#receivers+1]=side end end end
if #sources>0 then assert(#receivers==1,"高速供液口接收方向缺失或不唯一: "..address) for _,source in ipairs(sources) do
assert(not ports[source.raw],"高速供液口重复绑定: "..source.raw) ports[source.raw]={address=address,from=source.from,to=receivers[1]} end
end end end
return ports end local function verifyBulk(route,raw)
local f=call(route.address,"getFluidInTank",route.from,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end assert(type(f)=="table" and f.name==raw
and call(route.address,"getTankCapacity",route.from,1)==2147483647,"高速缓存口绑定已变化") assert(call(route.address,"getTankCount",route.to)==6,"高速接收接口已变化") for i=1,6 do
local tank=call(route.address,"getFluidInTank",route.to,i) if type(tank)=="table" and type(tank[1])=="table" then tank=tank[i] or tank[1] end assert(type(tank)=="table" and integer(tank.amount or 0)==0,"高速接收接口有未处理缓存")
end end local function unchanged()
local state=call(NODE,"getState") local blocked={idle=true,["paused-immediate"]=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true} assert(state=="idle" or (background and blocked[state]),"节点状态变化，停止预缓存并保留已有库存")
assert(call(RS,"getOutput",sides.top)==15,"暂停信号变化") field() end
local function prepareStreaming(target) local ports=bulkPorts() local stock,previous=field(),network(SUB)
local expected,raws={},{} for name,need in pairs(target) do local raw=mapping[name]
local batch=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch local existing=previous[raw] or 0
assert(amount==0 or ports[raw],"缺少高速供液口："..raw.."；禁止普通接口回退")
assert(existing<=amount and existing%batch==0,"子网原液超额或非整批: "..raw) if amount>0 then expected[raw]=amount end raws[#raws+1]={raw=raw,amount=amount,batch=batch}
end for raw in pairs(previous) do local allowed=false
for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end assert(allowed,"子网有无关原液: "..raw) end
for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end table.sort(raws,function(a,b) return a.raw<b.raw end) record.plan=raws;record.expected=expected;record.secured=previous;save("stream-planned")
for _,item in ipairs(raws) do local raw,need,batch=item.raw,item.amount,item.batch local route=ports[raw]
local chunk=math.floor(2147483647/batch)*batch local function bufferedInlet() return 0 end if (previous[raw] or 0)<need then
unchanged();emptyConfig();tanks(4,nil) record.configOwned=false;save("stream-configuring")
assert(route,"高速供液口不可用："..raw);verifyBulk(route,raw)
print("高速供液: "..raw.."；源 "..route.from.." -> 接收 "..route.to)
print(raw.." 整批目标 "..need.." mB；到账即搬入子网。") local job,status,craft,jobDeadline,doneAt
local attempts=0 local inletOpen=false local deadline=computer.uptime()+1800
while not stopping do unchanged();assert(same(field(),stock),"备料时约束场库存变化") assert(same(network(SUB),previous),"备料时子网库存变化")
local remaining=need-(previous[raw] or 0) local buffered=network(MAIN)[raw] or 0 local amount=math.floor(math.min(remaining,buffered,chunk)/batch)*batch
if amount>0 then verifyBulk(route,raw);local address,from,to=route.address,route.from,route.to
record.pending={raw=raw,amount=amount,address=address,from=from,to=to};save("transfer-pending") local ok,moved=call(address,"transferFluid",from,to,amount) record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=address,from=from,to=to}
save("transfer-returned") assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试") previous[raw]=(previous[raw] or 0)+amount
waitUntil(10,function() return same(network(SUB),previous) end,unchanged) record.pending=nil;record.secured=previous;save("stream-transfer-confirmed") print(raw.." 已入子网 "..previous[raw].." / "..need.." mB")
deadline=computer.uptime()+1800 end remaining=need-(previous[raw] or 0)
if remaining==0 and inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;inletOpen=false;save("stream-inlet-cleared")
waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) end if status and job.state=="submitted" then
local canceled,why=status.isCanceled() assert(canceled==false,"主网原液申请失败/取消: "..tostring(why)) local done=status.isDone();assert(type(done)=="boolean","AE 状态不可读")
if done then job.state="done";job.securedAfter=previous[raw] or 0 doneAt=computer.uptime();save("stream-craft-done")
else assert(computer.uptime()<jobDeadline,"主网原液合成超时，保留申请记录") end end if remaining==0 and (not job or job.state=="done") then break end
if remaining>0 and (not job or job.state=="done") then local missing=math.max(0,remaining-bufferedInlet()-(network(MAIN)[raw] or 0)) if missing>0 and (not doneAt or computer.uptime()-doneAt>=3) then
if job then assert((previous[raw] or 0)>job.securedBefore, "本次原液合成已结束但子网没有收获，暂停核对竞争设备")
end local cpus=call(MAIN,"getCpus") assert(type(cpus)=="table","主网 CPU 状态不可读")
local available=false for _,cpu in pairs(cpus) do if cpu.busy==false then available=true end end if available then
if not craft then local rows=call(MAIN,"getCraftables",{name=raw}) assert(type(rows)=="table","原液配方不可读")
local count=0;for _,v in pairs(rows) do craft=v;count=count+1 end assert(count==1,"原液不足且AE补货配方缺失或不唯一: "..raw) local f=craft.getStack()
assert(type(f)=="table" and f.name==raw and f.isCraftable==true and type(f.amount)=="number" and f.amount==f.size and f.hasTag==false, "未验证的流体合成对象")
end attempts=attempts+1;assert(attempts<=3,"原液仍被争抢，暂停保留已收获库存") missing=math.max(0,need-(previous[raw] or 0)-bufferedInlet()-(network(MAIN)[raw] or 0))
if missing>0 then job={raw=raw,amount=missing,unit="mB",state="pending",securedBefore=previous[raw] or 0} record.requests[#record.requests+1]=job;save("craft-request-pending")
local reason;status,reason=craft.request(missing) assert(status~=nil,"AE 申请未确认: "..tostring(reason)) job.state="submitted";jobDeadline=computer.uptime()+1800;doneAt=nil
save("stream-crafting") print("主网 AE 申请 "..raw.." "..missing.." mB；合成中持续收料。") end
end end end
assert(computer.uptime()<deadline,"持续收料超时，保留子网已搬入原液") tick(0.1) end
if inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;save("stream-inlet-cleared")
end waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) if stopping then return expected end
end end assert(same(network(SUB),expected),"整批子网原液不符")
record.plan=nil;save("stream-prepared") return expected end
local function cacheTarget(copies) assert(type(copies)=="number" and copies>=1 and copies==math.floor(copies),"缓存份数必须为正整数") local totals,count={},0 local selectedBackground
assert(fs.exists("/home/bec/recipes"),"没有已登记配方") for filename in fs.list("/home/bec/recipes") do if filename:sub(-4)==".dat" then local f=assert(io.open("/home/bec/recipes/"..filename,"r"));local text=f:read("*a");f:close()
local recipe=ser.unserialize(text) assert(type(recipe)=="table" and recipe.state=="converted" and type(recipe.condensates)=="table","配方记录未完成: "..filename) local demand={}
for _,fluid in ipairs(recipe.condensates) do assert(mapping[fluid.name],"未登记原液映射: "..tostring(fluid.name)) demand[fluid.name]=(demand[fluid.name] or 0)+integer(fluid.amount)
end assert(next(demand),"配方没有凝聚物需求: "..filename) for name,need in pairs(demand) do
assert(need*copies<=2147483647,"缓存目标过大") totals[name]=math.max(totals[name] or 0,need*copies) end
count=count+1 print("配方 "..count.."："..filename) end end
assert(count>0,"没有可缓存的已登记配方") if fixedStock then for name in pairs(totals) do totals[name]=fixedStock end
end if background then local previous=io.open(JOURNAL,"r")
local old if previous then old=ser.unserialize(previous:read("*a"));previous:close() end if old and old.background and old.incomplete then
assert(old.stage=="stopped" and old.pending==nil and old.configOwned==false,"后台缓存有未确认操作，保留日志核对") totals=old.target else
if call(NODE,"getState")~="idle" then return {} end local stock=field();local selected,lowest for name,need in pairs(totals) do local available=stock[name] or 0
if available<need and (not lowest or available<lowest) then selected=name;lowest=available end end if not selected then return {} end
selectedBackground=selected;totals={[selected]=fixedStock} end end
local live,stock=network(MAIN),field();local visibleRoutes=bulkPorts();local waiting for kind in pairs(totals) do local raw=mapping[kind]
local candidates={[raw]=true} candidates["fluid."..raw]=true if kind=="entangled_space" or kind=="entangled_time" then
local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid" candidates[stem]=true;candidates["fluid."..stem]=true end
local found={} for name in pairs(candidates) do if (live[name] or 0)>0 or visibleRoutes[name] then found[name]=true end end for name in pairs(candidates) do
local rows=call(MAIN,"getCraftables",{name=name}) assert(type(rows)=="table","原液配方读取失败") for _,craft in pairs(rows) do local stack=craft.getStack()
if type(stack)=="table" and stack.name==name and type(stack.amount)=="number" then found[name]=true end end end
local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end assert(n<=1,"原液名称不唯一: "..kind)
if n==0 and (stock[kind] or 0)<totals[kind] then waiting="等待原液库存/样板可见: "..kind.." / "..raw end
if n==1 then mapping[kind]=name end end
local routes=bulkPorts();local stored=field()
for kind,need in pairs(totals) do
 if (stored[kind] or 0)<need and not routes[mapping[kind]] then waiting="等待高速口流体可见: "..kind.." / "..mapping[kind].."；空口暂不能识别绑定，稍后重扫" end
end
if selectedBackground then print("高速后台缓存：本种按剩余缺口补到 "..fixedStock.." mB，不受16桶轮次限制。") end if fixedStock then
print("登记配方 "..count.."；每种凝聚物统一目标 "..fixedStock.." mB，只补差额。") else print("登记配方 "..count.."；每配方 "..copies.." 份，共用流体按最大用量缓存。") end return totals,waiting
end local function cacheMain() assert(mode=="preview" or mode=="run","用法: preview / run [每配方份数，默认1]")
RS=resolve("266f65b5","redstone");GEN=resolve("c1ae3f7c","gt_machine") assert(call(GEN,"getName")=="multi.bec.generator","纠缠装置名称不符") local target,waiting=cacheTarget(cacheCopies)
while waiting do print(waiting)
if background or mode=="preview" then return end
tick(2);if stopping then print("已取消等待；日志和库存未修改。");return end
target,waiting=cacheTarget(cacheCopies) end
if background and next(target)==nil then return end local stock=field() for name,need in pairs(target) do
local batch=units[name] or 144 print(name.." 缓存目标 "..need.."；凝聚物已有 "..(stock[name] or 0) .."；待补原液 "..math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch.." mB")
end if mode=="preview" then print("只读规划完成，未申请、搬料、转换或写记录。");return end local producer=io.open("/home/bec_auto.journal","r")
if producer then local old=ser.unserialize(producer:read("*a"));producer:close() assert(type(old)=="table" and (old.stage=="stopped" or (background and old.stage=="cache-working")) and old.pending==nil and old.configOwned==false,
"请先在生产界面按 Q 正常停止，不同时运行两个服务") for _,job in ipairs(old.requests or {}) do assert(job.state=="done","生产日志还有未确认申请") end end
local nodeState=call(NODE,"getState") local blocked={idle=true,["paused-immediate"]=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true} assert(nodeState=="idle" or (background and blocked[nodeState]),"预缓存须在节点空闲/已暂停时进行")
assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"预缓存前须暂停并关闭纠缠装置") emptyConfig();tanks(4,nil);tanks(5,nil)
if fs.exists(JOURNAL) then local f=assert(io.open(JOURNAL,"r"));local text=f:read("*a");f:close() local old=ser.unserialize(text)
assert(type(old)=="table" and old.kind=="cache" and old.stage=="stopped" and old.pending==nil and old.configOwned==false,"旧缓存有未确认操作，请保留日志核对") for _,job in ipairs(old.requests or {}) do assert(job.state=="done","缓存申请仍未确认") end
archiveJournal(text) end record={version=1,kind="cache",requests={},transfers={},configOwned=false,target=target,copies=cacheCopies,fixedStock=fixedStock,background=background}
save("starting");armed=true local expected=prepareStreaming(target) if not stopping and next(expected) then
unchanged();save("converting");generator(true) local deadline=computer.uptime()+180 for kind in pairs(target) do
deadline=deadline+math.ceil((expected[mapping[kind]] or 0)/(units[kind] or 144))*180 end while true do
unchanged();local ready=true;local now=field() for name,need in pairs(target) do if (now[name] or 0)<need then ready=false end end if ready then break end
assert(computer.uptime()<deadline,"缓存转换超时，保留库存与日志") tick(0.25) if stopping then break end
end generator(false) end
unchanged();generator(false) record.incomplete=false local final=field()
for name,need in pairs(target) do if (final[name] or 0)<need then record.incomplete=true end end for _,job in ipairs(record.requests) do if job.state~="done" then save("craft-paused");print("缓存已暂停，AE申请仍需核对，不重复下单。");return
end end save("stopped") print(stopping and "预缓存已暂停，已有原液/凝聚物保留。" or background and "预缓存完成（本轮）；统一目标仍以界面各项库存为准。" or "预缓存完成；凝聚物留在约束场，生产时直接抵扣。")
end local ok,err=xpcall(cacheMain,debug.traceback) if not ok then
if armed then pcall(pause,15);pcall(generator,false) if record.configOwned then pcall(call,MAIN,"setFluidInterfaceConfiguration",0) end
end print("预缓存停止："..tostring(err));print("保留 /home/bec_cache.journal 和库存，不删除日志重跑。") end
return ok,err
