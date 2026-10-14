local mode,initialView=... mode=mode or "run"
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
