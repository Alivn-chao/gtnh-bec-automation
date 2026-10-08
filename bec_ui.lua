-- Chinese dashboard wrapping the proven controller. No independent machine writes.
local mode,initialView=...
mode=mode or "run"
local c=require("component")
local event=require("event")
local computer=require("computer")
local unicode=require("unicode")
local ser=require("serialization")
local term=require("term")
local gpu=c.gpu
assert(gpu,"需要显卡和屏幕")
assert(mode=="run" or mode=="resume" or mode=="monitor" or mode=="restock","用法: run / resume / monitor / restock")
local controller
if mode~="monitor" then controller=assert(loadfile("/home/bec_auto.lua","t",_ENV),"缺少 /home/bec_auto.lua") end
local main="3afdc4cf-04e3-4ae9-8be6-e753c23a249d"
local sub="86311657-33d1-41b5-a0d9-0aee7b5c2c50"
local storage="237a9cac-118a-4b74-8755-0d0b0ad216c0"
local node="b04787f9-5423-4b03-8549-c786d4ef38d0"
local gen="c1ae3f7c-f714-4c27-baf3-392d94a0aa50"
local rs="266f65b5-20be-4543-8f2f-bfd2d0816611"
local fluids={{"彩色玻璃","molten.chromaticglass","entangled_chromaticglass"},
 {"超时空金属","molten.transcendentmetal","entangled_transcendentmetal"}}
local states={idle="等待订单",crafting="生产中",["paused-immediate"]="立即暂停",
 ["assembler-offline"]="等待观测阵列",unpowered="等待供电",["nanite-tier-too-low"]="蜂群等级不足"}
local stages={starting="启动",waiting="等待订单 / 机器",["stream-planned"]="计算整批需求",
 ["stream-configuring"]="配置供液",["stream-crafting"]="主网合成并收料",
 ["stream-transfer-confirmed"]="持续收料",["stream-craft-done"]="合成完成 / 收料",
 ["stream-inlet-cleared"]="退回接口余料",["stream-prepared"]="整批原液已齐",
 ["craft-request-pending"]="记录原液申请",["transfer-pending"]="记录搬运",
 ["transfer-returned"]="核对搬运",converting="转换凝聚物",watching="连续生产",
 stopped="服务已暂停",["craft-paused"]="已暂停 / 原液申请待核对"}
local oldPrint,oldPull,oldSleep=print,event.pull,os.sleep
local oldW,oldH=gpu.getResolution()
local oldFg,fgPalette=gpu.getForeground()
local oldBg,bgPalette=gpu.getBackground()
local maxW,maxH=gpu.maxResolution()
assert(maxW>=80 and maxH>=25,"界面需要至少80×25的显卡和屏幕")
local w,h=math.min(100,maxW),math.min(30,maxH)
local logs,lastFrame,rendering={},-math.huge,false
local started=computer.uptime()
local fault,stopRequested=false,false
local cacheView,showCache
local returnedAt=-math.huge
local patternBusy,lastPattern=false,-math.huge
local bg,fg,muted,accent,good,bad=0x101820,0xeeeeee,0xaaaaaa,0x55ccff,0x77ee77,0xff7777
local function get(address,method,...)
 local ok,value=pcall(c.invoke,address,method,...)
 if ok then return value end
 return nil
end
local function inventory(address)
 local rows=get(address,"getFluidsInNetwork")
 if type(rows)~="table" then return nil end
 local result={}
 for _,f in pairs(rows) do if type(f)=="table" and f.name then
  result[f.name]=(result[f.name] or 0)+(tonumber(f.amount or f.size) or 0)
 end end
 return result
end
local function journal(path)
 local f=io.open(path or "/home/bec_auto.journal","r")
 if not f then return {} end
 local text=f:read("*a");f:close()
 local ok,value=pcall(ser.unserialize,text)
 return ok and type(value)=="table" and value or {}
end
local function fit(text,width)
 text=tostring(text or "读取失败"):gsub("[\r\n]"," ")
 while unicode.wlen(text)>width do text=unicode.sub(text,1,-2) end
 return text
end
local function line(y,text,color)
 gpu.setBackground(bg);gpu.setForeground(color or fg)
 gpu.fill(2,y,w-2,1," ");gpu.set(2,y,fit(text,w-3))
end
local function amount(t,key)
 if type(t)~="table" then return "?" end
 return tostring(t[key] or 0)
end
local function toggle(value)
 if value==nil then return "读取失败" end
 return value and "开启" or "关闭"
end
local function paint()
 local state=get(node,"getState")
 local record=journal()
 local caching=record.stage=="cache-working"
 if caching then record=journal("/home/bec_cache.journal") end
 local stock=get(storage,"getStoredCondensate")
 local required,consumed=get(node,"getRequiredCondensate"),get(node,"getConsumedCondensate")
 local a,b=inventory(main),inventory(sub)
 local seconds=math.floor(computer.uptime()-started)
 line(2,"BEC 自动化   |   原始屏蔽层   |   "..(mode=="monitor" and "只读监控" or "常驻服务"),accent)
 line(4,"状态："..(fault and "程序已退出，查看下方原因" or (caching and "空闲自动补缓存") or states[state] or tostring(state)),fault and bad or good)
 line(5,"阶段："..(stages[record.stage] or record.stage or "尚无日志"))
 line(6,"本轮记录份数："..tostring(record.batchCount or "--").."   当前并行："..tostring(get(node,"getParallelRecipesInProgress")).."   界面运行："..seconds.." 秒")
 local tier=get(node,"getProvidedTier")
 line(7,"蜂群等级："..tostring(type(tier)=="table" and tier.tier or "?").."   数量："..tostring(get(node,"getAvailableNanites")))
 line(9,"原液与凝聚物库存 / 本轮目标（mB）",accent)
 for i,f in ipairs(fluids) do
  local y=10+(i-1)*4
  line(y,f[1],accent)
  line(y+1,"主网原液 "..amount(a,f[2]).."   子网原液 "..amount(b,f[2]).." / "..amount(record.expected,f[2]))
  line(y+2,"凝聚物   "..amount(stock,f[3]).." / "..amount(record.target,f[3]))
  line(y+3,"当前节点已消耗 "..amount(consumed,f[3]).." / "..amount(required,f[3]),muted)
 end
 line(18,"纠缠装置："..toggle(get(gen,"isWorkAllowed")).."   约束场："..toggle(get(storage,"isWorkAllowed")).."   暂停输出："..tostring(get(rs,"getOutput",require("sides").top)))
 line(19,"最近日志",accent)
 local count=h-23
 for i=1,count do line(19+i,logs[math.max(1,#logs-count+1)+i-1] or "",muted) end
 gpu.setBackground(0x334455);gpu.setForeground(fg);gpu.fill(2,h-1,w-2,1," ")
 gpu.set(3,h-1,mode=="monitor" and "[ Q 退出监控 ]" or "[ Q 暂停并退出 ]")
 gpu.set(31,h-1,"[ C 缓存设置 ]")
 gpu.set(w-19,h-1,"[ R 刷新 ]")
 line(h-2,mode=="monitor" and "样板处理：只读监控模式不可修改" or "[ S 处理工坊样板 ]",accent)
end
local function draw(force)
 if rendering or (not force and computer.uptime()-lastFrame<1) then return end
 rendering=true
 local ok,err=pcall(function() if showCache then cacheView.draw(force) else paint() end end)
 rendering=false;lastFrame=computer.uptime()
 if not ok then oldPrint("界面刷新失败："..tostring(err)) end
end
local function capture(...)
 local parts={...};for i,v in ipairs(parts) do parts[i]=tostring(v) end
 local text=table.concat(parts," ")
 if cacheView then cacheView.log(text) end
 logs[#logs+1]=text;if #logs>20 then table.remove(logs,1) end
 if text:find("程序停止",1,true) then fault=true end
 draw(false)
end
local function processPatterns()
 if mode=="monitor" then capture("只读监控模式，请在生产界面处理样板");return end
 if patternBusy or computer.uptime()-lastPattern<1 then return end
 patternBusy=true;lastPattern=computer.uptime()
 capture("开始处理工坊9槽样板；已登记样板自动跳过。")
 local ok,err=pcall(function()
  local worker,reason=loadfile("/home/bec_patterns.lua","t",_ENV)
  assert(worker,"缺少样板脚本："..tostring(reason));worker("run")
 end)
 patternBusy=false
 if not ok then capture("样板处理失败："..tostring(err)) end
 draw(true)
end
local function openSettings()
 if mode=="monitor" then capture("只读监控不修改缓存配置");return end
 if not cacheView then
  local ok,value=pcall(function()
   return assert(loadfile("/home/bec_cache_ui.lua","t",_ENV),"缺少缓存界面")("embedded")
  end)
  if not ok or type(value)~="table" then capture("缓存界面打开失败："..tostring(value));return end
  cacheView=value
 end
 showCache=true;gpu.fill(1,1,w,h," ");draw(true)
end
local function handle(e)
 if showCache then
  if cacheView.handle(e)=="back" then showCache=false;returnedAt=computer.uptime();gpu.fill(1,1,w,h," ");draw(true) end
  return {}
 end
  if e[1]=="touch" and e[5]==0 and e[4]==h-2 and e[3]>=2 and e[3]<=28 then
   e={"key_down","ui",115,31}
  end
  if e[1]=="touch" and e[5]==0 and e[4]==h-1 then
   if e[3]>=2 and e[3]<=25 then e={"key_down","ui",113,16}
   elseif e[3]>=31 and e[3]<=49 then e={"key_down","ui",99,46}
   elseif e[3]>=w-19 then draw(true);e={} end
  end
  if e[1]=="key_down" and (e[3]==114 or e[3]==82) then draw(true);e={} end
  if e[1]=="key_down" and (e[3]==115 or e[3]==83) then processPatterns();e={} end
  if e[1]=="key_down" and (e[3]==99 or e[3]==67) then
   openSettings();e={}
  end
  if e[1]=="key_down" and (e[3]==113 or e[3]==81) then
   if computer.uptime()-returnedAt<0.4 then e={} else stopRequested=true end
  end
 return e
end
local function mainUI()
 gpu.setResolution(w,h);gpu.setBackground(bg);gpu.fill(1,1,w,h," ")
 print=capture
 event.pull=function(n,filter) return coroutine.yield(n,filter) end
 os.sleep=function(n) coroutine.yield(n) end
 draw(true)
 if initialView=="cache" then openSettings() end
 if mode=="monitor" then
  repeat handle({oldPull(0.25)});draw(false) until stopRequested
 else
  local service=coroutine.create(function() controller(mode) end)
  local deadline,filter
  local function advance(e)
   local ok,n,f=coroutine.resume(service,table.unpack(e or {}))
   assert(ok,n);deadline=computer.uptime()+(tonumber(n) or math.huge);filter=f
  end
  advance()
  while coroutine.status(service)~="dead" do
   draw(false)
   local e=handle({oldPull(math.max(0,math.min(0.1,deadline-computer.uptime())))})
   if stopRequested then e={"key_down","ui",113,16} end
   if e[1] and (not filter or filter==e[1]) then advance(e)
   elseif computer.uptime()>=deadline then advance() end
  end
  draw(true)
  if fault then repeat handle({oldPull(0.25)});draw(false) until stopRequested end
 end
end
local ok,err=xpcall(mainUI,debug.traceback)
print,event.pull,os.sleep=oldPrint,oldPull,oldSleep
pcall(gpu.setResolution,oldW,oldH)
pcall(gpu.setForeground,oldFg,fgPalette);pcall(gpu.setBackground,oldBg,bgPalette)
pcall(term.clear);pcall(term.setCursor,1,1)
if not ok then oldPrint("界面退出："..tostring(err)) end
for i=math.max(1,#logs-5),#logs do oldPrint(logs[i]) end
if mode=="monitor" then oldPrint("已退出只读监控。") end
