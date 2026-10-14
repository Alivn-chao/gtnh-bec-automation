local mode,initialView=... mode=mode or "run"
local c=require("component") local event=require("event")
local computer=require("computer") local unicode=require("unicode")
local ser=require("serialization") local term=require("term")
local gpu=c.gpu assert(gpu,"需要显卡和屏幕")
assert(mode=="run" or mode=="resume" or mode=="monitor" or mode=="restock","用法: run / resume / monitor / restock") local controller
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
local started=computer.uptime() local fault,stopRequested=false,false
local cacheView,showCache local returnedAt=-math.huge
local patternBusy,lastPattern=false,-math.huge local bg,fg,muted,accent,good,bad=0x080a0e,0xe6edf3,0x768394,0x42d9ed,0x65dda2,0xff667d
local panel,track,purple=0x111720,0x243041,0xa38bff local cachePage=1
local gate="cf2a0c4a-ab8d-4958-b1df-253094d6690c" local function get(address,method,...)
local ok,value=pcall(c.invoke,address,method,...) if ok then return value end
return nil end
local function inventory(address) local rows=get(address,"getFluidsInNetwork")
if type(rows)~="table" then return nil end local result={}
for _,f in pairs(rows) do if type(f)=="table" and f.name then result[f.name]=(result[f.name] or 0)+(tonumber(f.amount or f.size) or 0)
end end return result
end local function journal(path)
local f=io.open(path or "/home/bec_auto.journal","r") if not f then return {} end
local text=f:read("*a");f:close() local ok,value=pcall(ser.unserialize,text)
return ok and type(value)=="table" and value or {} end
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
local function registry() if computer.uptime()-registryAt<5 then return end
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
local stock=get(storage,"getStoredCondensate") local required,consumed=get(node,"getRequiredCondensate"),get(node,"getConsumedCondensate")
local config=journal("/home/bec_cache.config") local goal=tonumber(config.target) or 144000
registry();local wanted={} for name in pairs(registered) do wanted[name]=true end
for name,n in pairs(type(stock)=="table" and stock or {}) do if n>0 then wanted[name]=true end end for name in pairs(record.target or {}) do wanted[name]=true end
for name in pairs(type(required)=="table" and required or {}) do wanted[name]=true end local names={};local ready,total=0,0
for name in pairs(wanted) do names[#names+1]=name;total=total+1;if stock and (stock[name] or 0)>=goal then ready=ready+1 end end table.sort(names)
cachePage=(cachePage-1)%math.max(1,math.ceil(#names/5))+1 local parallel=get(node,"getParallelRecipesInProgress")
local maxParallel=get(node,"getMaxParallel") local tier=get(node,"getProvidedTier")
local bees=get(node,"getAvailableNanites") gpu.setBackground(bg);gpu.fill(1,1,w,h," ")
text(2,2,"BEC / CONTROL CENTER",29,accent,bg) text(33,2,fault and "程序已退出" or caching and "自动补缓存" or states[state] or tostring(state),w-34,fault and bad or good,bg)
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
local nr=journal("/home/bec_nanites.journal") local ns={draining="退回旧蜂群",filling="装入蜂群",verifying="核对蜂群",done="切换完成"}
module(18,"蜂群切换",ns[nr.stage] or "待命",nr.stage and nr.stage~="done" and purple or muted) local nt=get(node,"getRequiredTier")
text(cw*2+5,6,"需求 T"..tostring(type(nt)=="table" and nt.tier or nt or "--"),w-(cw*2+6),muted) local rx,rw=34,w-35
box(rx,9,rw,12,"CACHE / 凝聚物库存 · "..cachePage.."/"..math.max(1,math.ceil(#names/5))) for i=1,5 do
local name=names[(cachePage-1)*5+i];local y=9+i*2 if name then
local n=stock and (stock[name] or 0) or nil text(rx+1,y,labels[name] or name,math.max(10,rw-23),fg)
text(rx+rw-21,y,number(n).." / "..number(goal).." mB",20,n and n>=goal and good or accent) bar(rx+1,y+1,rw-2,n,goal,n and n>=goal and good or purple)
end end
box(2,21,w-3,h-24,"EVENTS / "..(stages[record.stage] or record.stage or "等待订单")) local count=math.max(0,h-26)
for i=1,count do text(3,21+i,logs[math.max(1,#logs-count+1)+i-1] or "",w-5,muted) end gpu.setBackground(bg);gpu.setForeground(accent)
gpu.set(2,h-2,fit("[ S 样板处理 ]  [ N 缓存翻页 ]",w-3)) gpu.setBackground(track);gpu.setForeground(fg);gpu.fill(2,h-1,w-2,1," ")
gpu.set(3,h-1,mode=="monitor" and "[ Q 退出监控 ]" or "[ Q 暂停并退出 ]") gpu.set(31,h-1,"[ C 缓存设置 ]");gpu.set(w-19,h-1,"[ R 刷新 ]")
end local frameBuffer,oldBuffer
local function beginFrame() if not frameBuffer then
assert(gpu.allocateBuffer and gpu.setActiveBuffer and gpu.bitblt and gpu.freeBuffer,"显卡缺少后台缓冲功能，请使用支持VRAM的显卡") oldBuffer=gpu.getActiveBuffer()
frameBuffer=assert(gpu.allocateBuffer(w,h),"显存不足，无法分配界面缓冲") end
assert(gpu.setActiveBuffer(frameBuffer)~=nil,"无法切换后台缓冲") end
local function draw(force) if rendering or (not force and computer.uptime()-lastFrame<1) then return end
rendering=true local ok,err=pcall(function()
beginFrame() if showCache then cacheView.draw(force) else paint() end
assert(gpu.bitblt(0,1,1,w,h,frameBuffer,1,1),"界面提交失败") end)
if frameBuffer then pcall(gpu.setActiveBuffer,oldBuffer or 0) end rendering=false;lastFrame=computer.uptime()
if not ok then logs[#logs+1]="界面刷新失败："..tostring(err);if #logs>20 then table.remove(logs,1) end end end
local function capture(...) local parts={...};for i,v in ipairs(parts) do parts[i]=tostring(v) end
local text=table.concat(parts," ") if cacheView then cacheView.log(text) end
logs[#logs+1]=text;if #logs>20 then table.remove(logs,1) end if text:find("程序停止",1,true) then fault=true end
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
local function handle(e) if showCache then
if cacheView.handle(e)=="back" then showCache=false;returnedAt=computer.uptime();draw(true) end draw(e[1]~=nil);return {}
end if e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=32 and e[3]<=55 then e={"key_down","ui",110,49} end
if e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=2 and e[3]<=28 then e={"key_down","ui",115,31}
end if e[1]=="touch" and e[5]==0 and e[4]==h-1 then
if e[3]>=2 and e[3]<=25 then e={"key_down","ui",113,16} elseif e[3]>=31 and e[3]<=49 then e={"key_down","ui",99,46}
elseif e[3]>=w-19 then draw(true);e={} end end
if e[1]=="key_down" and (e[3]==110 or e[3]==78) then cachePage=cachePage+1;draw(true);e={} end if e[1]=="key_down" and (e[3]==114 or e[3]==82) then draw(true);e={} end
if e[1]=="key_down" and (e[3]==115 or e[3]==83) then processPatterns();e={} end if e[1]=="key_down" and (e[3]==99 or e[3]==67) then
openSettings();e={} end
if e[1]=="key_down" and (e[3]==113 or e[3]==81) then if computer.uptime()-returnedAt<0.4 then e={} else stopRequested=true end
end return e
end local function mainUI()
gpu.setResolution(w,h);gpu.setBackground(bg) beginFrame();gpu.setActiveBuffer(oldBuffer or 0)
print=capture event.pull=function(n,filter) return coroutine.yield(n,filter) end
os.sleep=function(n) coroutine.yield(n) end draw(true)
if initialView=="cache" then openSettings() end if mode=="monitor" then
repeat handle({oldPull(0.25)});draw(false) until stopRequested else
local service=coroutine.create(function() controller(mode) end) local deadline,filter
local function advance(e) local ok,n,f=coroutine.resume(service,table.unpack(e or {}))
assert(ok,n);deadline=computer.uptime()+(tonumber(n) or math.huge);filter=f end
advance() while coroutine.status(service)~="dead" do
draw(false) local e=handle({oldPull(math.max(0,math.min(0.1,deadline-computer.uptime())))})
if stopRequested then e={"key_down","ui",113,16} end if e[1] and (not filter or filter==e[1]) then advance(e)
elseif computer.uptime()>=deadline then advance() end end
draw(true) if fault then repeat handle({oldPull(0.25)});draw(false) until stopRequested end
end end
local ok,err=xpcall(mainUI,debug.traceback) print,event.pull,os.sleep=oldPrint,oldPull,oldSleep
if frameBuffer then pcall(gpu.setActiveBuffer,oldBuffer or 0)
pcall(gpu.freeBuffer,frameBuffer) end
pcall(gpu.setResolution,oldW,oldH) pcall(gpu.setForeground,oldFg,fgPalette);pcall(gpu.setBackground,oldBg,bgPalette)
pcall(term.clear);pcall(term.setCursor,1,1) if not ok then oldPrint("界面退出："..tostring(err)) end
for i=math.max(1,#logs-5),#logs do oldPrint(logs[i]) end if mode=="monitor" then oldPrint("已退出只读监控。") end
