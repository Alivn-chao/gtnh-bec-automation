-- Complete V1 install for a NEW OpenOS disk. Does not start machinery.
local first,second=...
local importOnly=first=='import'
local oldHome=first;if importOnly then oldHome=second end
local fs=require('filesystem');local ser=require('serialization');local internet
local TAG='bec-v1-full-2026-10-14.1'
local manifest={
{name="automation_demo.lua",size=2464,checksum=3590512264},
{name="bec_auto.lua",size=73181,checksum=1633258873},
{name="bec_bee_restart.lua",size=6673,checksum=1727298972},
{name="bec_cache.config",size=40,checksum=594873840},
{name="bec_cache.lua",size=28870,checksum=4226225003},
{name="bec_cache_ui.lua",size=12560,checksum=4040312061},
{name="bec_check.lua",size=910,checksum=3679727260},
{name="bec_clean.lua",size=2019,checksum=1165012568},
{name="bec_hd.config",size=101,checksum=3219594098},
{name="bec_hd.lua",size=11765,checksum=3202616409},
{name="bec_history.lua",size=1098,checksum=3287645135},
{name="bec_initialize.lua",size=8119,checksum=4171324930},
{name="bec_nanites.lua",size=17713,checksum=3876160642},
{name="bec_pattern.lua",size=2977,checksum=2540891175},
{name="bec_patterns.lua",size=7499,checksum=1281814973},
{name="bec_start.lua",size=1122,checksum=1162067},
{name="bec_ui.lua",size=31215,checksum=4183191812}
}
local bundled={
["automation_demo.lua"]=[========[-- Generic UI example: local simulated telemetry only. Never controls an actual machine.
local component=require("component")
local computer=require("computer")
local event=require("event")
local address
local count=0
for a in component.list("hd_panel",true)do address=a;count=count+1 end
assert(count==1,"请接入一面高清屏幕墙，等待拼屏完成；多面墙时自行指定组件地址")
local p=component.proxy(address)
local running=false
assert(p.setUI({title="自动化控制台",subtitle="通用接口演示 · 数值为样例，不控制真实机器",pages={
  {id="overview",label="运行总览",widgets={
    {id="energy",type="value",x=40,y=124,w=360,h=112,label="电力储备",unit=" EU"},
    {id="rate",type="value",x=420,y=124,w=360,h=112,label="生产速率",unit=" 件/秒"},
    {id="state",type="value",x=800,y=124,w=440,h=112,label="产线状态"},
    {id="stock",type="progress",x=40,y=260,w=1200,h=160,label="产物库存"},
    {id="switch",type="toggle",x=40,y=454,w=300,h=60,label="模拟产线",confirm="切换演示状态？此操作不会控制真实机器。"},
    {id="reset",type="button",x=360,y=454,w=240,h=60,label="重置演示计数"}}},
  {id="help",label="接口说明",widgets={
    {id="helptext",type="text",x=40,y=124,w=1200,h=180,label="接入自己的自动化"}}}
}}))
local amount=2500
local nextUpdate=computer.uptime()+.6
local ok,err=xpcall(function()
  while true do
    if computer.uptime()>=nextUpdate then
      nextUpdate=computer.uptime()+1
      if running then amount=math.min(10000,amount+25)end
      p.updateUI({energy={text="128.4M"},rate={text=running and "25" or "0"},state={text=running and "演示运行中" or "演示已停止"},
        stock={text=amount.." / 10000",value=amount,max=10000},switch={enabled=true,active=running},reset={enabled=true},
        helptext={text="setUI 定义页面；updateUI 更新数据；hd_panel_event 接收点击。"}})
    end
    local e={event.pull(.1)}
    if e[1]=="hd_panel_event"and e[2]==address then
      if e[3]=="switch"then running=e[6]==1;p.ack(e[5],true,"模拟状态已切换")
      elseif e[3]=="reset"then amount=0;p.ack(e[5],true,"演示计数已重置")
      else p.ack(e[5],false,"未定义的控件")end
      nextUpdate=math.min(nextUpdate,computer.uptime()+.6)
    elseif e[1]=="interrupted"or(e[1]=="key_down"and(e[3]==113 or e[3]==81))then break end
  end
end,debug.traceback)
pcall(p.release)
if not ok then error(err)end
]========],
["bec_auto.lua"]=[========[local c = require("component") local ser = require("serialization") local computer = require("computer") local fs = require("filesystem") local sides = require("sides") local event = require("event") local mode = (...) or "preview" local JOURNAL = "/home/bec_auto.journal"
local MAIN = "3afdc4cf-04e3-4ae9-8be6-e753c23a249d" local SUB = "86311657-33d1-41b5-a0d9-0aee7b5c2c50" local TRANS = "66fb280f-080d-4623-8d54-0dffd5cd5aad" local STORAGE = "237a9cac-118a-4b74-8755-0d0b0ad216c0" local NODE = "b04787f9-5423-4b03-8549-c786d4ef38d0" local GATE_ADDRESS = "cf2a0c4a-ab8d-4958-b1df-253094d6690c" local RS, GEN, GATE, armed, record local stopping=false
local NANITES=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")() local lastNaniteTier
local mapping = { entangled_infinity = "molten.infinity", entangled_chromaticglass = "molten.chromaticglass", entangled_transcendentmetal = "molten.transcendentmetal", entangled_dimshiftedsuperfluid = "dimensionallyshiftedsuperfluid", entangled_neutronium="molten.neutronium",entangled_cosmicneutronium="molten.cosmicneutronium", entangled_bedrockium="molten.bedrockium",entangled_celestialtungsten="molten.celestialtungsten", entangled_hypogen="molten.hypogen",entangled_phononmedium="phononmedium",
entangled_quarkgluonplasma="quarkgluonplasma",entangled_spacetime="molten.spacetime", entangled_time="molten.temporalfluid",entangled_space="molten.spatialfluid", entangled_cosmicsolder="boundlesscosmicsolder", entangled_mhdcsm="molten.magnetohydrodynamicallyconstrainedstarmatter", entangled_magmatter="molten.magmatter",entangled_universium="molten.universium", entangled_eternity="molten.eternity" } local units={entangled_dimshiftedsuperfluid=1000,entangled_phononmedium=1000,
entangled_quarkgluonplasma=1000,entangled_cosmicsolder=1000} local function call(a, m, ...) return c.invoke(a, m, ...) end local function method(a, m) assert(c.methods(a)[m] ~= nil, "组件缺少方法: " .. m) end local function resolve(prefix, kind) local address, count = nil, 0 for a, t in c.list() do
if a:sub(1, #prefix) == prefix and t == kind then address, count = a, count + 1 end end assert(count == 1, "目标组件缺失或不唯一: " .. prefix) return address end local function integer(v)
assert(type(v) == "number" and v >= 0 and v == math.floor(v), "库存/需求数量无效") return v end local function same(a, b) for k, v in pairs(a) do if b[k] ~= v then return false end end for k, v in pairs(b) do if a[k] ~= v then return false end end return true end
local function network(a) local rows, result = call(a, "getFluidsInNetwork"), {} assert(type(rows) == "table", "网络库存不可读") for _, f in pairs(rows) do assert(type(f) == "table", "流体条目无效") local n = integer(f.amount or f.size or 0) if n > 0 then assert(type(f.name) == "string", "流体名称缺失")
result[f.name] = (result[f.name] or 0) + n end end return result end local matchedOutputs, perRecipe local function checkRecipe(required,parallel) parallel=parallel or integer(call(NODE,"getParallelRecipesInProgress"))
assert(parallel>0 and type(required)=="table","当前配方并行/需求不可读") local normalized={} for name,n in pairs(required) do assert(mapping[name] and integer(n)>0 and n%parallel==0,"配方需求无法按并行拆分: "..tostring(name)) normalized[name]=n/parallel end local matches={} if fs.exists("/home/bec/recipes") then
for file in fs.list("/home/bec/recipes") do if file:match("%.dat$") then local f=assert(io.open("/home/bec/recipes/"..file,"r"));local r=ser.unserialize(f:read("*a"));f:close() assert(type(r)=="table","登记配方损坏: "..file) if r.state=="converted" then local needs={} for _,fluid in ipairs(r.condensates or {}) do needs[fluid.name]=(needs[fluid.name] or 0)+integer(fluid.amount or fluid.size) end if same(needs,normalized) then
assert(type(r.outputs)=="table" and #r.outputs==1,"登记产物无效: "..file) matches[#matches+1]=r.outputs[1] end end end end end if #matches>0 then
local provided=call(NODE,"getProvidedTier") if c.methods(NODE).getRequiredTier~=nil then local needed=call(NODE,"getRequiredTier") local tier=type(needed)=="table" and needed.tier or needed assert(type(tier)=="number","所需蜂群等级不可读") end  matchedOutputs,perRecipe=matches,normalized
return parallel end local amount=type(required)=="table" and required.entangled_chromaticglass assert(type(amount)=="number" and amount>0 and amount%288==0 and required.entangled_transcendentmetal==amount, "未验证的配方需求，保持暂停") local recipes=amount/288 assert(parallel==nil or parallel==recipes,"实际并行与凝聚物需求不符") local count=0; for _ in pairs(required) do count=count+1 end
assert(count==2,"未验证的凝聚物需求，保持暂停") local tier=call(NODE,"getProvidedTier") matchedOutputs={{name="gregtech:gt.metaitem.03",damage=32307,size=1}};perRecipe=normalized return recipes end local function tick(seconds)
local _,_,character=event.pull(seconds,"key_down") if character==113 or character==81 then stopping=true end end local function archiveJournal(contents,suffix)
assert(loadfile("/home/bec_history.lua"))().prune(JOURNAL..(suffix or ".stopped-"),2)
 suffix=suffix or ".stopped-" local index=1 while fs.exists(JOURNAL..suffix..index) do index=index+1 end local backup=JOURNAL..suffix..index
assert(fs.rename(JOURNAL,backup),"旧常驻日志归档失败") local f=assert(io.open(backup,"r"));local actual=f:read("*a");f:close() assert(actual==contents and not fs.exists(JOURNAL),"旧常驻日志归档验证失败") end local function field() assert(call(STORAGE, "isWorkAllowed") == true, "约束场必须保持开启") local v = call(STORAGE, "getStoredCondensate") assert(type(v) == "table", "凝聚物库存不可读")
for _, n in pairs(v) do integer(n) end return v end local function writeVerified(path, contents) local f = assert(io.open(path, "w")) local ok, err = f:write(contents) local flushed, flushErr = f:flush() f:close()
assert(ok and flushed, tostring(err or flushErr or "日志写入失败")) local r = assert(io.open(path, "r")) local actual = r:read("*a"); r:close() assert(actual == contents and type(ser.unserialize(actual)) == "table", "日志回读失败") end local function save(stage) record.stage = stage if fs.exists(JOURNAL) then
local f = assert(io.open(JOURNAL, "r")) local old = f:read("*a"); f:close() writeVerified(JOURNAL .. ".previous", old) end writeVerified(JOURNAL, ser.serialize(record, false)) end local function pause(value) call(RS, "setOutput", sides.top, value)
assert(call(RS, "getOutput", sides.top) == value, "红石输出回读不符") end local function generator(enabled) call(GEN, "setWorkAllowed", enabled) assert(call(GEN, "isWorkAllowed") == enabled, "纠缠装置启停回读不符") end local function switchNanites()
local needed=call(NODE,"getRequiredTier");needed=type(needed)=="table" and needed.tier or needed if type(needed)~="number" then return end
NANITES.ensure({tick=tick,stopping=function() return stopping end}) local provided=call(NODE,"getProvidedTier")
assert(type(provided)=="table" and provided.tier>=needed and integer(call(NODE,"getAvailableNanites"))>=64,"蜂群等级或数量不足，保持暂停") lastNaniteTier=needed
end local function gateFilters(required) assert(type(required)=="table","门过滤需求不可读") local result={} for name,n in pairs(required) do assert(mapping[name] and integer(n)>0,"门过滤需求无效: "..tostring(name)) result[#result+1]=name
end table.sort(result) assert(#result>0,"禁止写入全空过滤；全空会放行全部凝聚物") return result end local function verifyGate(expected) local count=integer(call(GATE,"getCondensateFilterCount")) assert(count>=#expected,"麦克斯韦门过滤槽不足")
local actual=call(GATE,"getCondensateFilters") assert(type(actual)=="table" and same(actual,expected), "麦克斯韦门过滤回读不符；检查门的流体输入仓是否自动覆盖 OC 过滤") assert(call(GATE,"isWorkAllowed")==true,"麦克斯韦门未启用，保持暂停") assert(call(GATE,"isMachineActive")==true,"麦克斯韦门未运行；检查结构和供电，保持暂停") end local function configureGate(required) assert(call(RS,"getOutput",sides.top)==15 and call(NODE,"getState")=="paused-immediate",
"切换门过滤前节点必须立即暂停") local expected=gateFilters(required) assert(integer(call(GATE,"getCondensateFilterCount"))>=#expected,"麦克斯韦门过滤槽不足") local actual=call(GATE,"getCondensateFilters") assert(type(actual)=="table","麦克斯韦门过滤不可读") record.gateIntent={address=GATE,filters=expected};save(record.stage) if not same(actual,expected) then call(GATE,"setCondensateFilters",expected) end for i=1,3 do
verifyGate(expected) assert(call(NODE,"getState")=="paused-immediate","设置过滤时订单状态变化") if i<3 then tick(0.1) end end print("麦克斯韦门过滤: "..table.concat(expected,", ")) return expected end local function tanks(side, name)
local count, amount = integer(call(TRANS, "getTankCount", side)), 0 assert(count > 0, "接口没有流体槽") for i = 1, count do local f = call(TRANS, "getFluidInTank", side, i) assert(type(f) == "table", "接口缓存不可读") if type(f[1]) == "table" then f = f[i] or f[1] end local n = integer(f.amount or 0) if n > 0 then
assert(name and f.name == name, "接口有未处理流体缓存") amount = amount + n end end return amount end local function emptyConfig() for slot = 0, 5 do
assert(call(MAIN, "getFluidInterfaceConfiguration", slot) == nil, "供液接口已有配置") end end local function current(recovering) local state=call(NODE,"getState") local unavailable=state=="assembler-offline" or state=="unpowered" or state=="nanite-tier-too-low" assert(state=="paused-immediate" or (recovering and unavailable and call(RS,"getOutput",sides.top)==15),"订单未处于立即暂停状态")
local parallel=integer(call(NODE, "getParallelRecipesInProgress")) assert(parallel>=1,"暂停节点没有正在处理的配方") local required, consumed = call(NODE, "getRequiredCondensate"), call(NODE, "getConsumedCondensate") assert(type(required) == "table" and type(consumed) == "table", "订单需求不可读") local remaining, total = {}, 0 for name, amount in pairs(required) do assert(mapping[name], "不支持的凝聚物: " .. tostring(name)) amount = integer(amount)
local used = integer(consumed[name] or 0) assert(used <= amount, "已消耗数量超过需求") remaining[name] = amount - used; total = total + amount end assert(total > 0, "订单没有有效需求") for name, amount in pairs(consumed) do assert(integer(amount) == 0 or required[name], "消耗记录与当前订单不符") end
checkRecipe(required,parallel) return required, remaining end local function queuedRecipes() local cpus=call(MAIN,"getCpus") assert(type(cpus)=="table","主网 CPU 清单不可读") local total=0 for _,row in pairs(cpus) do
if row.busy==true then assert(row.cpu~=nil,"主网 CPU 不提供任务对象，无法读取整批数量") for _,getter in ipairs({"activeItems","pendingItems"}) do local items=row.cpu[getter]() assert(type(items)=="table","主网剩余任务不可读: "..getter) for _,item in pairs(items) do for _,out in ipairs(matchedOutputs or {{name="gregtech:gt.metaitem.03",damage=32307,size=1}}) do if item.name==out.name and tonumber(item.damage or 0)==tonumber(out.damage or 0) then
assert(not out.hasTag and not item.hasTag,"带NBT产物不能用于整批计数") total=total+integer(item.size or item.amount or 0)/math.max(1,integer(out.size or out.amount or 1)) break end end end end end
end return math.ceil(total) end -- BEC_V1_ORDER_WINDOW_V1
local function batchTarget(required,remaining,queueHint)
  local parallel=checkRecipe(required)
  local queued=math.max(parallel,queueHint or queuedRecipes())
  local count=queued
  -- Bound the prepared window, not the AE order. Align the raw-fluid ceiling.
  for name in pairs(required) do
    local unit=units[name] or 144
    local limit=math.floor(2147483647/unit)*unit
    local now=integer(remaining[name])
    assert(now<=limit,'当前实际并行单轮需求超过单次供液上限: '..name..' / '..now..' mB；请降低机器最大并行')
    local per=perRecipe[name]
    assert(type(per)=='number' and per>0,'单配方需求不可读: '..name)
    count=math.min(count,parallel+math.floor((limit-now)/per))
  end
  local target={}
  for name in pairs(required) do
    target[name]=remaining[name]+perRecipe[name]*(count-parallel)
  end
  return target,count,queued
end
local function needsRefill(required,consumed,stock,queueHint)
  local remaining={}
  for name,amount in pairs(required) do
    local used=integer(consumed[name] or 0)
    assert(used<=amount,'当前消耗超过本轮需求: '..name)
    remaining[name]=amount-used
  end
  local window,count=batchTarget(required,remaining,queueHint)
  local parallel=checkRecipe(required)
  local ahead=math.min(parallel,math.max(0,count-parallel))
  for name in pairs(required) do
    -- Keep one following physical batch ready. Do not pause to refill the
    -- entire large queue after every completed recipe or small stock change.
    local low=math.min(window[name],remaining[name]+perRecipe[name]*ahead)
    if (stock[name] or 0)<low then return true end
  end
  return false
end
local function unchanged() local req, remaining = current() assert(same(req, record.required) and same(remaining, record.remaining), "暂停订单发生变化，停止")
end local function resolveRawNames(target) local main,sub,stock=network(MAIN),network(SUB),field() for kind,need in pairs(target) do if kind=="entangled_space" or kind=="entangled_time" then local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid" local candidates={[stem]=true,["molten."..stem]=true,["fluid."..stem]=true,["fluid.molten."..stem]=true} local found={}
for name in pairs(candidates) do if (main[name] or 0)>0 or (sub[name] or 0)>0 then found[name]=true end local rows=call(MAIN,"getCraftables",{name=name}) assert(type(rows)=="table","原液配方读取失败") for _,craft in pairs(rows) do local f=craft.getStack() if type(f)=="table" and f.name==name then found[name]=true end end
end local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end assert(n<=1,"空间/时间原液名称不唯一: "..kind) assert(n==1 or (stock[kind] or 0)>=need,"主网缺少空间/时间原液库存或样板: "..kind) if n==1 then mapping[kind]=name end end end end
local function plan(remaining,quiet) resolveRawNames(remaining) local stock, sub, main = field(), network(SUB), network(MAIN) local moves, expected, allowed, shortages, deficits = {}, {}, {}, {}, {} for name, need in pairs(remaining) do local raw = mapping[name] allowed[raw] = true local unit=units[name] or 144
local required = math.ceil(math.max(0, need - (stock[name] or 0)) / unit) * unit local existing = sub[raw] or 0 assert(existing <= required and existing % unit == 0, "子网原液超额或非整批: " .. raw) local missing = required - existing if (main[raw] or 0)<missing then deficits[#deficits+1]={raw=raw,amount=missing-(main[raw] or 0),needed=missing} shortages[#shortages+1]=raw..": 本次需补 "..missing.." mB，主网有 "..(main[raw] or 0) .."，还缺 "..(missing-(main[raw] or 0)).." mB"
end if required > 0 then expected[raw] = required end local left=missing while left>0 do local chunk=math.min(left,math.floor(16000/unit)*unit) moves[#moves+1]={raw=raw,amount=chunk};left=left-chunk end if not quiet then print(raw .. " 本次补入 " .. missing .. " mB") end
end for raw in pairs(sub) do assert(allowed[raw], "子网有无关原液: " .. raw) end for name, amount in pairs(stock) do assert(amount == 0 or mapping[name], "约束场有未知凝聚物: " .. name) end table.sort(moves, function(a,b) return a.raw < b.raw end) if #shortages>0 then table.sort(shortages)
local message=table.concat(shortages,"；") if not quiet then print("缺料: "..message.."；运行时向主网 AE 申请缺口") end table.sort(deficits,function(a,b) return a.raw<b.raw end) return nil,message,deficits end return moves, sub, expected end local function waitUntil(seconds, condition, guard)
local deadline = computer.uptime() + seconds while true do local ready, snapshot = condition() if ready then return end if guard then guard(snapshot) end assert(computer.uptime() < deadline, "等待超时，停止") os.sleep(0.25) end
end local function bulkPorts() local allowed,ports={},{} for _,raw in pairs(mapping) do allowed[raw]=true end for address,kind in c.list("transposer") do if kind=="transposer" and address~=TRANS then local sources,receivers={},{} for side=0,5 do
local ok,count=pcall(call,address,"getTankCount",side) if ok and count==1 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==2147483647 then local f=call(address,"getFluidInTank",side,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end if type(f)=="table" and allowed[f.name] then sources[#sources+1]={from=side,raw=f.name} end end
elseif ok and count==6 then local readable,capacity=pcall(call,address,"getTankCapacity",side,1) if readable and capacity==16000 then receivers[#receivers+1]=side end end end if #sources>0 then assert(#receivers==1,"高速供液口接收方向缺失或不唯一: "..address) for _,source in ipairs(sources) do
assert(not ports[source.raw],"高速供液口重复绑定: "..source.raw) ports[source.raw]={address=address,from=source.from,to=receivers[1]} end end end end return ports end
local function verifyBulk(route,raw) local f=call(route.address,"getFluidInTank",route.from,1) if type(f)=="table" and type(f[1])=="table" then f=f[1] end assert(type(f)=="table" and f.name==raw and call(route.address,"getTankCapacity",route.from,1)==2147483647,"高速缓存口绑定已变化") assert(call(route.address,"getTankCount",route.to)==6,"高速接收接口已变化") for i=1,6 do local tank=call(route.address,"getFluidInTank",route.to,i)
if type(tank)=="table" and type(tank[1])=="table" then tank=tank[i] or tank[1] end assert(type(tank)=="table" and integer(tank.amount or 0)==0,"高速接收接口有未处理缓存") end end local function prepareStreaming(target) resolveRawNames(target) local ports=bulkPorts() local stock,previous=field(),network(SUB)
local expected,raws={},{} for name,need in pairs(target) do local raw=mapping[name] local batch=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch local existing=previous[raw] or 0 assert(existing<=amount and existing%batch==0,"子网原液超额或非整批: "..raw) if amount>0 then expected[raw]=amount end
raws[#raws+1]={raw=raw,amount=amount,batch=batch} end for raw in pairs(previous) do local allowed=false for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end assert(allowed,"子网有无关原液: "..raw) end for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end
table.sort(raws,function(a,b) return a.raw<b.raw end) record.plan=raws;record.expected=expected;record.secured=previous;save("stream-planned") for _,item in ipairs(raws) do local raw,need,batch=item.raw,item.amount,item.batch local route=ports[raw] local chunk=math.floor((route and 2147483647 or 16000)/batch)*batch local function bufferedInlet() return route and 0 or tanks(4,raw) end if (previous[raw] or 0)<need then
unchanged();emptyConfig();tanks(4,nil) record.configOwned=route==nil;save("stream-configuring") if route then verifyBulk(route,raw) print("高速供液: "..raw.."；源 "..route.from.." -> 接收 "..route.to) else assert(call(MAIN,"setFluidInterfaceConfiguration",0, {name=raw,amount=math.min(need-(previous[raw] or 0),chunk),
size=math.min(need-(previous[raw] or 0),chunk)})==true,"持续供液配置失败") end print(raw.." 整批目标 "..need.." mB；到账即搬入子网。") local job,status,craft,jobDeadline,doneAt local attempts=0 local inletOpen=route==nil local deadline=computer.uptime()+1800 while not stopping do
unchanged();assert(same(field(),stock),"备料时约束场库存变化") assert(same(network(SUB),previous),"备料时子网库存变化") local remaining=need-(previous[raw] or 0) local buffered=route and (network(MAIN)[raw] or 0) or bufferedInlet() local amount=math.floor(math.min(remaining,buffered,chunk)/batch)*batch if amount>0 then local address,from,to=TRANS,4,5 if route then verifyBulk(route,raw);address,from,to=route.address,route.from,route.to end
record.pending={raw=raw,amount=amount,address=address,from=from,to=to};save("transfer-pending") local ok,moved=call(address,"transferFluid",from,to,amount) record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=address,from=from,to=to} save("transfer-returned") assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试") previous[raw]=(previous[raw] or 0)+amount waitUntil(10,function() return same(network(SUB),previous) end,unchanged) record.pending=nil;record.secured=previous;save("stream-transfer-confirmed")
print(raw.." 已入子网 "..previous[raw].." / "..need.." mB") deadline=computer.uptime()+1800 end remaining=need-(previous[raw] or 0) if remaining==0 and inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;inletOpen=false;save("stream-inlet-cleared") waitUntil(20,function() return tanks(4,raw)==0 end,unchanged)
end local priority=false
-- BEC_V1_SEQUENTIAL_CPU_WAIT_V1: keep both production fallback and cache alive while CPUs are occupied.
local supplyWaiting=false
local function supplyWait(reason,manual,missing,failure)
 supplyWaiting=true
 local summary=raw..': '..reason
 if not record.supplyWait or record.supplyWait.cpuWaitSummary~=summary then
  record.supplyWait={cpuWaitSummary=summary,cpuWait={[raw]={reason=reason,manual=manual,amount=missing,failure=failure}}}
  save(record.stage);print('供液等待: '..summary)
 end
end
if status and job.state=='submitted' then
 local computing=type(status.isComputing)=='function' and status.isComputing()
 local failed,why
 if type(status.hasFailed)=='function' then failed,why=status.hasFailed()end
 if computing==false and type(status.isComputing)=='function' and failed==true then
  job.state='rejected';job.preSubmissionFailed=true;job.manualSupply=true;job.failure=tostring(why)
  status=nil;save('stream-request-rejected')
 elseif computing then supplyWait('AE 正在计算计划，继续收料')
 else
  local canceled,why=status.isCanceled();assert(canceled==false,'AE任务取消且结果未确认: '..tostring(why))
  local done=status.isDone();assert(type(done)=='boolean','AE 状态不可读')
  if done then job.state='done';job.securedAfter=previous[raw] or 0;doneAt=computer.uptime();save('stream-craft-done')
  else supplyWait('AE 合成进行中，继续收料')end
 end
end
if priority and (not job or job.state=='done' or job.state=='rejected')then return handoff()end
if remaining==0 and (not job or job.state=='done' or job.state=='rejected')then record.supplyWait=nil;break end
if not priority and remaining>0 and (not job or job.state=='done' or job.state=='rejected')then
 local function deficit()return math.max(0,need-(previous[raw]or 0)-tanks(4,raw)-(network(MAIN)[raw]or 0))end
 local missing=deficit()
 if missing>0 and (not doneAt or computer.uptime()-doneAt>=3)then
  if job and job.state=='done'then assert((previous[raw]or 0)>job.securedBefore,'原液合成已结束但没有收获，核对竞争设备')end
  local ok,cpus=pcall(call,MAIN,'getCpus');local free,total,known,maxStorage=0,0,0,0;local unknown=not ok or type(cpus)~='table'
  if not unknown then for _,cpu in pairs(cpus)do
   total=total+1
   if type(cpu)~='table' or type(cpu.busy)~='boolean'then unknown=true
   else if not cpu.busy then free=free+1 end
    if type(cpu.storage)=='number'and cpu.storage>=0 then known=known+1;maxStorage=math.max(maxStorage,cpu.storage)end
   end
  end end
  if job and job.manualSupply then
   supplyWait('AE未启动申请；请在 ME 手动申请 '..missing..' mB；自动收料继续',true,missing,job.failure)
  elseif unknown then supplyWait('等待 CPU 状态恢复可读')
  elseif total==0 or (known==total and maxStorage==0)then supplyWait('CPU 容量不足：没有可用合成存储')
  elseif free==0 then supplyWait('等待合成 CPU 空闲，自动化继续运行')
  else
   if not craft then
    local rows=call(MAIN,'getCraftables',{name=raw});assert(type(rows)=='table','原液配方不可读')
    local count=0;for _,v in pairs(rows)do craft=v;count=count+1 end
    assert(count==1,'原液配方缺失或不唯一: '..raw)
    local f=craft.getStack();assert(type(f)=='table'and f.name==raw and f.isCraftable==true and type(f.amount)=='number'and f.amount==f.size and f.hasTag==false,'未验证的流体合成对象')
   end
   missing=deficit()
   if missing>0 then

    attempts=attempts+1;assert(attempts<=3,'原液被其他设备争抢，保留已收库存')
    job={raw=raw,amount=missing,unit='mB',state='pending',securedBefore=previous[raw]or 0}
    record.requests[#record.requests+1]=job;save('craft-request-pending')
    local why;status,why=craft.request(missing);assert(status~=nil,'AE申请结果不明: '..tostring(why))
    job.state='submitted';doneAt=nil;save('stream-crafting')
    supplyWait('AE 正在计算计划，继续收料')
   end
  end
 end
end
if supplyWaiting then deadline=math.max(deadline,computer.uptime()+1800)end
assert(computer.uptime()<deadline,'持续收料超时，保留子网已搬入原液')

tick(0.1) end if inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;save("stream-inlet-cleared") end waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) if stopping then return expected end
end end assert(same(network(SUB),expected),"整批子网原液不符") record.plan=nil;save("stream-prepared") return expected end
local serviceNaniteStage
-- BEC_V1_PRODUCTION_OVERLAP_V3: overlap independent AE jobs and conversion on bulk routes.
local sequentialPrepare=prepareStreaming
prepareStreaming=function(target)
 resolveRawNames(target)
 local ports,base,held=bulkPorts(),field(),network(SUB)
 for name,n in pairs(base) do assert(n==0 or mapping[name],"约束场有未知凝聚物") end
 local items,allowed,expected={},{},{}
 for name,need in pairs(target) do
  local raw,batch=mapping[name],units[name] or 144
  local amount=math.ceil(math.max(0,need-(base[name] or 0))/batch)*batch
  if amount>(held[raw] or 0) and not ports[raw] then
   print("缺少独立高速口，保留原顺序备料: "..raw)
   return sequentialPrepare(target)
  end
  assert((held[raw] or 0)<=amount and (held[raw] or 0)%batch==0,"子网原液超额或非整批: "..raw)
  allowed[raw]=true
  if amount>0 then expected[raw]=amount end
  items[#items+1]={raw=raw,name=name,amount=amount,batch=batch,initial=held[raw] or 0,delivered=0,attempts=0}
 end
 for raw in pairs(held) do assert(allowed[raw],"子网有无关原液: "..raw) end
 table.sort(items,function(a,b)return a.raw<b.raw end)
 unchanged();emptyConfig();tanks(4,nil);tanks(5,nil)
 assert(call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"流水备料开始前纠缠装置须停机")
 record.pipeline={base=base,initial=held,delivered={}}
 local recipe={};checkRecipe(record.required)
 for name,n in pairs(perRecipe) do recipe[name]=n end
 record.pipeline.recipe=recipe;record.pipeline.startConsumed={}
 for name,n in pairs(record.required) do record.pipeline.startConsumed[name]=n-record.remaining[name] end
 local halted,released=false,false
 local releasedAt;local lastFeedback;local feedbackAt=0
 local lastRequired=record.required
 local tierMethod=c.methods(NODE).getRequiredTier~=nil
 local function tierValue()local t=call(NODE,"getRequiredTier");return type(t)=="table" and t.tier or t end
 local neededTier=tierMethod and tierValue()
 local function productionGuard()
  serviceNaniteStage()

  if record.gateIntent then verifyGate(record.gateIntent.filters) end
  local state=call(NODE,"getState")
  local req=call(NODE,"getRequiredCondensate")
  local parallel=call(NODE,"getParallelRecipesInProgress")
  local normalized={}
  if type(req)=="table" and type(parallel)=="number" and parallel>0 then
   for name,n in pairs(req) do normalized[name]=integer(n)/parallel end
  end
  local changed=not same(normalized,recipe)
  local reason=changed and "配方需求变化，等待旧窗口收尾" or nil
  local tierCovered=false
  if not changed and tierMethod then
   local nextTier=tierValue()
   if nextTier~=neededTier or state=="nanite-tier-too-low" then
    local provided=call(NODE,"getProvidedTier")
    local count=call(NODE,"getAvailableNanites")
    tierCovered=type(nextTier)=="number" and type(provided)=="table" and type(provided.tier)=="number"
     and provided.tier>=nextTier and type(count)=="number" and count>=64
    if tierCovered then
     neededTier=nextTier
    else neededTier=nextTier;tierCovered=true end
   end
  end
  if state~="crafting" and state~="paused-immediate" and not(state=="nanite-tier-too-low" and tierCovered) then
   changed=true;reason=reason or ("节点状态: "..tostring(state))
  end
  if released and releasedAt and computer.uptime()-releasedAt>=3 then
   local output=call(RS,"getOutput",sides.top)
   local feedback
   if output~=0 then
    feedback="本脚本已放行，但暂停输出被改为 "..tostring(output).."；检查其他运行脚本或红石控制"
   elseif state=="paused-immediate" then
    feedback="本脚本暂停输出=0，节点仍立即暂停；检查其他控制仓收到的红石信号"
   end
   if feedback and (feedback~=lastFeedback or computer.uptime()>=feedbackAt) then
    print("放行核对: "..feedback)
    record.pipeline.feedback={reason=feedback,output=output,state=state,at=computer.uptime()}
    save(record.stage);lastFeedback=feedback;feedbackAt=computer.uptime()+15
   elseif not feedback then lastFeedback=nil;record.pipeline.feedback=nil end
  end
  if changed then
   if not halted then print("生产暂停: "..reason.."；已提交的供液申请继续核对，不重复下单。") end
   pause(15);released=false;halted=true
   if state=="idle" and record.pipeline.overlap then
    local used=call(NODE,"getConsumedCondensate");assert(type(used)=="table","节点空闲后消耗记录不可读")
    for name,n in pairs(lastRequired)do assert(integer(used[name] or 0)>=n,"节点进入空闲但凝聚物未消耗完: "..name)end
   end
  else
   lastRequired=req
  end
  return req
 end
 local plans={};for _,item in ipairs(items) do plans[#plans+1]={raw=item.raw,name=item.name,amount=item.amount,batch=item.batch} end
 record.plan=plans;record.expected=expected;record.secured=held;save("pipeline-planned")
 local converting=false
 local deadline=computer.uptime()+1800
 for _,item in ipairs(items) do deadline=deadline+math.ceil(item.amount/item.batch)*180 end
 local function jobsAndRequests()
  -- BEC_V1_CPU_WAIT_V1: wait for free CPUs; proven rejected requests use manual supply.
  local waits={};local waiting=false
  local function cpus()
   local ok,rows=pcall(call,MAIN,"getCpus")
   local info={free=0,busy=0,total=0,known=0,maxFree=0,maxBusy=0,max=0}
   if not ok or type(rows)~="table" then info.unknown=true;return info end
   for _,cpu in pairs(rows) do
    info.total=info.total+1
    if type(cpu)~="table" or type(cpu.busy)~="boolean" then info.unknown=true
    else
     if cpu.busy then info.busy=info.busy+1 else info.free=info.free+1 end
     local storage=cpu.storage
     if type(storage)=="number" and storage>=0 then
      info.known=info.known+1;info.max=math.max(info.max,storage)
      if cpu.busy then info.maxBusy=math.max(info.maxBusy,storage)
      else info.maxFree=math.max(info.maxFree,storage) end
     end
    end
   end
   return info
  end
  local function capacityFailure(reason)
   local s=tostring(reason):lower()
   return s:find("insufficient storage",1,true) or s:find("not enough storage",1,true)
    or s:find("storage too small",1,true) or s:find("insufficient capacity",1,true)
    or s:find("容量不足",1,true)
  end
  local function wait(item,reason,info)
   waiting=true
   waits[item.raw]={reason=reason,free=info and info.free,busy=info and info.busy,
    maxFree=info and info.maxFree,maxBusy=info and info.maxBusy,maxStorage=info and info.max}
  end
  -- Each deficit is independent: a rejected request cannot block other fluids.
  for _,item in ipairs(items) do
   if stopping then return true end
   local job,status=item.job,item.status
   if job and job.state=="submitted" then
    local computing
    if type(status.isComputing)=="function" then computing=status.isComputing() end
    local failed,why
    if type(status.hasFailed)=="function" then failed,why=status.hasFailed() end
    if computing==false and failed==true then
     job.state="rejected";job.preSubmissionFailed=true;job.failure=tostring(why)
     job.manualSupply=true;item.status=nil
     save("pipeline-request-rejected")
    elseif computing==true then
     wait(item,"AE 正在计算合成计划")
    else
     local canceled,why=status.isCanceled()
     assert(canceled==false,"主网原液申请失败/取消（未证实未启动，不重复下单）: "..tostring(why))
     local done=status.isDone();assert(type(done)=="boolean","AE 状态不可读")
     if done then job.state="done";item.doneAt=computer.uptime();save("pipeline-craft-done")
     else wait(item,"AE 合成进行中，继续收料") end
    end
   end
   local remaining=item.amount-item.initial-item.delivered
   if remaining>0 and (not job or job.state=="done" or job.state=="rejected")
    and (not item.doneAt or computer.uptime()-item.doneAt>=3) then
    local missing=math.max(0,remaining-(network(MAIN)[item.raw] or 0))
    if missing>0 then
     if job and job.state=="done" then
      assert(item.delivered>job.securedBefore,"原液合成已结束但没有收获，暂停核对竞争设备")
     end
     local info=cpus()
     local reason
     if job and job.state=="rejected" then
      if info.unknown then reason="申请未成功；CPU 状态暂不可读"
      elseif info.busy>0 then reason="申请未成功，CPU 被占用或容量/原料不足"
      elseif capacityFailure(job.failure) then reason="CPU 容量不足：AE 拒绝了这笔申请"
      else reason="AE 未启动申请：容量或原料待核对" end
      reason=reason.."；请在 ME 手动申请 "..missing.." mB；自动收料继续"
     elseif info.unknown then reason="等待 CPU 状态恢复可读"
     elseif info.total==0 or (info.known==info.total and info.max==0) then reason="CPU 容量不足：没有可用合成存储"
     elseif info.free==0 then reason="等待合成 CPU 空闲，其他供液与生产继续"
     end
     if reason then
      wait(item,reason,info)
      waits[item.raw].amount=missing;waits[item.raw].manual=job and job.manualSupply or nil
      waits[item.raw].failure=job and job.failure or nil
     end
     if not(job and job.manualSupply) and not info.unknown and info.free>0
      and not(info.known==info.total and info.max==0) then
      if not item.craft then
       local rows=call(MAIN,"getCraftables",{name=item.raw});assert(type(rows)=="table","原液配方不可读")
       local count=0;for _,craft in pairs(rows) do item.craft=craft;count=count+1 end
       assert(count==1,"原液配方缺失或不唯一: "..item.raw)
       local f=item.craft.getStack()
       assert(type(f)=="table" and f.name==item.raw and f.isCraftable==true and type(f.amount)=="number" and f.amount==f.size and f.hasTag==false,"未验证的流体合成对象")
      end
      missing=math.max(0,remaining-(network(MAIN)[item.raw] or 0))
      if missing>0 then
       item.attempts=item.attempts+1;assert(item.attempts<=3,"原液仍被争抢，保留已收获库存")
       job={raw=item.raw,unit="mB"};record.requests[#record.requests+1]=job
       job.amount=missing;job.state="pending";job.securedBefore=item.delivered
       item.job=job;save("craft-request-pending")
       local newStatus,why=item.craft.request(missing)
       assert(newStatus~=nil,"AE 申请未确认: "..tostring(why))
       item.status=newStatus;job.state="submitted";item.doneAt=nil
       save("pipeline-crafting");print("并行 AE 申请 "..item.raw.." "..missing.." mB")
       wait(item,"AE 正在计算合成计划",info)
      end
     end
    end
   end
  end
  local lines={}
  for raw,row in pairs(waits) do lines[#lines+1]={text=raw..": "..row.reason,
   urgent=row.reason:find("手动申请",1,true) or row.reason:find("容量不足",1,true)} end
  table.sort(lines,function(a,b)if not not a.urgent~=not not b.urgent then return not not a.urgent end;return a.text<b.text end)
  for i,row in ipairs(lines)do lines[i]=row.text end
  local summary=table.concat(lines,"；")
  if summary~=record.pipeline.cpuWaitSummary then
   record.pipeline.cpuWait=waits;record.pipeline.cpuWaitSummary=summary
   save(record.stage)
   if summary~="" then print("供液等待: "..summary) end
  end
  return waiting
 end

 while not stopping do
  productionGuard();local cpuWaiting=jobsAndRequests();if cpuWaiting then deadline=math.max(deadline,computer.uptime()+1800) end;if stopping then break end
  for _,item in ipairs(items) do
   if stopping then break end
   local remaining=item.amount-item.initial-item.delivered
   local amount=remaining>0 and math.floor(math.min(remaining,network(MAIN)[item.raw] or 0,2147483647)/item.batch)*item.batch or 0
   if amount>0 then
    local route=assert(ports[item.raw]);verifyBulk(route,item.raw);productionGuard()
    record.pending={raw=item.raw,amount=amount,address=route.address,from=route.from,to=route.to};save("transfer-pending")
    local ok,moved=call(route.address,"transferFluid",route.from,route.to,amount)
    record.transfers[#record.transfers+1]={raw=item.raw,ok=ok,amount=moved,requested=amount,address=route.address,from=route.from,to=route.to}
    save("transfer-returned");assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试")
    item.delivered=item.delivered+amount;record.pipeline.delivered[item.raw]=item.delivered
    record.pending=nil;save("pipeline-transfer-confirmed")
   end
  end
  if stopping then break end
  -- Read field before sub: conversion between reads can only lower this sum.
  local stock,sub=field(),network(SUB)
  for raw in pairs(sub) do assert(allowed[raw],"流水备料子网出现无关原液") end
  for name,n in pairs(base) do if not recipe[name] then assert((stock[name] or 0)==n,"无关凝聚物库存变化") end end
  local ready,hasRaw=true,false
  for _,item in ipairs(items) do
   local supplied=item.initial+item.delivered
   local liquid=integer(sub[item.raw] or 0);local condensate=integer(stock[item.name] or 0)
   assert(liquid+condensate<=supplied+(base[item.name] or 0),"流水备料库存超过已确认搬入量: "..item.raw)
   hasRaw=hasRaw or liquid>0
   if supplied<item.amount or liquid>0 or (item.job and item.job.state~="done" and not(item.job.state=="rejected" and item.job.preSubmissionFailed==true)) then ready=false end
  end
  local req=productionGuard()
  local funded=not halted
  local shortages={}
  if funded then
   local consumed=call(NODE,"getConsumedCondensate")
   assert(type(consumed)=="table","当前消耗记录不可读")
   for name,n in pairs(req) do
    local used=integer(consumed[name] or 0);assert(used<=n,"节点消耗超过当前需求")
    if (stock[name] or 0)<n-used then
     funded=false;shortages[#shortages+1]=name.." 缺 "..(n-used-(stock[name] or 0)).." mB"
    end
   end
  end
  if funded and not released then
   checkRecipe(req)
   record.pipeline.overlap=true;save("pipeline-production-release-pending")
   local releaseReq=productionGuard()
   if not halted and same(releaseReq,req) then pause(0);released=true;releasedAt=computer.uptime();save("pipeline-producing")
    print("当前配方材料已够，暂停输出已设0；节点运行状态持续核对，其余供液纠缠继续。") end
  elseif not funded and released then
   pause(15);released=false;save("pipeline-waiting-material")
   if #shortages>0 then print("生产等料: "..table.concat(shortages,"；").."；供液纠缠继续。") end
  end
  if ready and (halted or not funded) and (not converting or call(GEN,"isMachineActive")==false) then
   pause(15)
   if converting then generator(false) end
   record.plan=nil;record.pipeline=nil;record.productionOverlapHandled=true;record.expected={};record.secured={}
   save("stream-prepared");return {}
  end
  if hasRaw and not converting then
   productionGuard();save("pipeline-converting");generator(true);converting=true
   print("原液已到货，边收料边纠缠；当前配方够料即生产。")
  end
  assert(computer.uptime()<deadline,"流水备料超时，保留全部申请和搬液记录")
  tick(0.1)
 end
 return expected
end

-- BEC_V1_FAST_CYCLE_V1: batch IO reads and single-pass stage decisions.
-- BEC_V1_NANITES_STAGE_V2: let the node stall itself; exchange bees live.
local stageBusy=false
local stageSignature,stageCheckAt
local stageWorker
local originalStageTick=tick
serviceNaniteStage=function()
 if stageBusy or stopping or not record then return end
 local overlapping=record.pipeline and record.pipeline.overlap
 if record.stage~="watching" and not overlapping then return end
 local state=call(NODE,"getState")
 if state~="crafting" and state~="paused-immediate" and state~="nanite-tier-too-low" then return end
 local req=call(NODE,"getRequiredCondensate")
 local parallel=call(NODE,"getParallelRecipesInProgress")
 if type(req)~="table" or type(parallel)~="number" or parallel<1 then return end
 local normalized={};for name,n in pairs(req)do normalized[name]=integer(n)/parallel end
 local expected=overlapping and record.pipeline.recipe or perRecipe
 if not same(normalized,expected) then return end
 local required=call(NODE,"getRequiredTier")
 if type(required)~="table" or type(required.tier)~="number" then return end
 local signature=tostring(required.name)..":"..required.tier
 if signature==stageSignature and computer.uptime()<(stageCheckAt or 0) then return end
 if not stageWorker then
  local loader=assert(loadfile("/home/bec_nanites.lua","t",_ENV),"缺少蜂群模块")
  stageWorker=loader()
  assert(type(stageWorker)=="table" and type(stageWorker.needsSwitch)=="function" and stageWorker.passiveStages,
   "请先安装新版自动停顿换蜂模块")
 end
 stageSignature=signature;stageCheckAt=computer.uptime()+0.5
 if not stageWorker.fastStages then error("蜂群模块版本不匹配") end
 local current=call(NODE,"getProvidedTier");local count=call(NODE,"getAvailableNanites")
 if type(current)=="table" and current.name==required.name and current.tier==required.tier and type(count)=="number" and count>=64 then return end
 stageBusy=true
 local ok,reason=xpcall(function()
  -- Stage and consumption may advance while compatible bees keep working.
  -- Do not freeze those hints or drive node/GEN outputs to exchange bees.
  local function checked()
   if record.gateIntent then verifyGate(record.gateIntent.filters) end
  end
  local announced=false
  local function announce()
   checked();record.naniteStage={required=required,stage="switching"};save(record.stage)
   print("阶段换蜂：优先对应库存；等级不足由节点自动停顿");announced=true
  end
  stageWorker.ensure({passive=true,stage=true,beforeAction=announce,check=checked,tick=originalStageTick,stopping=function()return stopping end})
  checked()
  if announced then record.naniteStage=nil;save(record.stage) end
  local latest=call(NODE,"getRequiredTier")
  if type(latest)=="table" and latest.tier==required.tier and latest.name==required.name then
   stageSignature=signature;stageCheckAt=computer.uptime()+0.5
  else stageSignature=nil;stageCheckAt=0 end
 end,debug.traceback)
 stageBusy=false
 if not ok then error(reason) end
end
tick=function(seconds)
 originalStageTick(seconds)
 if not stopping then serviceNaniteStage() end
end

-- BEC_V1_BATCH_STOP_V1: latch work off before releasing each physical batch.
local function batchControlAddress(component)
 local candidates={}
 for address in component.list() do
  local methods=component.methods(address)
  if methods.getRequiredCondensate~=nil and methods.getParallelRecipesInProgress~=nil
   and methods.getState~=nil and methods.setWorkAllowed~=nil and methods.isWorkAllowed~=nil then
   candidates[#candidates+1]=address
  end
 end
 assert(#candidates==1,"需要唯一可启停的传送节点组件；请用适配器连接节点并提供 gt_machine（当前找到 "..#candidates.." 个）")
 return candidates[1]
end

local batchControl
local batchControlVerified=false
local function batchWork(enabled)
 batchControl=batchControl or batchControlAddress(c)
 if batchControlVerified and call(batchControl,"isWorkAllowed")==enabled then return end
 -- The generic gt_machine and bec_io_node must refer to the same physical node.
 assert(call(batchControl,"getState")==call(NODE,"getState"),"启停组件与传送节点状态不一致")
 assert(call(batchControl,"getParallelRecipesInProgress")==call(NODE,"getParallelRecipesInProgress"),"启停组件与节点并行不一致")
 local a,b=call(batchControl,"getRequiredCondensate"),call(NODE,"getRequiredCondensate")
 assert((a==nil and b==nil) or (type(a)=="table" and type(b)=="table" and same(a,b)),"启停组件与节点配方不一致")
 batchControlVerified=true
 if call(batchControl,"isWorkAllowed")~=enabled then
  record.batchStop={control=batchControl,enabled=enabled,phase="pending"};save(record.stage)
  call(batchControl,"setWorkAllowed",enabled)
  assert(call(batchControl,"isWorkAllowed")==enabled,"传送节点启停回读不符")
  record.batchStop.phase="confirmed";save(record.stage)
 end
end
local function batchBetween()
 -- Immediate pause is set before allowing an idle node to accept the next recipe.
 assert(call(RS,"getOutput",sides.top)==15,"接收下一批前必须立即暂停")
 batchWork(call(NODE,"getState")=="idle")
end
local continuousBatchPrepare=prepareStreaming
prepareStreaming=function(target)
 -- Beta 3 finishes the active batch with workAllowed=false but skips checkRecipe.
 batchWork(false)
 return continuousBatchPrepare(target)
end
local continuousBatchPause=pause
pause=function(value)
 if value==0 then batchWork(false) end
 return continuousBatchPause(value)
end

local function serve() local waiting={idle=true,["assembler-offline"]=true,unpowered=true,["nanite-tier-too-low"]=true}
local round=0 local nextCache=0 local function idleCache(state) if computer.uptime()<nextCache then return end nextCache=computer.uptime()+2 local pending=io.open("/home/bec_cache.journal","r") local old if pending then old=ser.unserialize(pending:read("*a"));pending:close() end
local incomplete=type(old)=="table" and old.background and old.incomplete -- BEC_V1_IDLE_CACHE_FAST_V2
if state~="idle" and not incomplete then
 local safe={['assembler-offline']=true,unpowered=true,['nanite-tier-too-low']=true,['paused-immediate']=true}
 if not safe[state] then return end
 local req=call(NODE,"getRequiredCondensate")
 if type(req)=="table" and next(req)~=nil then return end
end local input=io.open("/home/bec_cache.config","r") local settings if input then settings=ser.unserialize(input:read("*a"));input:close() end if not settings and not incomplete then if not fs.exists("/home/bec/recipes") then return end settings={version=1,target=144000}
end assert(not settings or (type(settings)=="table" and settings.version==1),"缓存配置无效") local target=incomplete and old.fixedStock or settings.target assert(type(target)=="number" and target>=1 and target==math.floor(target),"缓存配置无效") local worker,reason=loadfile("/home/bec_cache.lua","t",_ENV) assert(worker,"缺少后台缓存脚本："..tostring(reason)) waitUntil(190,function() return call(GEN,"isMachineActive")==false end) save("cache-working")
local ok,err=worker("background-stock",target) assert(ok,"后台缓存停止："..tostring(err)) record.lastState=nil;save("waiting") tick(0.1) end while not stopping do pause(15); generator(false) batchBetween()
    local state=call(NODE,"getState")
idleCache(state) if stopping then break end state=call(NODE,"getState") if state=="paused-immediate" or state=="nanite-tier-too-low" then switchNanites();state=call(NODE,"getState") end if waiting[state] then if state~=record.lastState then print("等待订单/机器就绪: "..state.."；任意数量同配方订单均可，按 Q 停止。") record.lastState=state;save("waiting") end
field();tick(0.1) else waitUntil(10,function() local v=call(NODE,"getState") return v=="paused-immediate",v end,function(v) assert(v=="crafting" or waiting[v],"无法暂停，实际状态: "..tostring(v)) field()
end) switchNanites();if stopping then break end record.required,record.remaining=current() local target,count=batchTarget(record.required,record.remaining) local stable=false for i=1,100 do tick(0.05);unchanged() local nextTarget,nextCount=batchTarget(record.required,record.remaining) if same(target,nextTarget) then stable=true;break end
target,count=nextTarget,nextCount end assert(stable,"主网任务清单持续变化，保持暂停") if stopping then break end record.batchCount=count;record.windowed=true print("本轮备料配方 "..count.." 份；当前实际并行 "..checkRecipe(record.required) .."；按安全批量备料，大订单自动接续。") round=round+1;record.round=round;record.transfers={};record.target=target;record.plan=nil;record.topups={}
waitUntil(10,function() return call(GEN,"isMachineActive")==false end) emptyConfig();tanks(4,nil);tanks(5,nil) local filters=configureGate(record.required) unchanged() if stopping then break end local expected=prepareStreaming(target) if record.productionOverlapHandled then record.productionOverlapHandled=nil else  if stopping then break end if record.pipelineComplete then unchanged();assert(next(network(SUB))==nil,"流水转换后子网非空");record.pipelineComplete=nil else for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.05) end end
save("converting");generator(true) local conversionLimit=180 for name,need in pairs(target) do conversionLimit=conversionLimit+math.ceil(need/(units[name] or 144))*180 end waitUntil(conversionLimit,function() local stock=field() for name,need in pairs(target) do if (stock[name] or 0)<need then return false end end return true end,unchanged)
unchanged();generator(false) record.plan=nil;record.lastState=nil;save("watching") if not stopping then verifyGate(filters);unchanged() pause(0) print("本轮备料齐备，已连续放行；库存不足时自动准备下一批。按 Q 停止。") local releasedAt=computer.uptime() local deadline=releasedAt+600
local lastStock=field() local lastRequired=record.required local nextQueueCheck=0 local windowQueue
while not stopping do local v=call(NODE,"getState") local stock=field() local req=call(NODE,"getRequiredCondensate") verifyGate(filters)
local needed=call(NODE,"getRequiredTier");needed=type(needed)=="table" and needed.tier or needed local supplied=call(NODE,"getProvidedTier");local available=call(NODE,"getAvailableNanites")
if type(needed)=="number" and (type(supplied)~="table" or type(supplied.tier)~="number" or supplied.tier<needed or type(available)~="number" or available<64) then pause(15);waitUntil(10,function() local s=call(NODE,"getState");return s=="paused-immediate" or s=="nanite-tier-too-low" end)
switchNanites();if stopping then break end
print("蜂群需求变化，保持暂停，重新核对当前配方过滤和库存。")
break end
local parallel if req~=nil then parallel=integer(call(NODE,"getParallelRecipesInProgress")) local matching=parallel>0 for name,n in pairs(req) do if not perRecipe[name] or n~=perRecipe[name]*parallel then matching=false end end for name in pairs(perRecipe) do if req[name]==nil then matching=false end end if not matching then pause(15);break end if not same(gateFilters(req),filters) then pause(15);break end
lastRequired=req end if v=="idle" then
 pause(15)
 local consumed=call(NODE,"getConsumedCondensate")
 local incomplete=type(consumed)~="table"
 if not incomplete then for name,need in pairs(lastRequired) do
  local used=consumed[name] or 0
  if type(used)~="number" or used<need then incomplete=true end
 end end
 record.lastOutcome={required=lastRequired,consumed=consumed,
  status=incomplete and "unconfirmed-or-skipped" or "consumed"}
 save("waiting")
 if incomplete then print("节点已空闲，旧轮次消耗未确认；记录后继续等待当前订单，不重放旧配方。") end
 break end if waiting[v] then break end assert(v=="crafting" or (v=="paused-immediate" and computer.uptime()-releasedAt<3), "节点运行异常: "..tostring(v)) local refill=false
if req~=nil then
 if computer.uptime()>=nextQueueCheck then windowQueue=queuedRecipes();nextQueueCheck=computer.uptime()+1 end
 local consumed=call(NODE,"getConsumedCondensate")
 assert(type(consumed)=="table","当前消耗记录不可读")
 refill=needsRefill(req,consumed,stock,windowQueue)
 if refill then
  windowQueue=queuedRecipes()
  refill=needsRefill(req,consumed,stock,windowQueue)
 end
end
if refill then break end if not same(stock,lastStock) then deadline=computer.uptime()+600;lastStock=stock end assert(computer.uptime()<deadline,"当前配方运行超时") tick(0.1) end
end end end end pause(15);generator(false);batchWork(false);record.configOwned=false for _,job in ipairs(record.requests) do if job.state~="done" then save("craft-paused") print("服务已暂停；主网原液申请仍需核对，保留日志，不重复下单。")
return end end save("stopped") print("已停止常驻服务：暂停输出 15，纠缠装置关闭；约束场与已有凝聚物保持开启。") end local function main() assert(mode=="preview" or mode=="run" or mode=="resume" or mode=="restock" or mode=="reset", "用法: preview / run / resume / restock / reset，无需填写数量")
RS = resolve("266f65b5", "redstone") GEN = resolve("c1ae3f7c", "gt_machine") GATE = resolve(GATE_ADDRESS, "bec_diode") assert(call(GEN, "getName") == "multi.bec.generator", "纠缠装置名称不符") for _, item in ipairs({{RS,"setOutput"},{RS,"getOutput"},{GEN,"setWorkAllowed"}, {GEN,"isWorkAllowed"},{GEN,"isMachineActive"},{MAIN,"getFluidsInNetwork"}, {MAIN,"setFluidInterfaceConfiguration"},{MAIN,"getFluidInterfaceConfiguration"}, {SUB,"getFluidsInNetwork"},{TRANS,"transferFluid"},
{MAIN,"getCraftables"},{MAIN,"getCpus"},{GATE,"getCondensateFilterCount"}, {GATE,"getCondensateFilters"},{GATE,"setCondensateFilters"}, {GATE,"isWorkAllowed"},{GATE,"isMachineActive"}}) do method(item[1],item[2]) end local minimum,maximum=integer(call(NODE,"getMinParallel")),integer(call(NODE,"getMaxParallel")) assert(minimum>=1 and maximum>=minimum,"节点并行设置无效") print("远端红石: " .. RS .. "；纠缠装置: " .. GEN) print("节点: " .. call(NODE,"getState") .. "；向上输出: " .. call(RS,"getOutput",sides.top)) print("纠缠装置允许工作: " .. tostring(call(GEN,"isWorkAllowed")))
print("麦克斯韦门: "..GATE.."；过滤: "..ser.serialize(call(GATE,"getCondensateFilters"),false) .."；运行: "..tostring(call(GATE,"isMachineActive"))) print("凝聚物库存: " .. ser.serialize(field(),false)) if mode == "preview" then print("子网原液: " .. ser.serialize(network(SUB),false)) if call(NODE,"getState") == "paused-immediate" then local required,remaining=current();local target,count=batchTarget(required,remaining) print("本轮备料配方 "..count.." 份")
plan(target) end print("预览结束：没有开关、搬液、配置或写日志。") return end local waitingStates = {idle=true, ["paused-immediate"]=true, ["assembler-offline"]=true, unpowered=true, ["nanite-tier-too-low"]=true} local initialState = call(NODE,"getState")
assert(waitingStates[initialState], "节点状态不适合启动: " .. tostring(initialState)) emptyConfig(); tanks(4,nil); tanks(5,nil)
-- BEC_V1_NEXT_RECIPE_V1: explicit reset detaches settled historical rounds.
if mode=="reset" then
 assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false
  and call(GEN,"isMachineActive")==false,"重置前保持节点暂停、纠缠装置停机")
 assert(next(network(SUB))==nil,"重置前子网仍有原液，不能忽略在途物料")
 field()
 local archives={}
 for _,entry in ipairs({{JOURNAL,"continuous"},{"/home/bec_cache.journal","cache"}}) do
  local path,kind=entry[1],entry[2]
  if fs.exists(path) then
   local f=assert(io.open(path,"r"));local text=f:read("*a");f:close()
   local old=ser.unserialize(text)
   assert(type(old)=="table" and old.version==1 and old.kind==kind
    and old.pending==nil and old.configOwned==false,"重置日志有未确认操作: "..path)
   assert(type(old.requests)=="table" and type(old.transfers)=="table","重置日志操作清单缺失")
   for _,job in pairs(old.requests) do
    assert(type(job)=="table" and job.state=="done","旧原液申请仍在进行，不重复下单")
   end
   for _,move in pairs(old.transfers) do
    assert(type(move)=="table" and move.ok==true and integer(move.amount)>0
     and move.requested==move.amount,"旧搬液结果未完整确认")
   end
   local n=1;while fs.exists(path..".reset-"..n) do n=n+1 end
   archives[#archives+1]={path=path,backup=path..".reset-"..n,text=text}
  end
 end
 -- Validate both journals before archiving either. No old requests are replayed.
 for _,a in ipairs(archives) do
  assert(fs.rename(a.path,a.backup),"重置日志归档失败: "..a.path)
  local f=assert(io.open(a.backup,"r"));local text=f:read("*a");f:close()
  assert(text==a.text and not fs.exists(a.path),"重置归档回读不符")
  print("旧日志已保留: "..a.backup)
 end
 print("进程已重置，按当前订单和实际库存重新计算；蜂群及已有凝聚物保留。")
 mode="run"
end

if fs.exists(JOURNAL) then local f=assert(io.open(JOURNAL,"r"));local contents=f:read("*a");f:close() local old=ser.unserialize(contents); assert(not(type(old)=="table" and old.naniteStage),"旧阶段换蜂未确认完成，保留蜂群与生产日志，禁止重放")
if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then
 assert(mode=="resume" or mode=="restock","流水未完成，请用resume核对")
 assert(old.pending==nil and old.configOwned==false,"流水存在未确认搬液，保留日志核对")
 for _,job in ipairs(old.requests or {})do assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"原液申请尚未确认完成，禁止重复下单")
  if job.manualSupply then
   local received=integer((old.pipeline.delivered or {})[job.raw] or 0)-integer(job.securedBefore or 0)
   local available=integer(network(MAIN)[job.raw] or 0)
   assert(received+available>=integer(job.amount),"手动补料尚未收齐：继续等待手动任务完成后再恢复，禁止自动重复下单")
  end
end
 for _,move in ipairs(old.transfers or {})do assert(move.ok==true and move.amount==move.requested and integer(move.amount)>0,"搬液未完整确认")end
 assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"恢复前节点须暂停且纠缠装置停机")
 resolveRawNames(old.target)
 local p=old.pipeline
 assert(type(p.base)=="table" and type(p.initial)=="table" and type(p.delivered)=="table","流水守恒记录缺失")
 local stock,sub=field(),network(SUB);local allowed={};local completed
 local req=call(NODE,"getRequiredCondensate");local consumed=call(NODE,"getConsumedCondensate")
 local normalized={};local parallel=call(NODE,"getParallelRecipesInProgress")
 if type(req)=="table" and type(parallel)=="number" and parallel>0 then for name,n in pairs(req)do normalized[name]=integer(n)/parallel end end
 -- BEC_V1_IDLE_RECOVERY_V1: Beta 3 keeps the last consumed table when idle.
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
 end
 for _,item in ipairs(old.plan)do
  local raw,name=item.raw,item.name;assert(mapping[name]==raw,"恢复原液映射变化");allowed[raw]=true
  local budget=integer(p.base[name] or 0)+integer(p.initial[raw] or 0)+integer(p.delivered[raw] or 0)
  local loss=budget-integer(stock[name] or 0)-integer(sub[raw] or 0)
  if p.overlap then
   assert(type(p.recipe)=="table" and type(p.startConsumed)=="table" and type(consumed)=="table","并行消耗记录缺失")
   local used=(sameRecipe or idleRetained) and integer(consumed[name] or 0) or 0
   if not sameRecipe and not idleRetained then for _,n in pairs(consumed)do assert(integer(n)==0,"下一配方已有消耗，须核对旧流水")end end
   local batches=(loss+integer(p.startConsumed[name] or 0)-used)/assert(p.recipe[name])
   assert(loss>=0 and batches>=0 and batches%1==0 and (completed==nil or completed==batches),"生产消耗与流水库存不守恒: "..raw)
   completed=batches
  else assert(loss==0,"流水库存不守恒: "..raw)end
 end
 for name,n in pairs(p.base)do if not allowed[mapping[name]]then assert((stock[name] or 0)==n,"无关凝聚物变化")end end
 for raw in pairs(sub)do assert(allowed[raw],"子网有无关原液")end
 -- Drain only confirmed material before archiving; never repeat a request/move.
 local total={};for _,item in ipairs(old.plan)do total[item.name]=integer(stock[item.name] or 0)+integer(sub[item.raw] or 0)end
 local ok,reason=pcall(function()
  if next(sub)~=nil then
   generator(true);local deadline=computer.uptime()+1800
   while next(network(SUB))~=nil or call(GEN,"isMachineActive")==true do
    assert(not stopping and computer.uptime()<deadline,"恢复转换未完成，原日志保留")
    assert(call(RS,"getOutput",sides.top)==15,"恢复转换时节点意外放行")
    field()
    tick(0.1)
   end
  end
  local final=field();for name,n in pairs(total)do assert((final[name] or 0)==n,"恢复转换不守恒")end
 end)
 generator(false);assert(ok,reason)
 if idleAudit then
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
 old.stage="watching";old.plan=nil;old.pipeline=nil
 print("并行生产消耗核对通过；已确认余液转换完成，按真实库存继续，不重复下单搬液。")
end

local streaming=type(old)=="table" and type(old.plan)=="table" and (old.stage=="stream-configuring" or old.stage=="stream-transfer-confirmed" or old.stage=="stream-inlet-cleared" or old.stage=="stream-planned")
and type(old.secured)=="table" and type(old.target)=="table" assert(type(old)=="table" and old.version==1 and old.kind=="continuous" and old.pending==nil and (old.configOwned==false or streaming),"日志无效或有未确认操作，禁止重跑") if mode=="resume" or mode=="restock" then -- BEC_V1_CACHE_RESUME_V3
if old.stage == "cache-working" then
  assert(old.plan == nil, "缓存恢复：旧生产仍有备料计划，保留日志核对")
  assert(old.pending == nil and old.configOwned == false
    and type(old.requests) == "table" and type(old.transfers) == "table",
    "缓存恢复：旧生产仍有未确认操作，保留日志核对")
  for _, job in pairs(old.requests) do
    assert(type(job) == "table" and job.state == "done", "缓存恢复：旧生产申请未确认完成")
  end
  for _, move in pairs(old.transfers) do
    assert(type(move) == "table" and move.ok == true and type(move.amount) == "number"
      and move.amount > 0 and move.amount == math.floor(move.amount)
      and move.requested == move.amount, "缓存恢复：旧生产搬液未完整确认")
  end
  -- expected/secured describe the prior production round, not live inventory.
  local cf = assert(io.open("/home/bec_cache.journal", "r"), "缓存恢复：缺少缓存日志")
  local cache = ser.unserialize(cf:read("*a")); cf:close()
  assert(type(cache) == "table" and cache.version == 1 and cache.kind == "cache"
    and cache.background == true and cache.stage == "stopped"
    and cache.incomplete == false and cache.pending == nil and cache.configOwned == false,
    "缓存恢复：缓存尚未确认完成，保留日志核对")
  assert(type(cache.requests) == "table" and type(cache.transfers) == "table",
    "缓存恢复：缓存操作记录缺失")
  for _, job in pairs(cache.requests) do
    assert(type(job) == "table" and job.state == "done", "缓存恢复：申请尚未完成")
  end
  for _, move in pairs(cache.transfers) do
    assert(type(move) == "table" and move.ok == true and type(move.amount) == "number"
      and move.amount > 0 and move.amount == math.floor(move.amount)
      and move.requested == move.amount, "缓存恢复：搬液未完整确认")
  end
  local safeStates = {idle=true, ["paused-immediate"]=true,
    ["nanite-tier-too-low"]=true, ["assembler-offline"]=true, unpowered=true}
  assert(safeStates[call(NODE, "getState")] and call(RS, "getOutput", sides.top) == 15
    and call(GEN, "isWorkAllowed") == false and call(GEN, "isMachineActive") == false,
    "缓存恢复：节点须暂停且纠缠装置已停机")
  assert(next(network(SUB)) == nil, "缓存恢复：子网仍有原液，保留日志核对")
  assert(type(cache.target) == "table" and next(cache.target) ~= nil,
    "缓存恢复：缺少本轮目标")
  local stock = field()
  for name, amount in pairs(cache.target) do
    integer(amount)
    assert((stock[name] or 0) >= amount, "缓存恢复：实际库存未达本轮目标: " .. name)
  end
  -- Normalize only in memory. The existing archive keeps the original journal.
  old.stage = "waiting"
  print("后台缓存完成核对通过；归档旧生产日志后按实际库存继续，不重放旧搬液或申请。")
end

local stopped=old.stage=="stopped" and old.plan==nil and type(old.transfers)=="table" local preTransfer=(old.stage=="starting" or old.stage=="waiting" or old.stage=="waiting-stock") and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil and (old.requests==nil or next(old.requests)==nil)
local watching=(old.stage=="watching" or old.stage=="waiting") and old.plan==nil and type(old.transfers)=="table" and type(old.target)=="table" local crafted=old.stage=="craft-done" and old.plan==nil and type(old.transfers)=="table" and next(old.transfers)==nil and type(old.requests)=="table" and next(old.requests)~=nil local prepared=old.stage=="stream-prepared" and old.plan==nil and type(old.expected)=="table" and type(old.transfers)=="table" and type(old.target)=="table"
local converting=old.stage=="converting" and old.plan==nil and type(old.expected)=="table" and type(old.transfers)=="table" and type(old.target)=="table" and type(old.required)=="table" and type(old.remaining)=="table" if stopped or watching or crafted or prepared or converting or streaming then for _,move in ipairs(old.transfers) do assert(move.ok==true and type(move.amount)=="number" and move.amount>0, "旧搬运未确认，禁止恢复") end
for _,job in ipairs(old.requests or {}) do assert(job.state=="done","原液申请未完成，禁止重复申请") end assert(call(RS,"getOutput",sides.top)==15 and call(GEN,"isWorkAllowed")==false and call(GEN,"isMachineActive")==false,"恢复前节点须暂停且纠缠装置已停机") if streaming then local req,remaining=current(true) assert(same(req,old.required) and same(remaining,old.remaining),"供液恢复订单变化，暂停核对")
assert(same(network(SUB),old.secured),"已确认搬运与子网库存不符，禁止恢复") resolveRawNames(old.target) local expected,stock={},field() for name,need in pairs(old.target) do local unit=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/unit)*unit local raw=mapping[name];if amount>0 then expected[raw]=amount end local held=old.secured[raw] or 0
assert(held<=amount and held%unit==0,"供液恢复子网超额或非整批") end for raw in pairs(old.secured) do assert(expected[raw],"供液恢复子网有无关原液") end print("供液恢复核对通过；保留已搬入原液，只补当前缺口。") end if crafted then local req,remaining=current(true) assert(same(req,old.required) and same(remaining,old.remaining),"旧申请订单已变化，暂停核对")
print("已完成原液申请已归档；按当前真实库存重新计算缺口。") end if prepared then current(true) assert(same(network(SUB),old.expected),"已备齐原液与日志不符，暂停核对") print("整批原液已在子网，恢复时抵扣，不重复搬料或申请。") end if converting then
local req,remaining=current(true) resolveRawNames(old.target) local target=old.target if not (same(req,old.required) and same(remaining,old.remaining)) then local count;target,count=batchTarget(req,remaining) assert(type(old.batchCount)=="number" and (old.windowed==true or count<=old.batchCount), "恢复时订单增加或旧批量缺失，暂停核对") for name,need in pairs(target) do assert(need<=integer(old.target[name]),"恢复需求超过旧整批目标") end
print("实际并行/消耗已变化，按 AE 剩余订单扣除节点已消耗量核对库存。") end local sub,stock=network(SUB),field() for name,value in pairs(target) do local raw=mapping[name] local need=integer(value) local liquid,condensate=integer(sub[raw] or 0),integer(stock[name] or 0) local unit=units[name] or 144
assert(liquid%unit==0 and condensate%unit==0 and (liquid+condensate==need or (mode=="restock" and liquid+condensate<need)), "转换恢复库存不符: "..raw.."；子网 "..liquid.." + 凝聚物 "..condensate.."，目标 "..need) if liquid+condensate<need then print(raw.." 当前缺口 "..(need-liquid-condensate).." mB；归档旧操作后重新备料。") end end for raw in pairs(sub) do local allowed=false;for _,known in pairs(mapping) do if known==raw then allowed=true end end assert(allowed,"转换恢复子网有无关原液")
end for name,n in pairs(stock) do assert(n==0 or mapping[name],"转换恢复有无关凝聚物") end print("转换恢复核对通过，抵扣当前库存；已完成的旧申请和搬运记录保留归档。") end end assert(stopped or preTransfer or watching or crafted or prepared or converting or streaming,"该阶段存在未确认操作，不能自动恢复") archiveJournal(contents,".before-resume-") else
assert(old.stage=="stopped","已有非正常停止日志，请核对后使用 resume，禁止盲目重跑") for _,job in ipairs(old.requests or {}) do assert(job.state=="done","旧日志有未确认的主网申请，禁止重新下单") end archiveJournal(contents) end else assert(mode~="resume" and mode~="restock","没有可恢复的日志")
end record={version=1,kind="continuous",stage="starting",transfers={},requests={},configOwned=false} save("starting");armed=true print("常驻模式：无需填写数量。先只提交原始屏蔽层任务，可先 5 再 10。") print("按主网剩余任务分批备料，整个AE订单保留；库存不足自动接续。") serve() end local ok, err = xpcall(main, debug.traceback)
if not ok then if armed then local paused = pcall(pause,15) local stopped = pcall(generator,false) local cleaned = true if record and record.configOwned then local success, result = pcall(call,MAIN,"setFluidInterfaceConfiguration",0) cleaned = success and result == true
end print("恢复暂停: " .. tostring(paused) .. "；关闭纠缠装置: " .. tostring(stopped) .. "；清供液配置: " .. tostring(cleaned)) if not paused then print("请手动提供控制仓暂停信号。") end end print("程序停止: " .. tostring(err)) print("保留现场与日志；不要删除日志盲目重跑。约束场保持开启。") end

-- BEC_V1_BEE_GUARD_V2
]========],
["bec_bee_restart.lua"]=[========[-- Restart only the installed whole-cell nanite exchange after manual ME IO repair.
local mode=(...)or 'restart'
assert(mode=='restart' or mode=='reset' or mode=='check','用法：restart / reset / check')
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local T='13070035-3a3f-4468-b896-1c084288fdc9';local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local PAUSE='266f65b5-20be-4543-8f2f-bfd2d0816611';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local SOUTH='4e31083a-e153-40e4-bf3f-e5ada363819d';local NORTH='4bfbed4a-5d62-4311-9d34-5761103e76ce'
local PATH='/home/bec_nanites_io.journal';local AUTO='/home/bec_auto.journal'
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(p)local f=io.open(p,'r');if not f then return end;local t=f:read('*a');f:close();return t end
local function write(p,t)local f=assert(io.open(p,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(p)==t,'写入回读失败: '..p)end
local function decode(text)local t=ser.unserialize(text);assert(type(t)=='table','运行记录不可读');return t end
local function replace(path,expected,text,backup)
 local temp=backup..'.new';local replaced=backup..'.replaced';write(temp,text)
 assert(read(path)==expected,'替换前记录变化: '..path)
 if expected then assert(fs.rename(path,replaced),'原记录归档失败')end
 if not fs.rename(temp,path)then
  if expected then assert(fs.rename(replaced,path),'原记录还原失败')end
  error('状态替换失败，已保留原记录')
 end
 assert(read(path)==text,'状态替换回读失败')
end
local function whole(n)return type(n)=='number'and n>=0 and n%1==0 end
local function hive()
 local n=call(NODE,'getAvailableNanites');assert(whole(n),'蜂群仓读数不可读')
 local p=call(NODE,'getProvidedTier')
 if n>0 then assert(type(p)=='table'and whole(p.tier)and type(p.name)=='string','蜂群仓类型不可读')end
 return {reading=n,tier=n>0 and p.tier or nil,family=n>0 and p.name or nil}
end
local function stopped()
 assert(call(PAUSE,'getOutput',1)==15,'先按Q退出UI，再运行此命令')
 assert(call(GEN,'isWorkAllowed')==false and call(GEN,'isMachineActive')==false,'先等纠缠装置关闭且停稳')
 local state=call(NODE,'getState')
 assert(state=='paused-immediate' or state=='nanite-tier-too-low' or state=='idle' or state=='assembler-offline' or state=='unpowered','节点还在生产，先退出UI暂停')
end
local function ports()
 local occupied={}
 for _,side in ipairs({2,3})do
  assert(call(T,'getInventoryName',side)=='tile.appliedenergistics2.BlockIOPort'and call(T,'getInventorySize',side)==12,'南北ME IO布局不符')
  for slot=1,12 do
   local item=call(T,'getStackInSlot',side,slot)
   if item then
    local label=(side==2 and '北面回收' or '南面装入')..'IO第'..slot..'槽'
    print(label..'：'..tostring(item.name)..'；盘内数量 '..tostring(item.storedItemCount))
    occupied[#occupied+1]=label
   end
  end
 end
 return occupied
end
local function low()
 for _,rs in ipairs({SOUTH,NORTH})do for side=0,5 do assert(call(rs,'getOutput',side)==0,'ME IO红石未关闭')end end
end
local ownsPorts=false
local function main()
 stopped()
 local ioText=read(PATH);local old=ioText and decode(ioText)
 assert(not old or old.version==2 and old.kind=='cell-io','这不是当前整盘换蜂日志')
 local autoText=read(AUTO);local auto=autoText and decode(autoText)
 if auto and auto.naniteStage then assert(type(auto.naniteStage)=='table'and auto.naniteStage.stage=='switching','不是可重开的阶段换蜂标记')end
 if mode=='check'then
  print('旧换蜂阶段：'..tostring(old and old.stage)..'；蜂群仓读数 '..hive().reading)
  ports();print('只读检查完成；没有重置或搬盘。');return
 end
 -- Backup before changing control outputs. Never replay the old pending move.
 local n=1
 while fs.exists(PATH..'.before-restart-'..n)or fs.exists(AUTO..'.before-bee-restart-'..n)do n=n+1 end
 local backup=PATH..'.before-restart-'..n
 if ioText then write(backup,ioText)end
 if auto and auto.naniteStage then write(AUTO..'.before-bee-restart-'..n,autoText)end
 ownsPorts=true
 for _,rs in ipairs({SOUTH,NORTH})do for side=0,5 do
  if call(rs,'getOutput',side)~=0 then call(rs,'setOutput',side,0)end
 end end
 low()
 local occupied=ports()
 assert(#occupied==0,'两端IO已关闭。请把 '..table.concat(occupied,'、')..' 的盘取回底部箱子前10格，再运行同一命令；旧日志未清除')
 local before=hive();os.sleep(.25);stopped();low()
 assert(#ports()==0,'检查期间端口出现盘，请停止其他搬盘程序')
 local after=hive();assert(before.reading==after.reading and before.tier==after.tier and before.family==after.family,'蜂群仍在变化，等端口停稳再运行')
 assert(read(PATH)==ioText and read(AUTO)==autoText,'检查期间日志变化，请退出其他自动化程序')
 local holding=old and old.holding
 if not(holding and before.reading<30720 and holding.count==before.reading and holding.family==before.family and holding.tier==before.tier)then holding=nil end
 local fresh={version=2,kind='cell-io',stage='done',holding=holding,
  exchangeRestart={kind='manual-restored-ports',backup=ioText and backup or nil,hive=before,
   abandonedStage=old and old.stage,abandonedPending=old and old.pending}}
 replace(PATH,ioText,ser.serialize(fresh,false),backup)
 if auto and auto.naniteStage then auto.naniteStage=nil;replace(AUTO,autoText,ser.serialize(auto,false),AUTO..'.before-bee-restart-'..n)end
 print('蜂群换盘状态已重置；旧记录备份：'..(ioText and backup or '原来没有日志'))
 if mode=='restart'then
  local module=assert(loadfile('/home/bec_nanites.lua','t',_ENV),'找不到已安装蜂群模块')()
  assert(type(module)=='table'and type(module.ensure)=='function','蜂群模块入口不符')
  print('重新读取当前需求和箱内存储盘，开始换蜂。')
  module.ensure({stage=true})
  local current=hive()
  print('换蜂检查完成；蜂群仓读数 '..current.reading..' / T'..tostring(current.tier))
  if current.reading<64 then print('蜂群尚不足64个；把满足当前等级的蜂群盘放在底部箱子前10格，再运行本命令。')end
 end
 print('返回自动化：lua /home/bec_ui.lua resume')
end
local ok,why=xpcall(main,debug.traceback)
if not ok then
 -- The installed module owns any new transfer journal. Only turn its ports off.
 if ownsPorts then for _,rs in ipairs({SOUTH,NORTH})do for side=0,5 do
  pcall(function()if call(rs,'getOutput',side)~=0 then call(rs,'setOutput',side,0)end end)
 end end end
 print('换蜂重开待处理：'..tostring(why))
end
return ok,why
]========],
["bec_cache.config"]=[========[{version=1,target=5000000,overrides={}}
]========],
["bec_cache.lua"]=[========[local c = require("component") local ser = require("serialization") local computer = require("computer")
local fs = require("filesystem") local sides = require("sides") local event = require("event")
local mode, cacheCopies = ... mode=mode or "preview" local fixedStock -- BEC_V1_CACHE_CUSTOM_V1
local overrides={}
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
assert(loadfile("/home/bec_history.lua"))().prune(JOURNAL..(suffix or ".stopped-"),2)

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
-- BEC_V1_CACHE_FAST_V2
local productionOutputs,priorityAt,priorityQueued={},-math.huge,false
local unknownReported=false
local function productionWaiting()
 if not background then return false end
 local state=call(NODE,"getState")
 if state~="idle" then
  local req=call(NODE,"getRequiredCondensate")
  if (type(req)=="table" and next(req)~=nil) or state=="crafting" or state=="paused-step" then
   print("后台缓存让位：节点有配方，优先生产。")
   return true
  end
 end
 if computer.uptime()<priorityAt then return priorityQueued end
 priorityAt=computer.uptime()+1;priorityQueued=false
 local cpus=call(MAIN,"getCpus");assert(type(cpus)=="table","主网 CPU 状态不可读")
 for _,cpu in pairs(cpus) do if cpu.busy==true then
  for _,getter in ipairs({"activeItems","pendingItems"}) do
   local ok,rows=pcall(function()return cpu.cpu[getter]()end)
   if not ok or type(rows)~="table" then
    if not unknownReported then print("AE CPU任务列表不可读；未确认为配方，空闲补库继续。") end
    unknownReported=true
   else for _,item in pairs(rows) do
    local key=tostring(item.name)..":"..tostring(tonumber(item.damage or 0))
    if productionOutputs[key] and (item.size or item.amount or 0)>0 then priorityQueued=true end
   end end
  end
 end end
 if priorityQueued then print("后台缓存让位：AE队列有登记配方，优先生产。") end
 return priorityQueued
end

local function prepareStreaming(target) local ports=bulkPorts() local stock,previous=field(),network(SUB)
local expected,raws={},{}

local priority=false
local function handoff()
 for _,job in ipairs(record.requests) do assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"缓存申请尚未完成，不能交回生产") end
 for raw,n in pairs(previous) do
  local known=false;for name in pairs(target) do if mapping[name]==raw then known=true;assert(integer(n)%(units[name] or 144)==0,"已搬缓存不是整批") end end
  assert(known,"交回生产前子网有无关原液")
 end
 for name in pairs(target) do target[name]=(stock[name] or 0)+(previous[mapping[name]] or 0) end
 expected=previous;record.target=target;record.expected=previous;record.secured=previous;record.plan=nil
 record.yieldedToRecipe=true;save("stream-prepared")
 print("已有配方，停止补缓存；仅转换已搬入原液后交回生产。")
 return previous
end
if productionWaiting() then return handoff() end

for name,need in pairs(target) do local raw=mapping[name]
local batch=units[name] or 144 local amount=math.ceil(math.max(0,need-(stock[name] or 0))/batch)*batch local existing=previous[raw] or 0
assert(amount==0 or ports[raw],"缺少高速供液口："..raw.."；禁止普通接口回退")
assert(existing<=amount and existing%batch==0,"子网原液超额或非整批: "..raw) if amount>0 then expected[raw]=amount end raws[#raws+1]={raw=raw,amount=amount,batch=batch}
end for raw in pairs(previous) do local allowed=false
for _,item in ipairs(raws) do if item.raw==raw then allowed=true end end assert(allowed,"子网有无关原液: "..raw) end
for name,amount in pairs(stock) do assert(amount==0 or mapping[name],"约束场有未知凝聚物") end table.sort(raws,function(a,b) return a.raw<b.raw end) record.plan=raws;record.expected=expected;record.secured=previous;save("stream-planned")
for _,item in ipairs(raws) do if productionWaiting() then return handoff() end local raw,need,batch=item.raw,item.amount,item.batch local route=ports[raw]
local chunk=math.floor(2147483647/batch)*batch local function bufferedInlet() return 0 end if (previous[raw] or 0)<need then
unchanged();emptyConfig();tanks(4,nil) record.configOwned=false;save("stream-configuring")
assert(route,"高速供液口不可用："..raw);verifyBulk(route,raw)
print("高速供液: "..raw.."；源 "..route.from.." -> 接收 "..route.to)
print(raw.." 整批目标 "..need.." mB；到账即搬入子网。") local job,status,craft,jobDeadline,doneAt
local attempts=0 local inletOpen=false local deadline=computer.uptime()+1800
while not stopping do unchanged();assert(same(field(),stock),"备料时约束场库存变化") assert(same(network(SUB),previous),"备料时子网库存变化")
priority=priority or productionWaiting()
local remaining=need-(previous[raw] or 0) local buffered=network(MAIN)[raw] or 0 local amount=priority and 0 or math.floor(math.min(remaining,buffered,chunk)/batch)*batch
if amount>0 then verifyBulk(route,raw);local address,from,to=route.address,route.from,route.to
record.pending={raw=raw,amount=amount,address=address,from=from,to=to};save("transfer-pending") local ok,moved=call(address,"transferFluid",from,to,amount) record.transfers[#record.transfers+1]={raw=raw,ok=ok,amount=moved,requested=amount,address=address,from=from,to=to}
save("transfer-returned") assert(ok==true and moved==amount,"未完整确认搬运，停止且不重试") previous[raw]=(previous[raw] or 0)+amount
waitUntil(10,function() return same(network(SUB),previous) end,unchanged) record.pending=nil;record.secured=previous;save("stream-transfer-confirmed") print(raw.." 已入子网 "..previous[raw].." / "..need.." mB")
deadline=computer.uptime()+1800 end remaining=need-(previous[raw] or 0)
if remaining==0 and inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;inletOpen=false;save("stream-inlet-cleared")
waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) end -- BEC_V1_SEQUENTIAL_CPU_WAIT_V1: keep both production fallback and cache alive while CPUs are occupied.
local supplyWaiting=false
local function supplyWait(reason,manual,missing,failure)
 supplyWaiting=true
 local summary=raw..': '..reason
 if not record.supplyWait or record.supplyWait.cpuWaitSummary~=summary then
  record.supplyWait={cpuWaitSummary=summary,cpuWait={[raw]={reason=reason,manual=manual,amount=missing,failure=failure}}}
  save(record.stage);print('供液等待: '..summary)
 end
end
if status and job.state=='submitted' then
 local computing=type(status.isComputing)=='function' and status.isComputing()
 local failed,why
 if type(status.hasFailed)=='function' then failed,why=status.hasFailed()end
 if computing==false and type(status.isComputing)=='function' and failed==true then
  job.state='rejected';job.preSubmissionFailed=true;job.manualSupply=true;job.failure=tostring(why)
  status=nil;save('stream-request-rejected')
 elseif computing then supplyWait('AE 正在计算计划，继续收料')
 else
  local canceled,why=status.isCanceled();assert(canceled==false,'AE任务取消且结果未确认: '..tostring(why))
  local done=status.isDone();assert(type(done)=='boolean','AE 状态不可读')
  if done then job.state='done';job.securedAfter=previous[raw] or 0;doneAt=computer.uptime();save('stream-craft-done')
  else supplyWait('AE 合成进行中，继续收料')end
 end
end
if priority and (not job or job.state=='done' or job.state=='rejected')then return handoff()end
if remaining==0 and (not job or job.state=='done' or job.state=='rejected')then record.supplyWait=nil;break end
if not priority and remaining>0 and (not job or job.state=='done' or job.state=='rejected')then
 local function deficit()return math.max(0,need-(previous[raw]or 0)-bufferedInlet()-(network(MAIN)[raw]or 0))end
 local missing=deficit()
 if missing>0 and (not doneAt or computer.uptime()-doneAt>=3)then
  if job and job.state=='done'then assert((previous[raw]or 0)>job.securedBefore,'原液合成已结束但没有收获，核对竞争设备')end
  local ok,cpus=pcall(call,MAIN,'getCpus');local free,total,known,maxStorage=0,0,0,0;local unknown=not ok or type(cpus)~='table'
  if not unknown then for _,cpu in pairs(cpus)do
   total=total+1
   if type(cpu)~='table' or type(cpu.busy)~='boolean'then unknown=true
   else if not cpu.busy then free=free+1 end
    if type(cpu.storage)=='number'and cpu.storage>=0 then known=known+1;maxStorage=math.max(maxStorage,cpu.storage)end
   end
  end end
  if job and job.manualSupply then
   supplyWait('AE未启动申请；请在 ME 手动申请 '..missing..' mB；自动收料继续',true,missing,job.failure)
  elseif unknown then supplyWait('等待 CPU 状态恢复可读')
  elseif total==0 or (known==total and maxStorage==0)then supplyWait('CPU 容量不足：没有可用合成存储')
  elseif free==0 then supplyWait('等待合成 CPU 空闲，自动化继续运行')
  else
   if not craft then
    local rows=call(MAIN,'getCraftables',{name=raw});assert(type(rows)=='table','原液配方不可读')
    local count=0;for _,v in pairs(rows)do craft=v;count=count+1 end
    assert(count==1,'原液配方缺失或不唯一: '..raw)
    local f=craft.getStack();assert(type(f)=='table'and f.name==raw and f.isCraftable==true and type(f.amount)=='number'and f.amount==f.size and f.hasTag==false,'未验证的流体合成对象')
   end
   missing=deficit()
   if missing>0 then
    if productionWaiting()then return handoff()end
    attempts=attempts+1;assert(attempts<=3,'原液被其他设备争抢，保留已收库存')
    job={raw=raw,amount=missing,unit='mB',state='pending',securedBefore=previous[raw]or 0}
    record.requests[#record.requests+1]=job;save('craft-request-pending')
    local why;status,why=craft.request(missing);assert(status~=nil,'AE申请结果不明: '..tostring(why))
    job.state='submitted';doneAt=nil;save('stream-crafting')
    supplyWait('AE 正在计算计划，继续收料')
   end
  end
 end
end
if supplyWaiting then deadline=math.max(deadline,computer.uptime()+1800)end
assert(computer.uptime()<deadline,'持续收料超时，保留子网已搬入原液')
 tick(0.1) end
if inletOpen then assert(call(MAIN,"setFluidInterfaceConfiguration",0)==true,"清供液配置失败") record.configOwned=false;save("stream-inlet-cleared")
end waitUntil(20,function() return tanks(4,raw)==0 end,unchanged) if stopping then return expected end
end end assert(same(network(SUB),expected),"整批子网原液不符")
record.plan=nil;save("stream-prepared") return expected end
local function cacheTarget(copies) assert(type(copies)=="number" and copies>=1 and copies==math.floor(copies),"缓存份数必须为正整数") local totals,count={},0 local selectedBackground
assert(fs.exists("/home/bec/recipes"),"没有已登记配方") for filename in fs.list("/home/bec/recipes") do if filename:sub(-4)==".dat" then local f=assert(io.open("/home/bec/recipes/"..filename,"r"));local text=f:read("*a");f:close()
local recipe=ser.unserialize(text) assert(type(recipe)=="table" and recipe.state=="converted" and type(recipe.condensates)=="table","配方记录未完成: "..filename) local demand={}
for _,out in ipairs(recipe.outputs or {}) do productionOutputs[tostring(out.name)..":"..tostring(tonumber(out.damage or 0))]=true end
for _,fluid in ipairs(recipe.condensates) do assert(mapping[fluid.name],"未登记原液映射: "..tostring(fluid.name)) demand[fluid.name]=(demand[fluid.name] or 0)+integer(fluid.amount)
end assert(next(demand),"配方没有凝聚物需求: "..filename) for name,need in pairs(demand) do
assert(need*copies<=2147483647,"缓存目标过大") totals[name]=math.max(totals[name] or 0,need*copies) end
count=count+1 print("配方 "..count.."："..filename) end end
assert(count>0,"没有可缓存的已登记配方") if fixedStock then
local input=io.open("/home/bec_cache.config","r")
if input then local cfg=ser.unserialize(input:read("*a"));input:close()
 assert(type(cfg)=="table" and cfg.version==1 and (cfg.overrides==nil or type(cfg.overrides)=="table"),"单项缓存配置无效")
 overrides=cfg.overrides or {};for name,n in pairs(overrides) do assert(type(name)=="string" and type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n),"单项缓存目标无效") end
end
for name in pairs(totals) do totals[name]=overrides[name]~=nil and overrides[name] or fixedStock end
end if background then local previous=io.open(JOURNAL,"r")
local old if previous then old=ser.unserialize(previous:read("*a"));previous:close() end if old and old.background and old.incomplete then
assert(old.stage=="stopped" and old.pending==nil and old.configOwned==false,"后台缓存有未确认操作，保留日志核对") totals=old.target else
if productionWaiting() then return {} end local stock=field();local selected,lowest for name,need in pairs(totals) do local available=stock[name] or 0
if available<need and (not lowest or available<lowest) then selected=name;lowest=available end end if not selected then return {} end
selectedBackground=selected;totals={[selected]=totals[selected]} end end
local live,stock=network(MAIN),field();for raw,n in pairs(network(SUB)) do live[raw]=math.max(live[raw] or 0,n) end local visibleRoutes=bulkPorts();local waiting for kind in pairs(totals) do local raw=mapping[kind]
local candidates={[raw]=true} candidates["fluid."..raw]=true if kind=="entangled_space" or kind=="entangled_time" then
local stem=kind=="entangled_space" and "spatialfluid" or "temporalfluid" candidates[stem]=true;candidates["fluid."..stem]=true end
local found={} for name in pairs(candidates) do if (live[name] or 0)>0 or visibleRoutes[name] then found[name]=true end end for name in pairs(candidates) do
local rows=call(MAIN,"getCraftables",{name=name}) assert(type(rows)=="table","原液配方读取失败") for _,craft in pairs(rows) do local stack=craft.getStack()
if type(stack)=="table" and stack.name==name and type(stack.amount)=="number" then found[name]=true end end end
local name,n=nil,0;for candidate in pairs(found) do name=candidate;n=n+1 end assert(n<=1,"原液名称不唯一: "..kind)
if n==0 and (stock[kind] or 0)<totals[kind] then waiting="等待原液库存/样板可见: "..kind.." / "..raw end
if n==1 then mapping[kind]=name end end
if productionWaiting() then return totals end local routes=bulkPorts();local stored=field()
for kind,need in pairs(totals) do
 if (stored[kind] or 0)<need and not routes[mapping[kind]] then waiting="等待高速口流体可见: "..kind.." / "..mapping[kind].."；空口暂不能识别绑定，稍后重扫" end
end
if selectedBackground then print("空闲高速补库：直接补本种完整缺口到 "..totals[selectedBackground].." mB；有配方优先让位。") end if fixedStock then
print("登记配方 "..count.."；默认目标 "..fixedStock.." mB，单项设置优先，0停补；只补差额。") else print("登记配方 "..count.."；每配方 "..copies.." 份，共用流体按最大用量缓存。") end return totals,waiting
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
assert(type(old)=="table" and old.kind=="cache" and old.stage=="stopped" and old.pending==nil and old.configOwned==false,"旧缓存有未确认操作，请保留日志核对") for _,job in ipairs(old.requests or {}) do assert(job.state=="done" or (job.state=="rejected" and job.preSubmissionFailed==true),"缓存申请仍未确认") end
archiveJournal(text) end record={version=1,kind="cache",requests={},transfers={},configOwned=false,target=target,copies=cacheCopies,fixedStock=fixedStock,background=background}
save("starting");armed=true local expected=prepareStreaming(target) if not stopping and next(expected) then
unchanged();save("converting");generator(true);if background then print("后台缓存纠缠转换中；本轮目标已更新。") end local deadline=computer.uptime()+180 for kind in pairs(target) do
deadline=deadline+math.ceil((expected[mapping[kind]] or 0)/(units[kind] or 144))*180 end while true do
unchanged();local ready=true;local now=field() for name,need in pairs(target) do if (now[name] or 0)<need then ready=false end end if ready then break end
assert(computer.uptime()<deadline,"缓存转换超时，保留库存与日志") tick(0.25) if stopping then break end
end generator(false) end
unchanged();generator(false) record.incomplete=false local final=field()
for name,need in pairs(target) do if (final[name] or 0)<need then record.incomplete=true end end for _,job in ipairs(record.requests) do if job.state~="done" and not(job.state=="rejected" and job.preSubmissionFailed==true) then save("craft-paused");print("缓存已暂停，AE申请仍需核对，不重复下单。");return
end end save("stopped") print(stopping and "预缓存已暂停，已有原液/凝聚物保留。" or background and "预缓存完成（本轮）；统一目标仍以界面各项库存为准。" or "预缓存完成；凝聚物留在约束场，生产时直接抵扣。")
end local ok,err=xpcall(cacheMain,debug.traceback) if not ok then
if armed then pcall(pause,15);pcall(generator,false) if record.configOwned then pcall(call,MAIN,"setFluidInterfaceConfiguration",0) end
end print("预缓存停止："..tostring(err));print("保留 /home/bec_cache.journal 和库存，不删除日志重跑。") end
return ok,err
]========],
["bec_cache_ui.lua"]=[========[local view=(...) if view~="embedded" and view~="standalone" then
local service=assert(loadfile("/home/bec_ui.lua","t",_ENV),"缺少生产界面") return service("run","cache")
end local embedded=view=="embedded"
local c=require("component") local event=require("event")
local computer=require("computer") local unicode=require("unicode")
local ser=require("serialization") local fs=require("filesystem")
local term=require("term") local gpu=assert(c.gpu,"需要显卡和屏幕")
local CONFIG="/home/bec_cache.config" local target=144000 -- BEC_V1_CACHE_CUSTOM_UI_V1
local overrides,selectedName,restoreDefault={},nil,false
local function valid(n) return type(n)=="number" and n>=1 and n<=2147483647 and n==math.floor(n) end local f=io.open(CONFIG,"r")
if f then local value=ser.unserialize(f:read("*a"));f:close()
assert(type(value)=="table" and value.version==1 and valid(value.target),"缓存配置损坏，请保留文件核对") target=value.target
assert(value.overrides==nil or type(value.overrides)=="table","单项缓存配置损坏")
overrides=value.overrides or {};for name,n in pairs(overrides) do assert(type(name)=="string" and type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n),"单项缓存目标无效") end
end local worker=assert(loadfile("/home/bec_cache.lua","t",_ENV),"缺少 /home/bec_cache.lua")
local oldPrint,oldPull=print,event.pull local oldW,oldH=gpu.getResolution()
local oldFg,fgPalette=gpu.getForeground() local oldBg,bgPalette=gpu.getBackground()
local mw,mh=gpu.maxResolution() assert(mw>=80 and mh>=25,"需要至少80×25屏幕")
local w,h=math.min(100,mw),math.min(30,mh) local busy,editing,quit=false,false,false
local buffer,status,logs=tostring(target),"等待设置或补缓存",{} local last=-math.huge
local names,page,registryAt={},1,-math.huge;local displayStock,displayStockAt=nil,-math.huge local labels={entangled_chromaticglass="彩色玻璃",entangled_transcendentmetal="超时空金属",
entangled_infinity="无尽",entangled_dimshiftedsuperfluid="维度偏移超流体", entangled_space="空间",entangled_spacetime="时空",entangled_time="时间",
entangled_neutronium="中子素",entangled_cosmicneutronium="宇宙中子素",entangled_bedrockium="基岩锭", entangled_celestialtungsten="天界钨",entangled_hypogen="海珀珍",entangled_phononmedium="声子介质",
entangled_quarkgluonplasma="夸克胶子等离子体",entangled_cosmicsolder="无尽宇宙焊料", entangled_mhdcsm="磁流体约束恒星物质",entangled_magmatter="磁物质",
entangled_universium="宇宙素",entangled_eternity="永恒"} local function log(text)
logs[#logs+1]=tostring(text);if #logs>30 then table.remove(logs,1) end end
local function refreshNames(stock) local wanted={}
if fs.exists("/home/bec/recipes") then for filename in fs.list("/home/bec/recipes") do if filename:sub(-4)==".dat" then
local input=assert(io.open("/home/bec/recipes/"..filename,"r")) local text=input:read("*a");input:close();local recipe=ser.unserialize(text)
assert(type(recipe)=="table" and recipe.state=="converted" and type(recipe.condensates)=="table","配方记录未完成: "..filename) for _,fluid in ipairs(recipe.condensates) do assert(type(fluid.name)=="string","流体记录无效");wanted[fluid.name]=true end
end end end
for name,n in pairs(stock or {}) do if n>0 then wanted[name]=true end end names={};for name in pairs(wanted) do names[#names+1]={labels[name] or name,name} end
table.sort(names,function(a,b) return a[2]<b[2] end) page=math.min(page,math.max(1,math.ceil(#names/8)))
registryAt=computer.uptime() end
local function line(y,text,color) text=tostring(text):gsub("[\r\n]"," ")
while unicode.wlen(text)>w-3 do text=unicode.sub(text,1,-2) end gpu.setBackground(0x080a0e);gpu.setForeground(color or 0xe6edf3)
gpu.fill(2,y,w-2,1," ");gpu.set(2,y,text) end
local function fitLabel(value,width) while unicode.wlen(value)>width do value=unicode.sub(value,1,-2) end
return value end
local externalFrame=false local function draw(force)
if embedded and not externalFrame then return end if not force and computer.uptime()-last<0.5 then return end
last=computer.uptime() gpu.setBackground(0x080a0e);gpu.fill(1,1,w,h," ")
line(2,"BEC / CACHE · 预缓存   |   统一库存配置",0x42d9ed) line(4,"状态："..status,busy and 0x65dda2 or 0xeeeeee)
line(6,(selectedName and ((labels[selectedName] or selectedName).." 单项目标：") or "默认缓存目标：")..(editing and buffer.."_" or tostring(target)).." mB",0x42d9ed) line(7,editing and "[ 保存 ]       [ 取消 ]       [ 恢复统一 ]  输入数字，0停补" or "[ E 默认目标 ]   [ B 补缓存 ]   [ P 预览 ]  点击流体设置；右键恢复默认")
local ok,stock=true,displayStock;if computer.uptime()-displayStockAt>=2 then ok,stock=pcall(c.invoke,"237a9cac-118a-4b74-8755-0d0b0ad216c0","getStoredCondensate");displayStock=ok and stock or nil;displayStockAt=computer.uptime() end stock=ok and type(stock)=="table" and stock or nil
if #names==0 or computer.uptime()-registryAt>=60 then local loaded,reason=pcall(refreshNames,stock);if not loaded then registryAt=computer.uptime();log(reason) end
end -- BEC_V1_CACHE_STATUS_FAST_V2
if embedded and stock and (status=="预缓存完成" or status=="本轮完成；继续维护库存") then
 local missing=0;for _,row in ipairs(names) do if (stock[row[2]] or 0)<(overrides[row[2]]~=nil and overrides[row[2]] or target) then missing=missing+1 end end
 line(4,missing>0 and ("状态："..missing.." 种未达标，等待下一轮补库") or "状态：当前显示库存已达标",0x42d9ed)
end
line(8,"登记/已有流体 "..#names.." 种   第 "..page.." / "..math.max(1,math.ceil(#names/8)).." 页 [ N 下一页 ]",0x42d9ed)
for i=1,8 do local row=names[(page-1)*8+i]
local desired=row and (overrides[row[2]]~=nil and overrides[row[2]] or target) or target
local value=row and stock and (stock[row[2]] or 0) or nil line(8+i,"")
if row then gpu.setBackground(0x111720);gpu.fill(2,8+i,w-2,1," ")
gpu.setForeground(0xe6edf3);gpu.set(3,8+i,fitLabel(row[1],24)) local bw=math.max(8,w-58)
gpu.setBackground(0x243041);gpu.fill(29,8+i,bw,1," ") local size=math.floor(bw*math.min(1,(value or 0)/math.max(1,desired)))
if size>0 then gpu.setBackground(value and value>=desired and 0x65dda2 or 0xa38bff);gpu.fill(29,8+i,size,1," ") end gpu.setBackground(0x111720);gpu.setForeground(0x42d9ed)
gpu.set(w-27,8+i,tostring(value or "?").." / "..(desired==0 and "停补" or desired)) end
end line(17,"只补已登记配方涉及的类型；整批转换可能略超目标。",0x768394)
line(18,embedded and "常驻服务空闲时自动补库；Q返回生产界面，补库继续。" or "补缓存前先退出生产服务；完成后可回生产界面。",0x768394) line(19,"最近日志",0x42d9ed)
local count=h-22 for i=1,count do line(19+i,logs[math.max(1,#logs-count+1)+i-1] or "",0x768394) end
line(h-1,embedded and "[ Q 返回生产界面，补库继续 ]" or (busy and "[ Q 暂停补缓存并退出 ]" or "[ Q 退出 ]   [ R 刷新 ]"),0x42d9ed) end
local function write(path,text) local out=assert(io.open(path,"w"));assert(out:write(text));assert(out:flush());out:close()
out=assert(io.open(path,"r"));local saved=out:read("*a");out:close() assert(saved==text,"配置保存回读不一致")
end local function save()
local n=tonumber(buffer)
assert(valid(n) or (selectedName~=nil and n==0),"默认目标需正整数；单项允许0停补")
local nextOverrides={};for name,value in pairs(overrides) do nextOverrides[name]=value end
local nextTarget=target
if selectedName then if restoreDefault then nextOverrides[selectedName]=nil else nextOverrides[selectedName]=n end else nextTarget=n end local previous=io.open(CONFIG,"r")
if previous then local old=previous:read("*a");previous:close()
local i=1;while fs.exists(CONFIG..".backup-"..i) do i=i+1 end write(CONFIG..".backup-"..i,old)
end write(CONFIG,ser.serialize({version=1,target=nextTarget,overrides=nextOverrides},false))
target=nextTarget;overrides=nextOverrides;editing=false;selectedName=nil;restoreDefault=false;status="缓存设置已保存，下次补库按单项目标执行" end
local function capture(...) local parts={...};for i,v in ipairs(parts) do parts[i]=tostring(v) end
local text=table.concat(parts," ");log(text) if text:find("预缓存停止",1,true) then status="补缓存停止，查看日志"
elseif text:find("后台缓存让位",1,true) then status=text
elseif text:find("等待高速口",1,true) or text:find("等待原液",1,true) then status=text
elseif text:find("高速供液",1,true) or text:find("已入子网",1,true) then status="高速缓存收液中"
elseif text:find("后台缓存纠缠转换中",1,true) then status="纠缠转换中"
elseif text:find("预缓存完成",1,true) then status=embedded and "本轮完成；继续维护库存" or "预缓存完成" elseif text:find("只读规划完成",1,true) then status="只读预览完成" end
if not embedded then draw(false) end end
local function pull(seconds,filter) if quit then return "key_down","ui",113,16 end
local deadline=computer.uptime()+(seconds or math.huge) repeat
draw(false) local e={oldPull(math.max(0,math.min(0.25,deadline-computer.uptime())))}
if e[1]=="touch" and e[5]==0 and e[4]==h-1 then if e[3]>=2 and e[3]<=25 then e={"key_down","ui",113,16}
elseif e[3]>=w-19 then draw(true);e={} else e={} end
end if e[1]=="key_down" and (e[3]==113 or e[3]==81) then quit=true end
if e[1] and (not filter or e[1]==filter) then return table.unpack(e) end until computer.uptime()>=deadline
end local function execute(preview)
busy=true;status=preview and "读取配方与库存" or "按差额补缓存";draw(true) local ok,err=pcall(worker,preview and "preview-stock" or "run-stock",target)
busy=false if not ok then status="补缓存停止，查看日志";log(err) end
draw(true) end
local function handle(e) if embedded and ((e[1]=="key_down" and (e[3]==113 or e[3]==81))
or (e[1]=="touch" and e[5]==0 and e[4]==h-1 and e[3]<=25)) then editing=false;selectedName=nil;restoreDefault=false;buffer=tostring(target);return "back" end if e[1]=="touch" and (e[5]==0 or e[5]==1) then
if e[4]>=9 and e[4]<=16 then
 local row=names[(page-1)*8+e[4]-8]
 if row then selectedName=row[2];restoreDefault=false;editing=true;buffer="";status="设置 "..row[1].."；输入新目标，0停止自动补这一种"
  if e[5]==1 then e={"key_down","ui",100} else e={} end
 end
elseif editing and e[4]==7 then
 e={"key_down","ui",e[3]<16 and 13 or e[3]<32 and 0 or 100,e[3]>=16 and e[3]<32 and 1 or 0}
elseif e[4]==6 then e={"key_down","ui",101} elseif e[4]==7 then e={"key_down","ui",e[3]<24 and 101 or (e[3]<40 and 98 or 112)}
elseif e[4]==8 then e={"key_down","ui",110} end end
if e[1]=="key_down" then local ch,code=e[3],e[4]
if editing then if code==1 then editing=false;selectedName=nil;restoreDefault=false
elseif ch==100 and selectedName then restoreDefault=true;buffer=tostring(target);local ok,err=pcall(save);if not ok then status=tostring(err) end
elseif ch==13 or code==28 then local ok,err=pcall(save);if not ok then status=tostring(err) end
elseif ch==8 or code==14 then buffer=buffer:sub(1,-2) elseif type(ch)=="number" and ch>=48 and ch<=57 and #buffer<10 then buffer=buffer..string.char(ch) end
elseif ch==101 or ch==69 then selectedName=nil;restoreDefault=false;editing=true;buffer="";status="修改默认目标，已设单项目标保持" elseif ch==98 or ch==66 then
if embedded then selectedName=nil;restoreDefault=false;buffer=tostring(target);local ok,err=pcall(save);status=ok and "已启用自动补缓存，空闲时执行" or tostring(err) else execute(false) end
elseif ch==112 or ch==80 then execute(true) end if not editing and (ch==114 or ch==82) then registryAt=-math.huge;displayStockAt=-math.huge end if not editing and (ch==110 or ch==78) then page=page%math.max(1,math.ceil(#names/8))+1 end
draw(true) end
end if embedded then
return {draw=function(force) externalFrame=true;local ok,err=pcall(draw,force);externalFrame=false
if not ok then error(err) end end,handle=handle,log=capture}
end local function main()
gpu.setResolution(w,h);gpu.setBackground(0x101820);gpu.fill(1,1,w,h," ") print=capture;event.pull=pull;draw(true)
while not quit do handle({pull(0.5)}) end end
local ok,err=xpcall(main,debug.traceback) print,event.pull=oldPrint,oldPull
pcall(gpu.setResolution,oldW,oldH) pcall(gpu.setForeground,oldFg,fgPalette);pcall(gpu.setBackground,oldBg,bgPalette)
pcall(term.clear);pcall(term.setCursor,1,1) if not ok then oldPrint("缓存界面退出："..tostring(err)) end
for i=math.max(1,#logs-5),#logs do oldPrint(logs[i]) end
]========],
["bec_check.lua"]=[========[-- Minimal read-only check. ASCII output avoids Unicode rendering issues.
local component = require("component")
local targets = {
  bec_io_node=true, bec_storage=true, bec_diode=true,
  gt_machine=true, me_interface=true, fluid_interface=true,
  me_controller=true, transposer=true, database=true
}
local rows = {"BEC component check"}
local ok, err = xpcall(function()
  for address, kind in component.list() do
    if targets[kind] then
      rows[#rows+1] = kind
      rows[#rows+1] = address
      rows[#rows+1] = ""
    end
  end
end, debug.traceback)
if not ok then rows[#rows+1] = tostring(err) end
local f = io.open("/home/bec_check_report.txt", "w")
if f then f:write(table.concat(rows,"\n")); f:close() end
for i, line in ipairs(rows) do
  print(line)
  if i % 12 == 0 and i < #rows then
    io.write("Press Enter to continue...")
    io.read()
  end
end
print("Report: /home/bec_check_report.txt")
]========],
["bec_clean.lua"]=[========[-- BEC history cleanup. Never removes active files, .previous, programs or reset evidence.
local mode=(...)or 'clean'
assert(mode=='clean'or mode=='check','usage: clean / check')
local fs=require('filesystem');local c=require('component')
assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'Exit UI with Q first')
assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false,'Stop the controller first')
local prefixes={'bec_cache.journal.stopped-','bec_auto.journal.stopped-',
 'bec_auto.journal.before-resume-','bec_nanites_io.journal.before-run-'}
local groups={};local total,removed=0,0
for name in fs.list('/home')do
 if not name:find('/',1,true)then
  for _,prefix in ipairs(prefixes)do
   local suffix=name:sub(#prefix+1)
   if name:sub(1,#prefix)==prefix and suffix:match('^%d+$')then
    local p='/home/'..name
    assert(not fs.isDirectory(p),'Unexpected directory: '..p)
    local ok,time=pcall(fs.lastModified,p)
    local rows=groups[prefix]or {};groups[prefix]=rows
    rows[#rows+1]={path=p,index=tonumber(suffix),time=ok and tonumber(time)or 0,size=fs.size(p)or 0}
   end
  end
 end
end
for _,prefix in ipairs(prefixes)do
 local rows=groups[prefix]or {}
 table.sort(rows,function(a,b)
  local x,y=a.time or 0,b.time or 0
  if x~=y then return x>y end
  return a.index>b.index
 end)
 for i=4,#rows do
  local row=rows[i]
  if mode=='clean'then assert(fs.remove(row.path),'Could not remove '..row.path)end
  removed=removed+1;total=total+row.size
 end
end
print((mode=='check'and 'Would remove 'or 'Removed ')..removed..' old history files; '..total..' bytes')
print('Kept 3 per history group. Active journals, .previous, reset backups, settings, recipes and programs kept.')
local ok,disk=pcall(fs.get,'/home')
if ok and disk and type(disk.spaceTotal)=='function'and type(disk.spaceUsed)=='function'then
 print('Free space: '..(disk.spaceTotal()-disk.spaceUsed())..' bytes')
end
print('If an IO journal write failed, check it before restarting a disk transfer.')
]========],
["bec_hd.config"]=[========[{version=1,node="b04787f9-5423-4b03-8549-c786d4ef38d0",field="237a9cac-118a-4b74-8755-0d0b0ad216c0"}
]========],
["bec_hd.lua"]=[========[-- OC HD Panel adapter. Existing bec_ui.lua remains responsible for machine writes.
local mode, panelAddress = ...
mode = mode or "monitor"
assert(mode == "monitor" or mode == "run" or mode == "resume" or mode == "restock",
  "用法: bec_hd.lua monitor|run|resume|restock [屏幕地址]")
local component = require("component")
local computer = require("computer")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local address
if panelAddress then address = assert(component.get(panelAddress), "屏幕地址不存在")
else
  local count = 0
  for a in component.list("hd_panel", true) do address = a; count = count + 1 end
  assert(count == 1, "请接入一块高清屏幕；多块屏幕时指定地址")
end
assert(component.type(address) == "hd_panel", "指定组件不是高清屏幕")
local panel = component.proxy(address)
assert(panel.setPage("bec_dashboard"))
local configFile=assert(io.open("/home/bec_hd.config","r"),"请从 bec_hd.config.example 创建 /home/bec_hd.config 并填写组件地址")
local configRaw=configFile:read("*a");configFile:close()
local configured,connection=pcall(serialization.unserialize,configRaw)
assert(configured and type(connection)=="table" and connection.version==1,"高清面板连接配置无效")
local function uuid(value)
  return type(value)=="string" and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
end
assert(uuid(connection.node) and uuid(connection.field),"请填写完整的 BEC 节点 / 约束场组件地址")
local node,field=connection.node,connection.field
local originalPull = event.pull
local originalPrint = print
local started, nextSnapshot = computer.uptime(), 0
local stopping, exiting, active = false, false, mode ~= "monitor"
local pauseRequest
local recent, lastStage = {}, nil
local labels = {
  idle="等待订单", crafting="生产中", ["paused-immediate"]="立即暂停",
  ["nanite-tier-too-low"]="蜂群等级不足", ["assembler-offline"]="等待观测阵列", unpowered="等待供电"
}
local fluidLabels = {
  entangled_bedrockium="基岩锭", entangled_cosmicneutronium="宇宙中子素",
  entangled_neutronium="中子素", entangled_chromaticglass="彩色玻璃",
  entangled_transcendentmetal="超时空金属", entangled_infinity="无尽",
  entangled_dimshiftedsuperfluid="维度偏移超流体",
  entangled_infinitycatalyst="无尽催化剂", entangled_spacetime="时空",
  entangled_eternity="永恒", entangled_hypogen="海珀珍", entangled_shirabon="shirabon"
}
local function read(address, method)
  local ok, value = pcall(component.invoke, address, method)
  return ok and value or nil
end
local function journal(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local raw = f:read("*a"); f:close()
  local ok, value = pcall(serialization.unserialize, raw)
  return ok and type(value) == "table" and value or {}
end
local function log(text)
  recent[#recent + 1] = tostring(text)
  while #recent > 8 do table.remove(recent, 1) end
end
local function reply(e, success, message)
  if type(e[5])=="number" and panel.ack then pcall(panel.ack,e[5],success,message) end
  log(message)
end
local function checkConfigRecovery()
  if filesystem.exists("/home/bec_cache.config") then return end
  for name in filesystem.list("/home") do
    assert(not name:match("^bec_cache%.config%.hd%.bak%."),"缓存配置缺失；请从 /home/bec_cache.config.hd.bak.* 恢复原配置后再启动")
  end
end
local function saveTarget(value, request)
  assert(type(value)=="number" and value>0 and value<=2147483647 and value==math.floor(value),"默认目标必须为有效正整数")
  checkConfigRecovery()
  local path="/home/bec_cache.config"
  local temp=path..".hd.new."..tostring(request)
  local backup=path..".hd.bak."..tostring(request)
  assert(not filesystem.exists(temp) and not filesystem.exists(backup),"临时文件已存在，请核对后重试")
  local config={version=1,overrides={}}
  local old=io.open(path,"r")
  local existed=old~=nil
  if old then
    local raw=assert(old:read("*a"));old:close()
    local parsed=serialization.unserialize(raw)
    assert(type(parsed)=="table" and parsed.version==1 and type(parsed.target)=="number" and parsed.target>0
      and parsed.target<=2147483647 and parsed.target==math.floor(parsed.target)
      and type(parsed.overrides or {})=="table","原缓存配置无效，未修改")
    for name,n in pairs(parsed.overrides or {}) do
      assert(type(name)=="string" and type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n),"原单项覆盖值无效，未修改")
    end
    config=parsed
  else assert(not filesystem.exists(path),"无法读取原配置，未修改") end
  config.target=value;config.overrides=config.overrides or {}
  local raw=serialization.serialize(config,false)
  local file=assert(io.open(temp,"w"))
  local wrote,writeReason=file:write(raw)
  local flushed,flushReason=file:flush()
  local closed,closeResult,closeReason=pcall(file.close,file)
  assert(wrote,writeReason);assert(flushed,flushReason)
  assert(closed and closeResult~=false and not closeReason,"临时文件关闭失败") -- OC close() succeeds with no return value.
  local check=assert(io.open(temp,"r"));local actual=assert(check:read("*a"));check:close()
  assert(actual==raw and serialization.unserialize(actual).target==value,"临时配置读回核对失败，未修改原配置")
  if existed then assert(filesystem.rename(path,backup),"无法备份原配置，未修改") end
  local called,renamed,reason=pcall(filesystem.rename,temp,path)
  if not called or not renamed then
    if existed then assert(filesystem.rename(backup,path),"保存失败且回滚失败；原配置位于 "..backup) end
    error("保存失败，原配置已恢复："..tostring(reason))
  end
  return existed and backup or nil
end
local function publish(force)
  local now = computer.uptime()
  if not force and now < nextSnapshot then return end
  nextSnapshot = now + 2 -- No AE network scans; hardware reads only once every 2 seconds.
  local record = journal("/home/bec_auto.journal")
  if record.stage and record.stage~=lastStage then
    log("生产阶段："..tostring(record.stage));lastStage=record.stage
  end
  local cache = journal("/home/bec_cache.journal")
  local config = journal("/home/bec_cache.config")
  local stock = read(field, "getStoredCondensate")
  local state = read(node, "getState")
  local tier = read(node, "getProvidedTier")
  local required = read(node, "getRequiredTier")
  local target = record.target or cache.target or {}
  if type(stock)=="table" then
    target={}
    local goal=tonumber(config.target) or 144000
    for name in pairs(stock) do
      local override=type(config.overrides)=="table" and config.overrides[name] or nil
      target[name]=type(override)=="number" and override>=0 and override==math.floor(override)
        and override<=2147483647 and override or goal
    end
  end
  local rows, names, achieved, total = {}, {}, 0, 0
  if type(stock) == "table" then for name in pairs(stock) do names[name] = true end end
  for name in pairs(target) do names[name] = true end
  local sorted = {}; for name in pairs(names) do sorted[#sorted+1]=name end; table.sort(sorted)
  for _, name in ipairs(sorted) do
    if #rows >= 32 then break end
    local amount, goal = tonumber(type(stock)=="table" and stock[name]) or 0, tonumber(target[name]) or 0
    rows[#rows + 1] = {name=fluidLabels[name] or name:gsub("^entangled_", ""), amount=amount, target=goal}
    if goal > 0 then total=total+1; if amount>=goal then achieved=achieved+1 end end
  end
  local snapshot = {
    status=labels[state] or tostring(state or "机器读取失败"),
    stage=tostring(record.stage or "尚无生产日志"), recipe="BEC 凝聚装配生产",
    mode=mode=="monitor" and "只读监控" or (active and "常驻服务" or "服务已停止，可恢复"),
    controls=mode~="monitor", configEditable=mode~="monitor" and not active,
    configTarget=tonumber(config.target) or 144000, parallel=read(node, "getParallelRecipesInProgress") or 0,
    maxParallel=read(node,"getMaxParallel") or 0, naniteTier=type(tier)=="table" and tier.tier or 0,
    requiredTier=type(required)=="table" and required.tier or 0,
    naniteCount=read(node,"getAvailableNanites") or 0,
    cachePercent=total>0 and achieved/total*100 or 0, uptime=now-started, fluids=rows, logs=recent
  }
  local ok, result, reason = pcall(panel.update, snapshot)
  if not ok then originalPrint("高清屏幕更新失败：" .. tostring(result))
  elseif result==nil then originalPrint("高清屏幕拒绝更新："..tostring(reason)) end
end
local function action(e)
  if e[1] ~= "hd_panel_action" or e[2] ~= address then return e end
  if e[3] == "refresh" then nextSnapshot=0;reply(e,true,"已请求刷新，等待下一份数据");return {} end
  if mode == "monitor" then reply(e,false,"只读监控拒绝控制操作");return {} end
  if e[3]=="cache_target" then
    if active then reply(e,false,"请先暂停原控制器，再保存目标");return {} end
    local ok,result=pcall(saveTarget,e[6],e[5])
    reply(e,ok,ok and "默认目标已保存；新补库计划读取，未完成计划按原日志恢复" or "保存失败："..tostring(result))
    if ok and result then log("原配置备份："..result) end
    nextSnapshot=0;return {}
  end
  if e[3] == "pause" and active then stopping=true;pauseRequest=e;return {"key_down","hd_panel",113,16}
  elseif e[3] == "patterns" and active then reply(e,true,"样板请求已交给原控制器，结果见日志");return {"key_down","hd_panel",115,31}
  elseif e[3] == "resume" and active then reply(e,true,"重试请求已交给原控制器，结果见日志");return {"key_down","hd_panel",116,20}
  elseif e[3] == "resume" and not active then return {"hd_resume",e} end
  reply(e,false,"服务已经停止，此操作当前不可用")
  return {}
end
local function bridgePull(timeout, ...)
  -- Preserve event.pull filters: the current bec_ui scheduler calls its saved pull without a filter.
  publish(false)
  local e = {originalPull(timeout, ...)}
  if e[1]=="key_down" and (e[3]==113 or e[3]==81) then exiting=true end
  return table.unpack(action(e))
end
local function runUI(runMode)
  stopping=false; active=runMode~="monitor"
  checkConfigRecovery()
  local ui = assert(loadfile("/home/bec_ui.lua", "t", _ENV), "缺少现有 /home/bec_ui.lua")
  event.pull=bridgePull
  local ok, err = xpcall(function() ui(runMode) end, debug.traceback)
  event.pull=originalPull; active=false
  if pauseRequest then reply(pauseRequest,ok,ok and "原控制界面已停止，适配器仍保持连接" or "控制界面异常退出，请核对日志");pauseRequest=nil end
  if not ok then log("控制界面退出："..tostring(err)); originalPrint(err) end
  log(stopping and "已通过原控制器暂停服务" or "控制界面已返回")
  publish(true)
end
local ok, err = xpcall(function()
  log("高清面板已连接；刷新周期 2 秒")
  if mode~="monitor" then runUI(mode) end
  while not exiting do
    publish(false)
    local e = action({originalPull(.25)})
    if e[1]=="hd_resume" then
      local record=journal("/home/bec_auto.journal")
      local f=io.open("/home/bec_auto.journal","r");local exists=f~=nil;if f then f:close() end
      local resumeMode=exists and record.stage~="stopped" and "resume" or "run"
      reply(e[2],true,"已交给原控制器的 "..resumeMode.." 入口，结果见运行状态");runUI(resumeMode)
    elseif e[1]=="key_down" and (e[3]==113 or e[3]==81) then exiting=true end
  end
end, debug.traceback)
event.pull=originalPull; print=originalPrint
pcall(panel.release)
if not ok then originalPrint(err) end
]========],
["bec_history.lua"]=[========[-- Bound completed runtime archives so a 4 MB disk does not fill with old rounds.
local fs=require('filesystem')
local allowed={['/home/bec_auto.journal.stopped-']=true,['/home/bec_auto.journal.before-resume-']=true,
 ['/home/bec_cache.journal.stopped-']=true,['/home/bec_nanites_io.journal.before-run-']=true}
local M={}
function M.prune(prefix,keep)
 assert(allowed[prefix],'Unknown history group')
 keep=keep or 3;assert(type(keep)=='number'and keep>=0 and keep%1==0)
 local namePrefix=prefix:sub(7);local rows={}
 for name in fs.list('/home')do
  if name:sub(1,#namePrefix)==namePrefix then
   local index=tonumber(name:sub(#namePrefix+1))
   if name:sub(#namePrefix+1):match('^%d+$')and not fs.isDirectory('/home/'..name)then
    local ok,time=pcall(fs.lastModified,'/home/'..name)
    rows[#rows+1]={path='/home/'..name,index=index,time=ok and tonumber(time)or 0}
   end
  end
 end
 table.sort(rows,function(a,b)if a.time~=b.time then return a.time>b.time end;return a.index>b.index end)
 for i=keep+1,#rows do assert(fs.remove(rows[i].path),'Could not prune '..rows[i].path)end
end
return M
]========],
["bec_initialize.lua"]=[========[-- BEC_V1_INITIALIZE_V1: explicitly abandon old bookkeeping and rebase on live hardware.
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local clock=require('computer');local event=require('event')
local MAIN='3afdc4cf-04e3-4ae9-8be6-e753c23a249d';local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0';local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local JOURNAL='/home/bec_auto.journal'
local paths={JOURNAL,'/home/bec_cache.journal',JOURNAL..'.failed-reset','/home/bec_cache.reset','/home/bec_cache.abandon'}
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(p)local f=io.open(p,'r');if not f then return end;local t=f:read('*a');f:close();return t end
local function write(p,t)local f=assert(io.open(p,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(p)==t,'初始化文件回读失败: '..p)end
local function integer(n)assert(type(n)=='number' and n>=0 and n%1==0,'实物数量不可读');return n end
local function same(a,b)for k,v in pairs(a)do if (b[k]or 0)~=v then return false end end;for k,v in pairs(b)do if (a[k]or 0)~=v then return false end end;return true end
local function stock()local t=call(FIELD,'getStoredCondensate');assert(type(t)=='table');local out={};for k,v in pairs(t)do out[k]=integer(v)end;return out end
local function rawStock()local rows=call(SUB,'getFluidsInNetwork');assert(type(rows)=='table');local out={}
 for _,row in pairs(rows)do local n=integer(row.amount or row.size or 0);if n>0 then assert(type(row.name)=='string');out[row.name]=(out[row.name]or 0)+n end end;return out end
local function snapshot()return {field=stock(),raw=rawStock(),required=call(NODE,'getRequiredCondensate'),consumed=call(NODE,'getConsumedCondensate')}end
local function tick()local _,_,ch=event.pull(.25,'key_down');assert(ch~=113 and ch~=81,'已退出初始化；记录备份和实物保留，再按Z从现场重新初始化')end
local audit,auditPath,armed
local function save(stage)audit.stage=stage;write(auditPath,ser.serialize(audit,false))end
local function guard()
 assert(call(RS,'getOutput',1)==15,'初始化暂停信号被改变')
 local state=call(NODE,'getState')
 assert(state=='idle' or state=='paused-immediate' or state=='assembler-offline' or state=='unpowered' or state=='nanite-tier-too-low','传送节点尚未确认停稳')
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do assert(call(MAIN,'getFluidInterfaceConfiguration',slot)==nil,'初始化期间供液配置被其他程序改变')end
end
local function main()
 local n=1
 while true do
  local occupied=fs.exists('/home/bec_initialize-'..n..'.dat')
  for _,p in ipairs(paths)do occupied=occupied or fs.exists(p..'.before-initialize-'..n) or fs.exists(p..'.retired-initialize-'..n) end
  if not occupied then break end;n=n+1
 end
 auditPath='/home/bec_initialize-'..n..'.dat'
 audit={version=1,kind='explicit-initialization',reason='user-reinitialize-unsubmitted-supply',files={},stage='backing-up'}
 -- Preserve original bytes, including corrupt or stale records. They are not runtime authority.
 for _,p in ipairs(paths)do local text=read(p);if text then
  local backup=p..'.before-initialize-'..n;write(backup,text)
  audit.files[#audit.files+1]={path=p,backup=backup,retired=p..'.retired-initialize-'..n}
 end end
 save('backed-up')
 assert(call(GEN,'getName')=='multi.bec.generator','纠缠装置地址不符')
 armed=true;call(RS,'setOutput',1,15);assert(call(RS,'getOutput',1)==15)
 call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false)
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do
  if call(MAIN,'getFluidInterfaceConfiguration',slot)~=nil then assert(call(MAIN,'setFluidInterfaceConfiguration',slot)==true,'清除供液配置失败')end
 end
 save('settling');print('初始化：已归档旧运行记录，等待机器当前转换完成。')
 while call(GEN,'isMachineActive')==true do guard();tick()end
 guard()
 -- A second stopped reading catches an API read that crossed a machine update.
 local before=snapshot();tick();guard();local current=snapshot()
 while not same(before.field,current.field) or not same(before.raw,current.raw)do
  before=current;tick();guard();current=snapshot()
 end
 audit.before=current;save('reading-live-inventory')
 -- The old equality assertion incorrectly counted input consumed by an active recipe as lost.
 -- Keep its expected/actual differences for diagnosis, but do not reuse that checkpoint.
 local checkpoint=read(JOURNAL..'.failed-reset')
 if checkpoint then
  local ok,old=pcall(ser.unserialize,checkpoint)
  if ok and type(old)=='table' then audit.previousExpected=old.expected end
 end
 local previous=current.raw;local lastProgress=clock.uptime();local lastMessage=-math.huge
 if next(current.raw)then
  save('draining-existing-material');call(GEN,'setWorkAllowed',true);assert(call(GEN,'isWorkAllowed')==true)
  print('初始化：转换子网现有原液；转换过程中等待产物入库，不按旧账判定缺料。')
  while true do
   guard();local active=call(GEN,'isMachineActive');local raw=rawStock()
   if not same(previous,raw) or active then previous=raw;lastProgress=clock.uptime()end
   if next(raw)==nil and active==false then break end
   if clock.uptime()-lastMessage>=5 then
    local total=0;for _,v in pairs(raw)do total=total+v end
    print('初始化：余液 '..total..' mB；'..(active and '转换正在进行，等待产物' or '等待纠缠装置处理余液'))
    lastMessage=clock.uptime()
   end
   if not active and clock.uptime()-lastProgress>=30 then
    audit.observed=snapshot();save('converter-not-processing')
    local rows={};for rawName,amount in pairs(raw)do rows[#rows+1]=rawName..' '..amount..' mB'end;table.sort(rows)
    error('纠缠装置30秒未处理余液：'..table.concat(rows,'；')..'；检查供电/输入仓/转换批量，再按Z')
   end
   tick()
  end
 end
 call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false)
 while call(GEN,'isMachineActive')==true do guard();tick()end
 local after=snapshot();tick();guard();local stable=snapshot()
 while not same(after.field,stable.field) or not same(after.raw,stable.raw)do after=stable;tick();guard();stable=snapshot()end
 assert(next(stable.raw)==nil,'还有未转换余液，尚未重新投料')
 audit.after=stable;save('ready-to-reinitialize')
 -- Retire all old supply/cache/reset states. Settings, recipes, addresses and item IO stay intact.
 for _,entry in ipairs(audit.files)do
  assert(read(entry.path)==read(entry.backup),'初始化期间记录被其他程序改写: '..entry.path)
 end
 local fresh={version=1,kind='continuous',stage='watching',configOwned=false,requests={},transfers={},target={},
  initialized={audit=auditPath,reason='explicit-live-inventory-rebase'}}
 local freshText=ser.serialize(fresh,false);local temp=JOURNAL..'.initialize-new-'..n;write(temp,freshText)
 for _,entry in ipairs(audit.files)do
  if entry.path~=JOURNAL then assert(fs.rename(entry.path,entry.retired),'旧状态归档失败: '..entry.path);assert(read(entry.retired)==read(entry.backup))end
 end
 local oldEntry;for _,entry in ipairs(audit.files)do if entry.path==JOURNAL then oldEntry=entry end end
 if oldEntry then assert(fs.rename(JOURNAL,oldEntry.retired),'旧生产状态归档失败')end
 if not fs.rename(temp,JOURNAL)then
  if oldEntry then assert(fs.rename(oldEntry.retired,JOURNAL),'原生产记录还原失败')end
  error('新状态安装失败；再次按Z初始化')
 end
 assert(read(JOURNAL)==freshText,'新生产状态回读失败')
 save('done');armed=false
 print('初始化完成：旧生产/缓存/重置状态已归档；按当前配方和实际库存重新投料。')
 print('现场诊断记录：'..auditPath)
end
local ok,why=xpcall(main,debug.traceback)
if armed then pcall(call,GEN,'setWorkAllowed',false)end
if not ok then print('初始化待处理: '..tostring(why))end
return ok,why
]========],
["bec_nanites.lua"]=[========[-- V1 module: whole-cell transfers through the verified south/north ME IO ports.
local c=require('component')
local ser=require('serialization')
local fs=require('filesystem')
local clock=require('computer')
local T='13070035-3a3f-4468-b896-1c084288fdc9'
local SOUTH='4e31083a-e153-40e4-bf3f-e5ada363819d'
local NORTH='4bfbed4a-5d62-4311-9d34-5761103e76ce'
local PAUSE='266f65b5-20be-4543-8f2f-bfd2d0816611'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0'
local PATH='/home/bec_nanites_io.journal'
local CELL='appliedenergistics2:item.ItemExtremeStorageCell.Singularity'
local DISPLAY_CAP,MIN=30720,64 -- Machine reading limit, not a transfer limit.
-- NaniteTier enum -> material ore name. Labels may be localized.
local tiers={Carbon={1,'Carbon'},Glowstone={1,'Glowstone'},Silver={2,'Silver'},
 Neutronium={2,'Neutronium'},Gold={3,'Gold'},TranscendentMetal={4,'Transcendent'},
 SixPhasedCopper={5,'SixPhasedCopper'},WhiteDwarfMatter={6,'WhiteDwarf'},
 BlackDwarfMatter={7,'BlackDwarf'},Universium={8,'Universium'},Eternity={9,'Eternity'},MagMatter={10,'MagMatter'}}
local record,context
local function call(a,m,...) return c.invoke(a,m,...) end
local function whole(n) return type(n)=='number' and n>=0 and n%1==0 end
local function read(path)
 local f=io.open(path,'r');if not f then return end
 local v=f:read('*a');f:close();return v
end
local function write(path,text)
 local f=assert(io.open(path,'w'));assert(f:write(text));assert(f:flush());f:close()
 assert(read(path)==text,'蜂群IO日志回读失败')
end
local function oldRecord()
 local text=read(PATH);if not text then return end
 local r=ser.unserialize(text)
 assert(type(r)=='table' and r.version==2 and r.kind=='cell-io','蜂群IO日志损坏，保留现场')
 return r
end
local function save(stage)
 record.stage=stage
 local old=read(PATH);if old then write(PATH..'.previous',old) end
 write(PATH,ser.serialize(record,false))
end
local function archive()
assert(loadfile("/home/bec_history.lua"))().prune(PATH..".before-run-",2)
 local old=read(PATH);if not old then return end
 local n=1;while fs.exists(PATH..'.before-run-'..n) do n=n+1 end
 write(PATH..'.before-run-'..n,old)
end
local function needed()
 local v=call(NODE,'getRequiredTier');return type(v)=='table' and v.tier or v
end
local function requiredFamily()
 local v=call(NODE,'getRequiredTier')
 return type(v)=='table' and v.name or nil
end
local function hive()
 local n=call(NODE,'getAvailableNanites');assert(whole(n),'蜂群仓数量无效')
 local p=call(NODE,'getProvidedTier')
 if n==0 then return 0 end
 assert(type(p)=='table' and whole(p.tier) and type(p.name)=='string','蜂群仓类型不可读')
 return n,p
end
local function guard()
 local s=call(NODE,'getState')
 if context and context.passive then
  assert(s=='crafting' or s=='paused-immediate' or s=='nanite-tier-too-low' or s=='idle','节点状态不适合换蜂：'..tostring(s))
  local demand=call(NODE,'getRequiredTier')
  record.requiredTier=type(demand)=='table' and demand.tier or demand
  record.requiredFamily=type(demand)=='table' and demand.name or nil
 else
  assert(call(PAUSE,'getOutput',1)==15,'换蜂必须保持传送节点暂停红石15')
  assert(s=='paused-immediate' or s=='nanite-tier-too-low' or
   s=='idle' and call(NODE,'isWorkAllowed')==false,'节点状态不适合换蜂：'..tostring(s))
  assert(needed()==record.requiredTier,'换蜂过程中配方等级变化，保留现场')
  assert(not record.requiredFamily or requiredFamily()==record.requiredFamily,'换蜂过程中蜂群类型需求变化，保留现场')
 end
 if context and context.check then context.check() end
 if context and context.stopping and context.stopping() then error('换蜂已暂停，保留现场') end
end
local function tick()
 if context and context.tick then context.tick(0.05) else os.sleep(0.05) end
 guard()
end
local function output(a,n)
 call(a,'setOutput',0,n);assert(call(a,'getOutput',0)==n,'IO向下红石回读失败')
end
local function off()
 local a,e=pcall(output,SOUTH,0);local b,f=pcall(output,NORTH,0)
 assert(a and b,'关闭IO红石失败，手动关闭两端：'..tostring(e)..'; '..tostring(f))
end
local function stack(side,slot) return call(T,'getStackInSlot',side,slot) end
local function describe(item)
 assert(type(item)=='table' and item.name==CELL and item.size==1,'蜂群硬盘必须是单个数字奇点')
 assert(whole(item.storedItemCount) and type(item.getAvailableItems)=='table','盘内数量不可读')
 local row
 for _,v in pairs(item.getAvailableItems) do
  assert(not row and type(v.name)=='string' and whole(v.size) and v.size>0 and not v.hasTag,'盘内不能混料或放带NBT蜂群')
  local material
  for _,ore in pairs(v.oreNames or {}) do
   local candidate=type(ore)=='string' and ore:match('^nanite(.+)$')
   if candidate and tiers[candidate] then
    assert(not material or material==candidate,'蜂群矿辞类型不唯一');material=candidate
   end
  end
  -- This exact item was read from, loaded into, and recovered from the real rig.
  if not material and v.name=='gregtech:gt.metaitem.03' and v.damage==4581 then material='TranscendentMetal' end
  assert(material,'未知蜂群，请保留编号和oreNames：'..tostring(v.name)..':'..tostring(v.damage))
  local t=tiers[material]
  row={name=v.name,damage=v.damage or 0,count=v.size,tier=t[1],family=t[2],label=v.label or material}
  row.key=row.name..':'..row.damage
 end
 local n=row and row.count or 0
 assert(n==item.storedItemCount,'盘内数量与清单不一致')
 return n,row
end
local function discover()
 for a,kind in pairs({[T]='transposer',[SOUTH]='redstone',[NORTH]='redstone',[PAUSE]='redstone',[NODE]='bec_io_node'}) do
  assert(c.type(a)==kind,'组件缺失或类型错误：'..a)
 end
 for _,side in ipairs({2,3}) do
  assert(call(T,'getInventoryName',side)=='tile.appliedenergistics2.BlockIOPort' and call(T,'getInventorySize',side)==12,'南北面应为12槽ME IO端口')
 end
 local size=call(T,'getInventorySize',0)
 assert(whole(size) and size>=1 and size<=1024,'底面硬盘盒不可读或过大')
 for _,a in ipairs({SOUTH,NORTH}) do for side=0,5 do
  assert(call(a,'getOutput',side)==0,'蜂群IO已有红石输出，不能叠加操作')
 end end
 return size
end
local function slotSnapshot(side,size)
 local ok,rows=pcall(function()
  if c.methods(T).getAllStacks==nil then return end
  local reader=call(T,'getAllStacks',side)
  assert(reader.count()==size,'批量槽数不符')
  local values=reader.getAll();assert(type(values)=='table')
  for index in pairs(values) do assert(whole(index) and index>=1 and index<=size,'批量槽号不符') end
  return values
 end)
 return ok and rows or nil
end
local function snapshotStack(rows,side,slot)
 if not rows then return stack(side,slot) end
 local item=rows[slot]
 if type(item)=='table' and item.name==nil then return nil end
 if item and (item.storedItemCount==nil or type(item.getAvailableItems)~='table') then return stack(side,slot) end
 return item
end
-- BEC_NANITES_IO_SLOTS_1_7_V1: exclusively shuttle one disk through input 1/output 7.
local function emptyPorts()
 for _,side in ipairs({2,3}) do
 for _,slot in ipairs({1,7}) do
  assert(stack(side,slot)==nil,'蜂群IO已有硬盘，保留未完成操作')
 end end
end
-- BEC_NANITES_BANK_FIRST10_V1: only physical slots 1..10 belong to the bee bank.
local function bank(size)
 local cells={}
 for slot=1,math.min(size,10) do
  local item=stack(0,slot)
  if item then
   local n,row=describe(item)
   cells[#cells+1]={slot=slot,count=n,item=row,
    empty=n==0 and item.canHoldNewItem==true and (item.remainingItemCount or 0)>0}
  end
 end
 return cells
end
local function pack(cells,key)
 local candidates={}
 for _,disk in ipairs(cells) do
  if disk.item and disk.item.key==key then candidates[#candidates+1]=disk end
 end
 table.sort(candidates,function(a,b) return a.count>b.count or a.count==b.count and a.slot<b.slot end)
 local picked,n={},0
 for _,disk in ipairs(candidates) do picked[#picked+1]=disk;n=n+disk.count end
 return picked,n
end
local function choose(cells,need,family)
 local seen,best={},nil
 for _,disk in ipairs(cells) do if disk.item and not seen[disk.item.key] then
  local item=disk.item;seen[item.key]=true
  local picked,n=pack(cells,item.key)
  local exact=item.tier==need and item.family==family
  if item.tier>=need and n>=MIN and (not best or exact and not best.exact
   or exact==best.exact and (item.tier<best.item.tier or item.tier==best.item.tier and n>best.count)) then
   best={item=item,count=n,picked=picked,exact=exact}
  end
 end end
 return best
end
local function move(from,to,source,dest,expected,key)
 guard()
 local n,row=describe(stack(from,source))
 assert(n==expected and (not key or row and row.key==key) and stack(to,dest)==nil,'搬盘前槽位/内容变化')
 record.pending={from=from,to=to,source=source,dest=dest,count=expected,key=key}
 save('moving-cell')
 assert(call(T,'transferItem',from,to,1,source,dest)==1,'搬盘返回值未确认，不重试')
 local actual,result=describe(stack(to,dest))
 assert(stack(from,source)==nil and actual==expected and (not key or result and result.key==key),'搬盘后槽位/内容不符，不重试')
 record.pending=nil;save('cell-moved')
end
local function runPort(side,rs,endDisk,endHive,kind,key)
 save('waiting-port');output(rs,15)
 local deadline=clock.uptime()+30
 while true do
  guard()
  local at,n,row
  -- Output 7 is free before each one-cell operation; read it before input 1.
  local item=stack(side,7)
  if item then at=7;n,row=describe(item) end
  if not at then item=stack(side,1);if item then n,row=describe(item) end end
  local h,p=hive()
  if record.operationTotal then
   assert(not n or n<=record.operationTotal,'盘内数量超出本次目标')
   assert(h<=math.min(record.operationTotal,DISPLAY_CAP),'仓内读数超出本次目标')
  end
  if row then assert(row.family==kind.family and row.tier==kind.tier and (not key or row.key==key),'IO盘内蜂群类型变化') end
  if at then
   output(rs,0)
   local diskOK=endDisk==nil and row and math.min(n,DISPLAY_CAP)==record.beforeReading or n==endDisk
   if diskOK and h==math.min(endHive,DISPLAY_CAP) then
    if h>0 then assert(p.tier==kind.tier and p.name==kind.family,'节点蜂群类型不符') end
    save('port-complete');return at,row
   end
  end
  assert(clock.uptime()<deadline,'IO转移未完成：盘内'..tostring(n)..'，仓内'..h..'；保留现场，不重试')
  tick()
 end
end
local function recover(cells)
 local h,p=hive();assert(h>0,'回收前蜂群已变化')
 local chosen
 for _,disk in ipairs(cells) do if disk.empty then
  if not chosen or record.holding and disk.slot==record.holding.home then chosen=disk end
 end end
 assert(chosen,'缺少可接收新类型的空数字奇点盘，旧蜂群未搬运')
 record.operationTotal=record.holding and record.holding.count or nil
 record.beforeReading=h;save('recovering')
 local known=record.holding and record.holding.key
 move(0,2,chosen.slot,1,0)
 local at,row=runPort(2,NORTH,record.operationTotal,0,{family=p.name,tier=p.tier},known)
 assert(row,'回收盘没有蜂群清单')
 move(2,0,at,chosen.slot,row.count,row.key)
 record.holding=nil;save('recovered')
 print('整盘回收：T'..row.tier..' / '..row.count..' 个，盘槽 '..chosen.slot)
end
local function loadCell(disk)
 local base,p=hive();local item=disk.item
 assert(item and item.count>0,'装入盘没有蜂群')
 if base>0 then assert(record.holding and record.holding.key==item.key and p.name==item.family and p.tier==item.tier,'追加蜂群身份未确认') end
 local actualBase=record.holding and record.holding.count or 0
 assert(base==math.min(actualBase,DISPLAY_CAP),'追加前节点数量变化')
 record.operationTotal=actualBase+item.count;save('loading')
 move(0,3,disk.slot,1,item.count,item.key)
 local at=runPort(3,SOUTH,0,record.operationTotal,item,item.key)
 move(3,0,at,disk.slot,0)
 record.holding={key=item.key,name=item.name,damage=item.damage,tier=item.tier,family=item.family,count=record.operationTotal,home=disk.slot}
 save('loaded')
 print('整盘装入：T'..item.tier..' / 仓内'..record.operationTotal..' 个，空盘槽 '..disk.slot)
end
local M={}
M.passiveStages=true
M.fastStages=true
-- Read-only decision for the controller. Never fills an already compatible hive
-- merely to change its quantity; same-tier family preference is intentional.
function M.needsSwitch()
 local need,family=needed(),requiredFamily()
 if not whole(need) or need<1 then return false end
 local old=oldRecord();assert(not old or old.stage=='done','旧蜂群IO未完成，保留盘和日志，不自动重放')
 local size=discover();emptyPorts()
 local cells=bank(size);local h,p=hive();local best=choose(cells,need,family)
 if h<MIN or not p or p.tier<need then
  if best then return true end
  local available=h
  if p and p.tier>=need then for _,disk in ipairs(cells) do
   if disk.item and disk.item.family==p.name then available=available+disk.count end
  end;return available>=MIN end
  return false
 end
 return best~=nil and (best.item.tier<p.tier or best.exact and p.name~=family)
end
function M.preview()
 local size=discover();local h,p=hive();local cells=bank(size)
 print('蜂群IO：南3装入，北2回收，底0硬盘盒 '..size..' 槽；整盘搬运，数量由放盘控制')
 print('仓内：'..h..' 个 / T'..tostring(p and p.tier)..'；需求T'..tostring(needed()))
 for _,disk in ipairs(cells) do if disk.item then
  print('盘槽 '..disk.slot..'：T'..disk.item.tier..' / '..disk.count..' 个 / '..disk.item.label)
 end end
 local r=oldRecord();print('蜂群IO日志：'..tostring(r and r.stage or '无')..'；旧接口日志不重放')
 emptyPorts()
end
function M.ensure(ctx)
 local started=clock.uptime()
 local need=needed();if not whole(need) or need<1 then return false end
 context=ctx;local size=discover()
 local old=oldRecord();assert(not old or old.stage=='done','旧蜂群IO未完成，保留盘和日志，不自动重放')
 emptyPorts()
 local family=requiredFamily()
 local cells=bank(size);local h,p=hive();local best=choose(cells,need,family)
 local known=old and old.holding
 -- A saturated node reading cannot prove the current raw quantity. Recover to
 -- read the actual quantity before another operation, even with an old record.
 if not (known and known.count==h and h<DISPLAY_CAP and p and known.family==p.name and known.tier==p.tier) then known=nil end
 local sameFamily=0
 if p then for _,disk in ipairs(cells) do if disk.item and disk.item.family==p.name then sameFamily=sameFamily+disk.count end end end
 if context and context.stage then
  local switch
  if h<MIN or not p or p.tier<need then switch=best~=nil or p and p.tier>=need and h+sameFamily>=MIN
  else switch=best~=nil and (best.item.tier<p.tier or best.exact and p.name~=family) end
  if not switch then return false end
 end
 local keeping=h>0 and p.tier>=need and h+sameFamily>=MIN
  and (not best or best.item.tier>=p.tier and not(best.exact and p.name~=family))
 local extra={}
 if keeping then
  if known then extra=pack(cells,known.key)
  else for _,disk in ipairs(cells) do if disk.item and disk.item.family==p.name then extra={disk};break end end end
  if #extra==0 then return false end
 else
  if not best and context and context.passive then return false end
  assert(best,'硬盘盒缺少满足T'..need..'的至少64个蜂群')
 end
 if h>0 and (not keeping or not known) then
  local hasEmpty=false;for _,disk in ipairs(cells) do if disk.empty then hasEmpty=true;break end end
  assert(hasEmpty,'缺少可接收新类型的空数字奇点盘，旧蜂群未搬运')
 end
 record={version=2,kind='cell-io',requiredTier=need,requiredFamily=family,holding=known,stage='prepared'}
 guard()
 if context and context.beforeAction then context.beforeAction() end
 archive();save('prepared')
 local ok,result=xpcall(function()
  if h>0 and (not keeping or not known) then
   recover(cells);cells=bank(size)
   if context and context.passive then need=needed();family=requiredFamily() end
   -- Once empty, the node cannot progress. Choose the latest requirement.
   if not whole(need) or need<1 then
    emptyPorts();save('done');print('蜂群已完整回盘；当前没有合成需求');return true
   end
   best=choose(cells,need,family)
   if not best and context and context.passive then
    emptyPorts();save('done');print('蜂群已完整回盘；等待满足T'..need..'的库存');return true
   end
   assert(best,'回收后没有可装入蜂群')
  elseif context and context.passive and h==0 then
   need=needed();family=requiredFamily()
   best=whole(need) and need>=1 and choose(cells,need,family) or nil
   if not best then emptyPorts();save('done');return false end
  end
  local picked
  if keeping and known then picked=extra else picked=best.picked end
  for _,disk in ipairs(picked) do loadCell(disk) end
  emptyPorts();guard()
  local n,t=hive();assert(n>=MIN and (context and context.passive or t.tier>=need),'换蜂后数量或等级不足')
  assert(record.holding and math.min(record.holding.count,DISPLAY_CAP)==n and record.holding.family==t.name,'换蜂后身份核对失败')
  save('done');print('蜂群IO完成：T'..t.tier..' / '..n..' 个；耗时 '..string.format('%.2f',clock.uptime()-started)..' 秒'..(context and context.passive and '；由节点判断当前阶段' or '；节点仍暂停'))
  return true
 end,debug.traceback)
 local cut,cutError=pcall(off)
 assert(cut,tostring(cutError));assert(ok,tostring(result)..'\n保留现场，不重试。')
 return result
end
local mode=(...)
if mode=='preview' then M.preview() elseif mode=='test' then M.ensure();M.preview()
elseif mode~=nil then error('用法：preview / test；或由V1控制器加载') end
return M
]========],
["bec_pattern.lua"]=[========[-- Read a copied processing pattern from interface pattern slot 1.
-- Read-only: this version does not edit patterns or request crafting.
local component=require("component")
local serialization=require("serialization")
local choices={}
for address,kind in component.list() do
  local ok,methods=pcall(component.methods,address)
  if ok and methods.getInterfacePattern~=nil then
    choices[#choices+1]={address=address,kind=kind,methods=methods}
  end
end
table.sort(choices,function(a,b) return a.address<b.address end)
if #choices==0 then print("No pattern-readable interface. Connect an adapter to a full ME interface block."); return end
local choice=1
if #choices>1 then
  print("Choose the pattern workshop interface:")
  for i,v in ipairs(choices) do print(i,v.kind,v.address) end
  io.write("Number: ")
  choice=tonumber(io.read())
  if not choice or choice%1~=0 or not choices[choice] then print("Invalid selection."); return end
end
local v=choices[choice]
print("INTERFACE: "..v.address)
for _,name in ipairs({"getInterfacePattern","setInterfacePatternInput",
  "setInterfacePatternOutput","clearInterfacePatternInput",
  "getCraftables","getItemsInNetwork","getFluidsInNetwork"}) do
  print(name..": "..(v.methods[name]~=nil and "YES" or "NO"))
end
local ok,p=pcall(component.invoke,v.address,"getInterfacePattern",1)
if not ok then print("READ ERROR: "..tostring(p)); return end
if p==nil then print("Pattern slot 1 is empty. Put an encoded processing pattern there."); return end
local f,err=io.open("/home/bec_pattern_report.txt","w")
if f then
  f:write("Interface: "..v.address.."\n"..serialization.serialize(p,true))
  f:close()
else print("SAVE ERROR: "..tostring(err)) end
print("isCraftable: "..tostring(p.isCraftable))
local function ascii(s)
  return tostring(s):gsub("[\128-\255]",function(c)
    return string.format("\\x%02X",string.byte(c))
  end)
end
local function dump(t,indent,depth)
  if type(t)~="table" then print(indent..ascii(t)); return end
  if depth>5 then print(indent.."[nested data; see report]"); return end
  local keys={}
  for k in pairs(t) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  for _,k in ipairs(keys) do
    if k~="label" and k~="tag" and k~="nbt" then
      if type(t[k])=="table" then
        print(indent..ascii(k)..":"); dump(t[k],indent.."  ",depth+1)
      else print(indent..ascii(k).." = "..ascii(t[k])) end
    end
  end
end
for _,group in ipairs({"inputs","outputs"}) do
  print("\n"..string.upper(group))
  local entries=p[group]
  if type(entries)~="table" then print("No decoded entries. See report.")
  else
    local keys={}
    for k in pairs(entries) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do
      print("ENTRY "..tostring(k)); dump(entries[k],"  ",0)
      io.write("Press Enter for next entry..."); io.read()
    end
  end
end
print("DONE: /home/bec_pattern_report.txt")
]========],
["bec_patterns.lua"]=[========[-- Automatic workshop pattern registration. Never touches the production interface.
local mode=(...) or "preview"
local c=require("component")
local fs=require("filesystem")
local ser=require("serialization")
local event=require("event")
local ADDRESS="72994a02-7bff-41cb-bfc7-8a541036d7ad"
local DIR="/home/bec/recipes"
local announced={}
local function equal(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~="table" then return a==b end
 for k,v in pairs(a) do if not equal(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function read(slot) return c.invoke(ADDRESS,"getInterfacePattern",slot) end
local function load(path)
 local f=assert(io.open(path,"r"));local text=f:read("*a");f:close()
 local value=ser.unserialize(text);assert(type(value)=="table","配方记录损坏，保留原文件")
 return value
end
local function save(path,record)
 local text=ser.serialize(record,false)
 local f=assert(io.open(path..".tmp","w"))
 assert(f:write(text),"配方记录写入失败");assert(f:flush(),"配方记录刷新失败")
 local closed,reason=f:close();assert(closed~=false and reason==nil,"配方记录关闭失败")
 local check=assert(io.open(path..".tmp","r"));local copy=check:read("*a");check:close()
 assert(copy==text and type(ser.unserialize(copy))=="table","配方记录回读失败")
 local backup
 if fs.exists(path) then
  local n=1;while fs.exists(path..".backup-"..n) do n=n+1 end
  backup=path..".backup-"..n;assert(fs.rename(path,backup),"旧配方记录归档失败")
 end
 local ok,err=fs.rename(path..".tmp",path)
 if not ok then if backup then fs.rename(backup,path) end;error(err or "配方记录保存失败") end
end
local function inspect(p)
 assert(p.isCraftable==false,"仅处理加工样板")
 assert(type(p.inputs)=="table" and type(p.outputs)=="table" and #p.outputs==1,"仅处理单产物加工样板")
 local out=p.outputs[1]
 assert(type(out.name)=="string" and not out.hasTag,"产物标识无效或带NBT，暂不登记")
 local ordinary,fluids={},{}
 local tail=false
 for index,input in ipairs(p.inputs) do
  assert(type(input)=="table" and type(input.name)=="string","输入标识无效")
  if input.name:sub(1,10)=="entangled_" then
   tail=true
   local n=tonumber(input.amount or input.size)
   assert(n and n>0 and n==math.floor(n),"凝聚物数量无效")
   assert(not (input.size and input.amount) or input.size==input.amount,"凝聚物数量字段不一致")
   fluids[#fluids+1]={name=input.name,amount=n,index=index}
  else
   assert(not tail,"凝聚物后还有普通输入，保留样板不处理")
   ordinary[#ordinary+1]=input
  end
 end
 local key=out.name:gsub("[^%w_]","_").."_"..tostring(out.damage or 0).."_"..tostring(out.size or 1)
 return DIR.."/"..key..".dat",ordinary,fluids
end
local function notify(slot,text)
 if announced[slot]~=text then print("槽 "..slot.."："..text);announced[slot]=text end
end
local function process(slot)
 local p=read(slot)
 if p==nil then announced[slot]=nil;return end
 assert(type(p)=="table","样板不可读")
 local path,ordinary,fluids=inspect(p)
 local existing=fs.exists(path) and load(path)
 if #fluids==0 then
  if existing then
   assert(existing.state=="converted" and equal(p.inputs,existing.ordinaryInputs)
    and equal(p.outputs,existing.outputs),"现有样板与登记记录不符，请保留并核对")
   notify(slot,"已转换并登记，无需重复处理")
  else notify(slot,"没有凝聚物输入，也无原始需求记录；不猜测配方") end
  return
 end
 assert(#ordinary>0,"不能移除全部样板输入")
 if existing then
  assert(existing.state=="converted" and equal(existing.original,p),"同产物记录冲突或有未完成转换，保留记录")
  assert(equal(existing.ordinaryInputs,ordinary) and equal(existing.condensates,fluids),"登记需求不一致")
 end
 local name=tostring(p.outputs[1].label or p.outputs[1].name)
 if mode=="preview" then
  print("槽 "..slot.."："..name.."，普通输入 "..#ordinary.." 项，凝聚物 "..#fluids.." 项")
  for _,f in ipairs(fluids) do print("  "..f.name.." "..f.amount.." mB") end
  return
 end
 assert(equal(read(slot),p),"登记前样板已变化")
 local record=existing or {version=1,state="prepared",interface=ADDRESS,slot=slot,
  original=p,ordinaryInputs=ordinary,outputs=p.outputs,condensates=fluids}
 if not existing then assert(fs.makeDirectory(DIR)~=false,"创建配方目录失败");save(path,record) end
 local changed=false
 local ok,err=xpcall(function()
  for i=#fluids,1,-1 do
   local before=read(slot)
   local expected={};for index=1,fluids[i].index do expected[index]=p.inputs[index] end
   assert(type(before)=="table" and before.isCraftable==p.isCraftable and equal(before.inputs,expected)
    and equal(before.outputs,p.outputs),"转换途中样板变化")
   changed=true
   assert(c.invoke(ADDRESS,"clearInterfacePatternInput",slot,fluids[i].index)~=false,"清除凝聚物输入失败")
  end
  local after=read(slot)
  assert(type(after)=="table" and after.isCraftable==p.isCraftable and equal(after.inputs,ordinary) and equal(after.outputs,p.outputs),"转换结果不符")
  if not existing then record.state="converted";save(path,record) end
 end,debug.traceback)
 if not ok then
  if changed then
   local restored,restoreErr=pcall(function()
    local after=read(slot)
    assert(type(after)=="table" and after.isCraftable==p.isCraftable and equal(after.outputs,p.outputs),"样板已被替换，不能自动还原")
    assert(type(after.inputs)=="table" and #after.inputs>=#ordinary and #after.inputs<=#p.inputs,"输入数量变化")
    for i,input in ipairs(after.inputs) do assert(equal(input,p.inputs[i]),"输入内容变化，不能自动还原") end
    for index=#after.inputs+1,#p.inputs do
     local input=p.inputs[index]
     assert(c.invoke(ADDRESS,"setInterfacePatternInput",slot,index,
      {name=input.name,size=input.size or input.amount,amount=input.amount or input.size},"fluid")~=false,"还原失败")
    end
    assert(equal(read(slot),p),"还原核对失败")
   end)
   if not existing then
    record.state=restored and "restored" or "needs_manual_restore"
    record.error=tostring(err);record.restoreError=not restored and tostring(restoreErr) or nil
    pcall(save,path,record)
   end
   error(tostring(err)..(restored and "；原样板已还原" or "；请保留此槽和记录，人工核对"))
  end
  error(err)
 end
 notify(slot,"转换完成并登记："..name)
end
local function main()
 assert(mode=="preview" or mode=="run" or mode=="watch","用法: preview / run / watch")
 local methods=c.methods(ADDRESS)
 for _,m in ipairs({"getInterfacePattern","clearInterfacePatternInput","setInterfacePatternInput"}) do
  assert(methods[m]~=nil,"工作接口缺少方法："..m)
 end
 print("BEC 样板自动处理：工作接口 "..ADDRESS)
 print(mode=="preview" and "只读预览，不修改样板或记录" or "放入原加工样板的副本，自动去除凝聚物输入并保存需求")
 repeat
  for slot=1,9 do
   local ok,err=pcall(process,slot)
   if not ok then notify(slot,"暂停处理："..tostring(err));return end
  end
  if mode~="watch" then break end
  local _,_,char=event.pull(1,"key_down")
  if char==113 or char==81 then break end
 until false
 print("样板处理已结束；转换样板仍在工作接口，需求记录在 "..DIR)
end
local ok,err=xpcall(main,debug.traceback)
if not ok then print("样板服务停止："..tostring(err)) end
]========],
["bec_start.lua"]=[========[-- New-disk launcher: monitor first, or explicitly initialize existing machinery.
local mode,panel=...
mode=mode or 'monitor'
local fs=require('filesystem');local c=require('component')
local function run(path,...)return assert(loadfile(path,'t',_ENV))(...)end
if mode=='bee-restart'then return run('/home/bec_bee_restart.lua')end
if mode=='initialize'then
 assert(fs.exists('/home/bec/recipes'),'没有配方目录，请从旧硬盘导入登记配方或用样板处理登记')
 local count=0;for name in fs.list('/home/bec/recipes')do if name:match('%.dat$')then count=count+1 end end
 assert(count>0,'还没有登记配方；请先迁移旧盘配方或运行 bec_patterns.lua')
 local ok,why=run('/home/bec_initialize.lua');assert(ok,why)
 ok,why=run('/home/bec_bee_restart.lua','reset');assert(ok,why)
 mode='resume'
end
assert(mode=='monitor'or mode=='run'or mode=='resume'or mode=='restock','用法：monitor / initialize / run / resume / bee-restart')
local count=0;for _ in c.list('hd_panel',true)do count=count+1 end
if count>0 then return run('/home/bec_hd.lua',mode,panel)end
return run('/home/bec_ui.lua',mode)
]========],
["bec_ui.lua"]=[========[local mode,initialView=... mode=mode or "run"
local c=require("component") local event=require("event")
local computer=require("computer") local unicode=require("unicode")
local ser=require("serialization") local term=require("term")
local gpu=c.gpu assert(gpu,"需要显卡和屏幕")
assert(mode=="run" or mode=="resume" or mode=="monitor" or mode=="restock" or mode=="reset","用法: run / resume / monitor / restock / reset") local controller
if mode~="monitor" then controller=assert(loadfile("/home/bec_auto.lua","t",_ENV),"缺少 /home/bec_auto.lua") end local main="3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local sub="86311657-33d1-41b5-a0d9-0aee7b5c2c50" local storage="237a9cac-118a-4b74-8755-0d0b0ad216c0"
local node="b04787f9-5423-4b03-8549-c786d4ef38d0" local gen="c1ae3f7c-f714-4c27-baf3-392d94a0aa50"
local rs="266f65b5-20be-4543-8f2f-bfd2d0816611" local fluids={{"彩色玻璃","molten.chromaticglass","entangled_chromaticglass"},
{"超时空金属","molten.transcendentmetal","entangled_transcendentmetal"}} local states={idle="等待订单",crafting="生产中",["paused-immediate"]="立即暂停",
["assembler-offline"]="等待观测阵列",unpowered="等待供电",["nanite-tier-too-low"]="蜂群等级不足"} local stages={starting="启动",waiting="等待订单 / 机器",["stream-planned"]="计算整批需求",
["stream-configuring"]="配置供液",["stream-crafting"]="主网合成并收料", ["stream-transfer-confirmed"]="持续收料",["stream-craft-done"]="合成完成 / 收料",
["stream-inlet-cleared"]="退回接口余料",["stream-prepared"]="整批原液已齐", ["craft-request-pending"]="记录原液申请",["transfer-pending"]="记录搬运",
["transfer-returned"]="核对搬运",converting="转换凝聚物",watching="连续生产", stopped="服务已暂停",["craft-paused"]="已暂停 / 原液申请待核对"}
local oldPrint,oldPull,oldSleep=print,event.pull,os.sleep local oldW,oldH=gpu.getResolution()
local oldFg,fgPalette=gpu.getForeground() local oldBg,bgPalette=gpu.getBackground()
local maxW,maxH=gpu.maxResolution() assert(maxW>=80 and maxH>=25,"界面需要至少80×25的显卡和屏幕")
local w,h=math.min(100,maxW),math.min(30,maxH) local logs,lastFrame,rendering={},-math.huge,false
local started=computer.uptime() local fault,stopRequested=false,false -- BEC_V1_UI_PAUSE_V1
local pauseReason,retryRequested=nil,false -- BEC_V1_UI_CACHE_RESET_V3
local resetRequested=false
local cacheView,showCache local returnedAt=-math.huge
local patternBusy,lastPattern=false,-math.huge local bg,fg,muted,accent,good,bad=0x080a0e,0xe6edf3,0x768394,0x42d9ed,0x65dda2,0xff667d
local panel,track,purple=0x111720,0x243041,0xa38bff local cachePage=1
-- BEC_V1_UI_SPEED_V1
-- BEC_V1_UI_SPEED_V2
local perf,activeService,lastServiceYield={},nil,-math.huge
local nativeInvoke=c.invoke
local function measure(name,elapsed)
 local row=perf[name] or {count=0,total=0,max=0}
 row.count=row.count+1;row.total=row.total+elapsed;row.max=math.max(row.max,elapsed);perf[name]=row
end
c.invoke=function(...)
 local worker=activeService and coroutine.running()==activeService
 local before=computer.uptime();local values=table.pack(nativeInvoke(...))
 if worker then
  measure("controller.component",computer.uptime()-before)
  if computer.uptime()-lastServiceYield>=0.05 then
   lastServiceYield=computer.uptime()
   -- This is a scheduling yield, not an added delay or a machine pause.
   local e={coroutine.yield(0,"key_down")}
   if e[1]=="key_down" and (e[3]==113 or e[3]==81) then stopRequested=true end
  end
 end
 return table.unpack(values,1,values.n)
end
local function writePerf()
 local names={};for name in pairs(perf) do names[#names+1]=name end;table.sort(names)
 local rows={"UI performance seconds; controller.resume excludes time yielded to UI."}
 for _,name in ipairs(names) do local v=perf[name]
  rows[#rows+1]=string.format("%s count=%d total=%.3f max=%.3f",name,v.count,v.total,v.max)
 end
 local text=table.concat(rows,"\n").."\n"
 local f=assert(io.open("/home/bec_ui.perf","w"));assert(f:write(text));assert(f:flush());f:close()
 f=assert(io.open("/home/bec_ui.perf","r"));local actual=f:read("*a");f:close();assert(actual==text,"性能记录回读失败")
end

local displayCache,displayFiles,pendingUI={},{},{}
local function pollUI()
 if not rendering then return end
 local e={oldPull(0)}
 if not e[1] then return end
 local quit=(e[1]=="key_down" and (e[3]==113 or e[3]==81))
  or (e[1]=="touch" and e[5]==0 and e[4]==h-1 and e[3]>=2 and e[3]<=25)
 if quit and not showCache and computer.uptime()-returnedAt>=0.4 then
  stopRequested=true
 else pendingUI[#pendingUI+1]=e end
end
local function pullUI(...)
 if #pendingUI>0 then return table.unpack(table.remove(pendingUI,1)) end
 return oldPull(...)
end
local function clearDisplayCache() displayCache={};displayFiles={} end

local gate="cf2a0c4a-ab8d-4958-b1df-253094d6690c" local function get(address,method,...)
pollUI()
local key=address..":"..method
local cached=displayCache[key];local now=computer.uptime()
if cached and (now<cached.untilAt or stopRequested) then return cached.value end
if stopRequested then return nil end
local ttl=(method=="getMaxParallel") and 30 or 2
local before=computer.uptime();local ok,value=pcall(c.invoke,address,method,...)
measure("display."..method,computer.uptime()-before)
if not ok then value=nil end
displayCache[key]={value=value,untilAt=computer.uptime()+ttl}
if ok then return value end return nil end
local function inventory(address) local rows=get(address,"getFluidsInNetwork")
if type(rows)~="table" then return nil end local result={}
for _,f in pairs(rows) do if type(f)=="table" and f.name then result[f.name]=(result[f.name] or 0)+(tonumber(f.amount or f.size) or 0)
end end return result
end local function journal(path)
path=path or "/home/bec_auto.journal";pollUI()
local cached=displayFiles[path];local now=computer.uptime()
if cached and (now<cached.untilAt or stopRequested) then return cached.value end
if stopRequested then return {} end
local fileStart=computer.uptime();local f=io.open(path,"r") if not f then
 displayFiles[path]={value={},untilAt=now+2};return {} end
local text=f:read("*a");f:close();measure("display.file",computer.uptime()-fileStart) local ok,value=pcall(ser.unserialize,text)
value=ok and type(value)=="table" and value or {}
displayFiles[path]={value=value,untilAt=computer.uptime()+(path:match("%.config$") and 10 or path:match("%.dat$") and 60 or 2)}
return value end
local function fit(text,width) text=tostring(text or "读取失败"):gsub("[\r\n]"," ")
while unicode.wlen(text)>width do text=unicode.sub(text,1,-2) end return text
end local function line(y,text,color)
gpu.setBackground(bg);gpu.setForeground(color or fg) gpu.fill(2,y,w-2,1," ");gpu.set(2,y,fit(text,w-3))
end local function amount(t,key)
if type(t)~="table" then return "?" end return tostring(t[key] or 0)
end local function toggle(value)
if value==nil then return "读取失败" end return value and "开启" or "关闭"
end local labels={entangled_chromaticglass="彩色玻璃",entangled_transcendentmetal="超时空金属",
entangled_infinity="无尽",entangled_dimshiftedsuperfluid="维度偏移超流体", entangled_space="空间",entangled_spacetime="时空",entangled_time="时间",
entangled_neutronium="中子素",entangled_cosmicneutronium="宇宙中子素",entangled_bedrockium="基岩锭", entangled_celestialtungsten="天界钨",entangled_hypogen="海珀珍",entangled_phononmedium="声子介质",
entangled_quarkgluonplasma="夸克胶子等离子体",entangled_cosmicsolder="无尽宇宙焊料", entangled_mhdcsm="磁流体约束恒星物质",entangled_magmatter="磁物质",
entangled_universium="宇宙素",entangled_eternity="永恒"} local registered,registryAt={},-math.huge
local function registry() if computer.uptime()-registryAt<60 then return end
registryAt=computer.uptime() pcall(function()
local fs=require("filesystem");local nextNames={} if fs.exists("/home/bec/recipes") then
for filename in fs.list("/home/bec/recipes") do if filename:sub(-4)==".dat" then
local r=journal("/home/bec/recipes/"..filename) if r.state=="converted" then for _,f in ipairs(r.condensates or {}) do if f.name then nextNames[f.name]=true end end end
end end
end registered=nextNames
end) end
local function text(x,y,value,width,color,background) gpu.setBackground(background or panel);gpu.setForeground(color or fg)
gpu.set(x,y,fit(value,width)) end
local function box(x,y,width,height,title) gpu.setBackground(panel);gpu.fill(x,y,width,height," ")
text(x+1,y,title,width-2,muted) end
local function number(n) if type(n)~="number" then return "?" end
if n>=1000000 then return string.format("%.2fM",n/1000000) end if n>=1000 then return string.format("%.1fk",n/1000) end
return tostring(math.floor(n)) end
local function bar(x,y,width,n,total,color) gpu.setBackground(track);gpu.fill(x,y,width,1," ")
local ratio=type(n)=="number" and type(total)=="number" and total>0 and math.min(1,math.max(0,n/total)) or 0 local size=math.floor(width*ratio)
if size>0 then gpu.setBackground(color or accent);gpu.fill(x,y,size,1," ") end end
local function module(y,title,value,color) text(3,y,title,14,muted);text(19,y,value,12,color or fg)
end local function paint()
local state=get(node,"getState") local record=journal()
local caching=record.stage=="cache-working" if caching then record=journal("/home/bec_cache.journal") end
local stock=get(storage,"getStoredCondensate") local required=get(node,"getRequiredCondensate")
local config=journal("/home/bec_cache.config") local goal=tonumber(config.target) or 144000
-- BEC_V1_UI_TARGETS_V1: same per-fluid targets as the cache worker/settings view.
local function cacheGoal(name)
 local v=type(config.overrides)=="table" and config.overrides[name] or nil
 if type(v)=="number" and v>=0 and v==math.floor(v) and v<=2147483647 then return v end
 return goal
end
registry();local wanted={} for name in pairs(registered) do wanted[name]=true end
for name,n in pairs(type(stock)=="table" and stock or {}) do if n>0 then wanted[name]=true end end for name in pairs(record.target or {}) do wanted[name]=true end
for name in pairs(type(required)=="table" and required or {}) do wanted[name]=true end local names={};local ready,total=0,0
for name in pairs(wanted) do names[#names+1]=name;total=total+1;if stock and (stock[name] or 0)>=cacheGoal(name) then ready=ready+1 end end table.sort(names)
cachePage=(cachePage-1)%math.max(1,math.ceil(#names/5))+1 local parallel=get(node,"getParallelRecipesInProgress")
local maxParallel=get(node,"getMaxParallel") local tier=get(node,"getProvidedTier")
local bees=get(node,"getAvailableNanites") gpu.setBackground(bg);gpu.fill(1,1,w,h," ")
text(2,2,"BEC / CONTROL CENTER",29,accent,bg) text(33,2,fault and "暂停：待处理" or caching and "自动补缓存" or states[state] or tostring(state),w-34,fault and bad or good,bg)
local cw=math.floor((w-4)/3) box(2,4,cw,4,"PRODUCTION / 生产并行")
text(3,5,tostring(parallel or "?").." / "..tostring(maxParallel or "?"),cw-2,accent) bar(3,7,cw-2,parallel,maxParallel,accent)
box(cw+3,4,cw,4,"CACHE / 缓存达标") text(cw+4,5,ready.." / "..total.." 种  "..(total>0 and math.floor(ready/total*100).."%" or "--"),cw-2,good)
bar(cw+4,7,cw-2,ready,total,good) box(cw*2+4,4,w-(cw*2+4),4,"NANITES / 纳米蜂群")
text(cw*2+5,5,"T"..tostring(type(tier)=="table" and tier.tier or "?").."  "..number(bees).." 个",w-(cw*2+6),purple) text(cw*2+5,7,"运行 "..math.floor(computer.uptime()-started).." 秒",w-(cw*2+6),muted)
box(2,9,30,11,"MODULES / 模块状态") module(11,"传送节点",states[state] or tostring(state),state=="crafting" and good or accent)
module(12,"纠缠装置",toggle(get(gen,"isWorkAllowed")),get(gen,"isMachineActive") and good or muted) module(13,"约束场",toggle(get(storage,"isWorkAllowed")),good)
local active=get(gate,"isMachineActive") module(14,"韦门过滤",active==nil and "未知" or active and "运行中" or "未运行",active and good or bad)
local filters=get(gate,"getCondensateFilters") module(15,"过滤类型",type(filters)=="table" and #filters.." 种" or "未知",accent)
module(16,"供液调度",caching and "缓存备料" or record.stage=="watching" and "备料完成" or stages[record.stage] or "待命",purple) module(17,"样板处理",patternBusy and "处理中" or "待命",patternBusy and good or muted)
local nr=journal("/home/bec_nanites_io.journal")
if nr.kind~="cell-io" then nr=journal("/home/bec_nanites.journal") end
local ns={draining="退回旧蜂群",filling="装入蜂群",verifying="核对蜂群",done="待命",
 loading="装入蜂群",loaded="装入已核对",recovering="回收蜂群",recovered="回收已核对",
 ["moving-cell"]="搬运存储盘",["waiting-port"]="端口传输中",["cell-moved"]="存储盘已搬入",
 ["port-complete"]="端口完成",prepared="准备换蜂"}
module(18,"蜂群切换",ns[nr.stage] or "待命",nr.stage and nr.stage~="done" and purple or muted) local nt=get(node,"getRequiredTier")
text(cw*2+5,6,"需求 T"..tostring(type(nt)=="table" and nt.tier or nt or "--"),w-(cw*2+6),muted) local rx,rw=34,w-35
box(rx,9,rw,12,"CACHE / 凝聚物库存 · "..cachePage.."/"..math.max(1,math.ceil(#names/5))) for i=1,5 do
local name=names[(cachePage-1)*5+i];local y=9+i*2 if name then
local desired=cacheGoal(name);local n=stock and (stock[name] or 0) or nil text(rx+1,y,labels[name] or name,math.max(10,rw-23),fg)
text(rx+rw-21,y,number(n).." / "..(desired==0 and "停补" or number(desired).." mB"),20,n and n>=desired and good or accent) bar(rx+1,y+1,rw-2,n,math.max(1,desired),n and n>=desired and good or purple)
end end
box(2,21,w-3,h-24,"EVENTS / "..(fault and "已暂停 / 待处理" or stages[record.stage] or record.stage or "等待订单")) local count=math.max(0,h-26)
for i=1,count do text(3,21+i,logs[math.max(1,#logs-count+1)+i-1] or "",w-5,muted) end
-- BEC_V1_CPU_WAIT_UI_V1: waiting for supply does not put the controller in fault.
local supply=record.pipeline or record.supplyWait;local cpuReason=supply and supply.cpuWaitSummary
if not fault and type(cpuReason)=="string" and cpuReason~="" then
 local rows=supply.cpuWait or {};local manual={}
 for raw,row in pairs(rows)do if row.manual then manual[#manual+1]=raw end end
 table.sort(manual)
 if #manual>0 then
  local index=math.floor(computer.uptime()/5)%#manual+1
  local raw=manual[index];local row=rows[raw]
  text(3,22,"手动申请 "..index.."/"..#manual..": "..raw.."  "..row.amount.." mB",w-5,0xffffff,0xb00020)
  if h>25 then text(3,23,"AE拒绝: "..tostring(row.failure).."；下单后自动收料继续",w-5,0xffffff,0xb00020) end
 else
 local shortage=cpuReason:find("CPU 容量不足",1,true) or cpuReason:find("手动申请",1,true)
 text(3,22,"供液状态："..cpuReason,w-5,0xffffff,shortage and 0xb00020 or 0x23505b)
 if h>25 then text(3,23,"失败后在 ME 手动申请；程序继续收料，够料即生产",w-5,0xffffff,0x23505b) end
 end
end
local reason=pauseReason
if not fault then
 if state=="unpowered" then reason="供电不足：检查机器供电"
 elseif state=="assembler-offline" then reason="观测阵列未就绪：检查连接与运行状态"
 elseif state=="nanite-tier-too-low" then reason="蜂群等级不足：检查所需蜂群"
 end
end
if reason then
 text(3,22,"暂停原因："..reason,w-5,0xffffff,0xb00020)
 if h>25 then text(3,23,fault and "处理后点击下方继续；恢复时重新核对记录" or "等待条件满足后，常驻服务继续检查",w-5,0xffffff,0xb00020) end
end gpu.setBackground(bg);gpu.setForeground(accent)
gpu.set(2,h-2,fit("[ S 样板处理 ]  [ N 缓存翻页 ]",w-3))
if fault then text(2,h-2,"[ Z 初始化 / 重新投料 ]",28,0xffffff,0xb00020);text(60,h-2,"[ T 重试 / 继续 ]",w-61,0xffffff,0xb00020) end gpu.setBackground(track);gpu.setForeground(fg);gpu.fill(2,h-1,w-2,1," ")
gpu.set(3,h-1,mode=="monitor" and "[ Q 退出监控 ]" or "[ Q 暂停并退出 ]") gpu.set(31,h-1,"[ C 缓存设置 ]");gpu.set(w-19,h-1,"[ R 刷新 ]")
end local frameBuffer,oldBuffer
local function beginFrame() if not frameBuffer then
assert(gpu.allocateBuffer and gpu.setActiveBuffer and gpu.bitblt and gpu.freeBuffer,"显卡缺少后台缓冲功能，请使用支持VRAM的显卡") oldBuffer=gpu.getActiveBuffer()
frameBuffer=assert(gpu.allocateBuffer(w,h),"显存不足，无法分配界面缓冲") end
assert(gpu.setActiveBuffer(frameBuffer)~=nil,"无法切换后台缓冲") end
local function draw(force) if rendering or (not force and computer.uptime()-lastFrame<2) then return end
rendering=true local frameStart=computer.uptime();local ok,err=pcall(function()
beginFrame() if showCache then cacheView.draw(force) else paint() end
assert(gpu.bitblt(0,1,1,w,h,frameBuffer,1,1),"界面提交失败") end)
measure("display.frame",computer.uptime()-frameStart)
if frameBuffer then pcall(gpu.setActiveBuffer,oldBuffer or 0) end rendering=false;lastFrame=computer.uptime()
if not ok then logs[#logs+1]="界面刷新失败："..tostring(err);if #logs>20 then table.remove(logs,1) end end end
local function capture(...) local parts={...};for i,v in ipairs(parts) do parts[i]=tostring(v) end
local text=table.concat(parts," ") if cacheView then cacheView.log(text) end
logs[#logs+1]=text;if #logs>20 then table.remove(logs,1) end if text:find("程序停止",1,true) then
 fault=true;pauseReason=text:match("([^\n]+)") or text
 pauseReason=pauseReason:gsub("^程序停止：%s*",""):gsub("^程序停止:%s*",""):gsub("^/home/[^:]+:%d+:%s*","")
end
draw(false) end
local function processPatterns() if mode=="monitor" then capture("只读监控模式，请在生产界面处理样板");return end
if patternBusy or computer.uptime()-lastPattern<1 then return end patternBusy=true;lastPattern=computer.uptime()
capture("开始处理工坊9槽样板；已登记样板自动跳过。") local ok,err=pcall(function()
local worker,reason=loadfile("/home/bec_patterns.lua","t",_ENV) assert(worker,"缺少样板脚本："..tostring(reason));worker("run")
end) patternBusy=false
if not ok then capture("样板处理失败："..tostring(err)) end draw(true)
end local function openSettings()
if mode=="monitor" then capture("只读监控不修改缓存配置");return end if not cacheView then
local ok,value=pcall(function() return assert(loadfile("/home/bec_cache_ui.lua","t",_ENV),"缺少缓存界面")("embedded")
end) if not ok or type(value)~="table" then capture("缓存界面打开失败："..tostring(value));return end
cacheView=value end
showCache=true;draw(true) end
local function handle(e)
if fault and mode~="monitor" and ((e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=2 and e[3]<=28)
 or (e[1]=="key_down" and (e[3]==122 or e[3]==90))) then
 resetRequested=true;retryRequested=true;return {}
end
if fault and mode~="monitor" and ((e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=60)
 or (e[1]=="key_down" and (e[3]==116 or e[3]==84))) then
 retryRequested=true;return {}
end
if showCache then
if cacheView.handle(e)=="back" then if clearDisplayCache then clearDisplayCache() end showCache=false;returnedAt=computer.uptime();draw(true) end draw(e[1]~=nil);return {}
end if e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=32 and e[3]<=55 then e={"key_down","ui",110,49} end
if e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=2 and e[3]<=28 then e={"key_down","ui",115,31}
end if e[1]=="touch" and e[5]==0 and e[4]==h-1 then
if e[3]>=2 and e[3]<=25 then e={"key_down","ui",113,16} elseif e[3]>=31 and e[3]<=49 then e={"key_down","ui",99,46}
elseif e[3]>=w-19 then clearDisplayCache();registryAt=-math.huge;draw(true);e={} end end
if e[1]=="key_down" and (e[3]==110 or e[3]==78) then cachePage=cachePage+1;draw(true);e={} end if e[1]=="key_down" and (e[3]==114 or e[3]==82) then clearDisplayCache();registryAt=-math.huge;draw(true);e={} end
if e[1]=="key_down" and (e[3]==115 or e[3]==83) then processPatterns();e={} end if e[1]=="key_down" and (e[3]==99 or e[3]==67) then
openSettings();e={} end
if e[1]=="key_down" and (e[3]==113 or e[3]==81) then if computer.uptime()-returnedAt<0.4 then e={} else stopRequested=true end
end return e
end -- BEC_V1_UI_INITIALIZE_V1: new live-inventory session.
local function cacheResetWorker()
-- BEC_V1_INITIALIZE_V1: explicitly abandon old bookkeeping and rebase on live hardware.
local c=require('component');local ser=require('serialization');local fs=require('filesystem')
local clock=require('computer');local event=require('event')
local MAIN='3afdc4cf-04e3-4ae9-8be6-e753c23a249d';local SUB='86311657-33d1-41b5-a0d9-0aee7b5c2c50'
local FIELD='237a9cac-118a-4b74-8755-0d0b0ad216c0';local GEN='c1ae3f7c-f714-4c27-baf3-392d94a0aa50'
local NODE='b04787f9-5423-4b03-8549-c786d4ef38d0';local RS='266f65b5-20be-4543-8f2f-bfd2d0816611'
local JOURNAL='/home/bec_auto.journal'
local paths={JOURNAL,'/home/bec_cache.journal',JOURNAL..'.failed-reset','/home/bec_cache.reset','/home/bec_cache.abandon'}
local function call(a,m,...)return c.invoke(a,m,...)end
local function read(p)local f=io.open(p,'r');if not f then return end;local t=f:read('*a');f:close();return t end
local function write(p,t)local f=assert(io.open(p,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(p)==t,'初始化文件回读失败: '..p)end
local function integer(n)assert(type(n)=='number' and n>=0 and n%1==0,'实物数量不可读');return n end
local function same(a,b)for k,v in pairs(a)do if (b[k]or 0)~=v then return false end end;for k,v in pairs(b)do if (a[k]or 0)~=v then return false end end;return true end
local function stock()local t=call(FIELD,'getStoredCondensate');assert(type(t)=='table');local out={};for k,v in pairs(t)do out[k]=integer(v)end;return out end
local function rawStock()local rows=call(SUB,'getFluidsInNetwork');assert(type(rows)=='table');local out={}
 for _,row in pairs(rows)do local n=integer(row.amount or row.size or 0);if n>0 then assert(type(row.name)=='string');out[row.name]=(out[row.name]or 0)+n end end;return out end
local function snapshot()return {field=stock(),raw=rawStock(),required=call(NODE,'getRequiredCondensate'),consumed=call(NODE,'getConsumedCondensate')}end
local function tick()local _,_,ch=event.pull(.25,'key_down');assert(ch~=113 and ch~=81,'已退出初始化；记录备份和实物保留，再按Z从现场重新初始化')end
local audit,auditPath,armed
local function save(stage)audit.stage=stage;write(auditPath,ser.serialize(audit,false))end
local function guard()
 assert(call(RS,'getOutput',1)==15,'初始化暂停信号被改变')
 local state=call(NODE,'getState')
 assert(state=='idle' or state=='paused-immediate' or state=='assembler-offline' or state=='unpowered' or state=='nanite-tier-too-low','传送节点尚未确认停稳')
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do assert(call(MAIN,'getFluidInterfaceConfiguration',slot)==nil,'初始化期间供液配置被其他程序改变')end
end
local function main()
 local n=1
 while true do
  local occupied=fs.exists('/home/bec_initialize-'..n..'.dat')
  for _,p in ipairs(paths)do occupied=occupied or fs.exists(p..'.before-initialize-'..n) or fs.exists(p..'.retired-initialize-'..n) end
  if not occupied then break end;n=n+1
 end
 auditPath='/home/bec_initialize-'..n..'.dat'
 audit={version=1,kind='explicit-initialization',reason='user-reinitialize-unsubmitted-supply',files={},stage='backing-up'}
 -- Preserve original bytes, including corrupt or stale records. They are not runtime authority.
 for _,p in ipairs(paths)do local text=read(p);if text then
  local backup=p..'.before-initialize-'..n;write(backup,text)
  audit.files[#audit.files+1]={path=p,backup=backup,retired=p..'.retired-initialize-'..n}
 end end
 save('backed-up')
 assert(call(GEN,'getName')=='multi.bec.generator','纠缠装置地址不符')
 armed=true;call(RS,'setOutput',1,15);assert(call(RS,'getOutput',1)==15)
 call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false)
 assert(call(FIELD,'isWorkAllowed')==true,'约束场须开启')
 for slot=0,5 do
  if call(MAIN,'getFluidInterfaceConfiguration',slot)~=nil then assert(call(MAIN,'setFluidInterfaceConfiguration',slot)==true,'清除供液配置失败')end
 end
 save('settling');print('初始化：已归档旧运行记录，等待机器当前转换完成。')
 while call(GEN,'isMachineActive')==true do guard();tick()end
 guard()
 -- A second stopped reading catches an API read that crossed a machine update.
 local before=snapshot();tick();guard();local current=snapshot()
 while not same(before.field,current.field) or not same(before.raw,current.raw)do
  before=current;tick();guard();current=snapshot()
 end
 audit.before=current;save('reading-live-inventory')
 -- The old equality assertion incorrectly counted input consumed by an active recipe as lost.
 -- Keep its expected/actual differences for diagnosis, but do not reuse that checkpoint.
 local checkpoint=read(JOURNAL..'.failed-reset')
 if checkpoint then
  local ok,old=pcall(ser.unserialize,checkpoint)
  if ok and type(old)=='table' then audit.previousExpected=old.expected end
 end
 local previous=current.raw;local lastProgress=clock.uptime();local lastMessage=-math.huge
 if next(current.raw)then
  save('draining-existing-material');call(GEN,'setWorkAllowed',true);assert(call(GEN,'isWorkAllowed')==true)
  print('初始化：转换子网现有原液；转换过程中等待产物入库，不按旧账判定缺料。')
  while true do
   guard();local active=call(GEN,'isMachineActive');local raw=rawStock()
   if not same(previous,raw) or active then previous=raw;lastProgress=clock.uptime()end
   if next(raw)==nil and active==false then break end
   if clock.uptime()-lastMessage>=5 then
    local total=0;for _,v in pairs(raw)do total=total+v end
    print('初始化：余液 '..total..' mB；'..(active and '转换正在进行，等待产物' or '等待纠缠装置处理余液'))
    lastMessage=clock.uptime()
   end
   if not active and clock.uptime()-lastProgress>=30 then
    audit.observed=snapshot();save('converter-not-processing')
    local rows={};for rawName,amount in pairs(raw)do rows[#rows+1]=rawName..' '..amount..' mB'end;table.sort(rows)
    error('纠缠装置30秒未处理余液：'..table.concat(rows,'；')..'；检查供电/输入仓/转换批量，再按Z')
   end
   tick()
  end
 end
 call(GEN,'setWorkAllowed',false);assert(call(GEN,'isWorkAllowed')==false)
 while call(GEN,'isMachineActive')==true do guard();tick()end
 local after=snapshot();tick();guard();local stable=snapshot()
 while not same(after.field,stable.field) or not same(after.raw,stable.raw)do after=stable;tick();guard();stable=snapshot()end
 assert(next(stable.raw)==nil,'还有未转换余液，尚未重新投料')
 audit.after=stable;save('ready-to-reinitialize')
 -- Retire all old supply/cache/reset states. Settings, recipes, addresses and item IO stay intact.
 for _,entry in ipairs(audit.files)do
  assert(read(entry.path)==read(entry.backup),'初始化期间记录被其他程序改写: '..entry.path)
 end
 local fresh={version=1,kind='continuous',stage='watching',configOwned=false,requests={},transfers={},target={},
  initialized={audit=auditPath,reason='explicit-live-inventory-rebase'}}
 local freshText=ser.serialize(fresh,false);local temp=JOURNAL..'.initialize-new-'..n;write(temp,freshText)
 for _,entry in ipairs(audit.files)do
  if entry.path~=JOURNAL then assert(fs.rename(entry.path,entry.retired),'旧状态归档失败: '..entry.path);assert(read(entry.retired)==read(entry.backup))end
 end
 local oldEntry;for _,entry in ipairs(audit.files)do if entry.path==JOURNAL then oldEntry=entry end end
 if oldEntry then assert(fs.rename(JOURNAL,oldEntry.retired),'旧生产状态归档失败')end
 if not fs.rename(temp,JOURNAL)then
  if oldEntry then assert(fs.rename(oldEntry.retired,JOURNAL),'原生产记录还原失败')end
  error('新状态安装失败；再次按Z初始化')
 end
 assert(read(JOURNAL)==freshText,'新生产状态回读失败')
 save('done');armed=false
 print('初始化完成：旧生产/缓存/重置状态已归档；按当前配方和实际库存重新投料。')
 print('现场诊断记录：'..auditPath)
end
local ok,why=xpcall(main,debug.traceback)
if armed then pcall(call,GEN,'setWorkAllowed',false)end
if not ok then print('初始化待处理: '..tostring(why))end
return ok,why

end
local function mainUI()
gpu.setResolution(w,h);gpu.setBackground(bg) beginFrame();gpu.setActiveBuffer(oldBuffer or 0)
print=capture event.pull=function(n,filter) if stopRequested then return "key_down","ui",113,16 end return coroutine.yield(n,filter) end
os.sleep=function(n) coroutine.yield(n) end draw(true)
if stopRequested then return end
if initialView=="cache" then openSettings() end if mode=="monitor" then
repeat handle({pullUI(0.1)});if not stopRequested then draw(false) end until stopRequested else
local service=coroutine.create(function() controller(mode) end);activeService=service local deadline,filter
local function advance(e) local resumeStart=computer.uptime();local ok,n,f=coroutine.resume(service,table.unpack(e or {}))
measure("controller.resume",computer.uptime()-resumeStart)
if not ok then capture("程序停止: "..tostring(n));deadline=math.huge;filter=nil;return end
deadline=computer.uptime()+(tonumber(n) or math.huge);filter=f end
while true do
advance() while coroutine.status(service)~="dead" do
local e=handle({pullUI(math.max(0,math.min(0.1,deadline-computer.uptime())))})
if stopRequested then e={"key_down","ui",113,16} end if e[1] and (not filter or filter==e[1]) then advance(e)
elseif computer.uptime()>=deadline then advance() end if not stopRequested then draw(false) end end
draw(true)
if fault and not stopRequested then
 repeat handle({pullUI(0.1)});if not stopRequested then draw(false) end until stopRequested or retryRequested
 if stopRequested then break end
 local doReset=resetRequested;resetRequested=false;retryRequested=false;fault=false;pauseReason=nil;clearDisplayCache()
 -- Only the existing validated recovery entry point may restart a controller.
 -- Never erase, rewrite or silently mark unconfirmed operations as done here.
 local f=io.open("/home/bec_auto.journal","r");local retryMode=f and "resume" or "run";if f then f:close() end
 service=coroutine.create(function()
 if doReset then
  local ok,err=cacheResetWorker();assert(ok,err)
  cacheView=nil;showCache=false;clearDisplayCache()
 end
 controller(retryMode)
end);activeService=service
 deadline=nil;filter=nil;started=computer.uptime()
else break end
end
end end
local ok,err=xpcall(mainUI,debug.traceback) c.invoke=nativeInvoke;activeService=nil print,event.pull,os.sleep=oldPrint,oldPull,oldSleep
if frameBuffer then pcall(gpu.setActiveBuffer,oldBuffer or 0)
pcall(gpu.freeBuffer,frameBuffer) end
pcall(gpu.setResolution,oldW,oldH) pcall(gpu.setForeground,oldFg,fgPalette);pcall(gpu.setBackground,oldBg,bgPalette)
pcall(term.clear);pcall(term.setCursor,1,1) if not ok then oldPrint("界面退出："..tostring(err)) end
for i=math.max(1,#logs-5),#logs do oldPrint(logs[i]) end if mode=="monitor" then oldPrint("已退出只读监控。") end

local perfOk,perfError=pcall(writePerf);if not perfOk then oldPrint("性能记录失败："..tostring(perfError)) else oldPrint("性能记录: /home/bec_ui.perf") end
]========]
}
local stage='/home/bec_install_stage'
local function read(p)local f=io.open(p,'r');if not f then return end;local t=f:read('*a');f:close();return t end
local function write(p,t)local f=assert(io.open(p,'w'));assert(f:write(t));assert(f:flush());f:close();assert(read(p)==t,'写入回读失败: '..p)end
local function checksum(text)local a,b=1,0;for i=1,#text do a=(a+text:byte(i))%65521;b=(b+a)%65521 end;return b*65536+a end
local function validate(entry,text)
 assert(#text==entry.size and checksum(text)==entry.checksum,'下载校验失败')
 if entry.name:match('%.lua$')then assert(load(text,'@'..entry.name,'t',_ENV),'Lua语法错误')
 else assert(type(ser.unserialize(text))=='table','默认配置无效')end
 return text
end
local function fetch(entry)
 if bundled[entry.name]then return validate(entry,bundled[entry.name])end
 internet=internet or require('internet')
 local roots={'https://raw.githubusercontent.com/Alivn-chao/gtnh-bec-automation/'..TAG..'/reinstall/files/',
 'https://fastly.jsdelivr.net/gh/Alivn-chao/gtnh-bec-automation@'..TAG..'/reinstall/files/'}
 local errors={}
 for _,root in ipairs(roots)do
  local ok,result=pcall(function()
   local pieces,n={},0;for chunk in internet.request(root..entry.name)do
    assert(type(chunk)=='string');n=n+#chunk;assert(n<=entry.size,'下载内容超出预期');pieces[#pieces+1]=chunk
   end
   return validate(entry,table.concat(pieces))
  end)
  if ok then return result end;errors[#errors+1]=tostring(result)
 end
 error(entry.name..' 下载失败：'..table.concat(errors,'; '))
end
local pending=read(stage..'/release.txt')
local resuming=pending and pending:match('^([^\n]+)')==TAG
if fs.exists(stage)then assert(resuming,'安装临时目录不是本版，请核对 '..stage)end
if resuming and not oldHome then local saved=pending:match('\n(.+)$');if saved then oldHome=saved end end
for _,entry in ipairs(manifest)do
 assert(entry.name:match('^[%w_%.]+$')and not entry.name:find('..',1,true),'安装包路径无效')
 if not importOnly and not resuming then assert(not fs.exists('/home/'..entry.name),'这是新盘完整安装包；当前文件已存在: '..entry.name)end
end
assert(not fs.exists('/home/bec_auto.journal')and not fs.exists('/home/bec_nanites_io.journal'),'当前盘有运行状态，请使用新盘OpenOS安装')
if not oldHome then
 local candidates,seen={},{}
 local current=fs.get('/home')
 for proxy,path in fs.mounts()do
  if proxy.address~=current.address then for _,suffix in ipairs({'home/',''})do
   local candidate=path:gsub('/+$','')..'/'..suffix
   candidate=candidate:gsub('/+$','')
   if not seen[candidate]and fs.exists(candidate..'/bec/recipes')and fs.exists(candidate..'/bec_auto.lua')then
    candidates[#candidates+1]=candidate;seen[candidate]=true
   end
  end end
 end
 if #candidates==1 then oldHome=candidates[1]
 elseif #candidates>1 then
  for _,p in ipairs(candidates)do print('旧盘候选：'..p)end
  error('找到多个旧程序目录；请重新运行安装器并在命令后指定旧home目录')
 end
end
local imports={};local recipes=0
if importOnly then assert(oldHome,'未找到旧盘；命令格式：lua /home/bec_install.lua import /mnt/旧盘地址/home')end
if oldHome then
 oldHome=oldHome:gsub('/+$','')
 assert(fs.isDirectory(oldHome),'旧盘目录不存在: '..oldHome)
 for _,name in ipairs({'bec_cache.config','bec_hd.config'})do
  local text=read(oldHome..'/'..name)
  if text then
   local ok,t=pcall(ser.unserialize,text);assert(ok and type(t)=='table'and t.version==1,'旧配置不可读: '..name)
   if name=='bec_cache.config'then
    assert(type(t.target)=='number'and t.target>=1 and t.target<=2147483647 and t.target%1==0,'旧缓存目标无效')
    assert(t.overrides==nil or type(t.overrides)=='table','旧单项缓存配置无效')
    for k,v in pairs(t.overrides or {})do assert(type(k)=='string'and type(v)=='number'and v>=0 and v<=2147483647 and v%1==0,'旧单项缓存目标无效')end
   else
    for _,k in ipairs({'node','field'})do assert(type(t[k])=='string'and t[k]:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'旧高清配置地址无效')end
   end
   imports[name]=text
  end
 end
 local dir=oldHome..'/bec/recipes'
 if fs.isDirectory(dir)then for name in fs.list(dir)do
  if name:match('^[%w_%-%.]+%.dat$')and not fs.isDirectory(dir..'/'..name)then
   local text=assert(read(dir..'/'..name));local ok,t=pcall(ser.unserialize,text)
   assert(ok and type(t)=='table'and t.state=='converted'and type(t.condensates)=='table','旧配方未完成或不可读: '..name)
   imports['bec/recipes/'..name]=text;recipes=recipes+1
  end
 end end
 print('只迁移配方与配置，来源：'..oldHome)
end
if importOnly then
 if not fs.exists('/home/bec/recipes')then assert(fs.makeDirectory('/home/bec/recipes'))end
 for name,text in pairs(imports)do
  local target='/home/'..name;local previous=read(target)
  if previous~=text then
   if previous then local n=1;while fs.exists(target..'.before-import-'..n)do n=n+1 end;write(target..'.before-import-'..n,previous)end
   write(target,text)
  end
 end
 print('旧盘配方与配置迁移完成：'..recipes..' 个配方；未复制运行日志。');return
end
local disk=fs.get('/home');local needed=65536
for _,entry in ipairs(manifest)do needed=needed+entry.size end
for _,text in pairs(imports)do needed=needed+#text end
assert(disk.spaceTotal()-disk.spaceUsed()>needed,'新盘空间不足；至少需要 '..needed..' 字节')
-- Stage and validate every download before exposing a partial program installation.
if not fs.exists(stage)then assert(fs.makeDirectory(stage));write(stage..'/release.txt',TAG..'\n'..(oldHome or ''))end
for i,entry in ipairs(manifest)do
 print('下载 '..i..'/'..#manifest..' '..entry.name)
 local expected=imports[entry.name]
 local installed=read('/home/'..entry.name)
 if installed then
  assert(installed==expected or (not expected and #installed==entry.size and checksum(installed)==entry.checksum),'部分安装的目标已变化: '..entry.name)
 else
  local cached=read(stage..'/'..entry.name)
  local valid=cached and (cached==expected or (not expected and #cached==entry.size and checksum(cached)==entry.checksum))
  if not valid then write(stage..'/'..entry.name,expected or fetch(entry))end
 end
 imports[entry.name]=nil
end
if not fs.exists('/home/bec/recipes')then assert(fs.makeDirectory('/home/bec/recipes'))end
for name,text in pairs(imports)do
 local target='/home/'..name;local previous=read(target)
 assert(not previous or previous==text,'目标数据已变化: '..target)
 if not previous then write(target,text)end
end
for _,entry in ipairs(manifest)do if not fs.exists('/home/'..entry.name)then assert(fs.rename(stage..'/'..entry.name,'/home/'..entry.name),'安装改名失败: '..entry.name)end end
assert(fs.remove(stage..'/release.txt'))
assert(fs.remove(stage),'清除安装临时目录失败')
print('完整安装完成：V1控制器、单项缓存、整盘换蜂、初始化与OCHD适配器。')
print('已迁移登记配方 '..recipes..' 个；没有复制历史日志，也没有启动机器。')
print('只读查看：lua /home/bec_start.lua monitor')
print('盘归位且ME IO设置正确后，从现场初始化并运行：lua /home/bec_start.lua initialize')
if recipes==0 then print('尚未迁移配方：保留旧盘，用安装器 import /mnt/旧盘地址/home 迁移，或用 bec_patterns.lua 登记样板。')end
