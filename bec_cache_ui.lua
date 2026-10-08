local view=(...)
if view~="embedded" and view~="standalone" then
 local service=assert(loadfile("/home/bec_ui.lua","t",_ENV),"缺少生产界面")
 return service("run","cache")
end
local embedded=view=="embedded"
local c=require("component")
local event=require("event")
local computer=require("computer")
local unicode=require("unicode")
local ser=require("serialization")
local fs=require("filesystem")
local term=require("term")
local gpu=assert(c.gpu,"需要显卡和屏幕")
local CONFIG="/home/bec_cache.config"
local target=144000
local function valid(n) return type(n)=="number" and n>=1 and n<=2147483647 and n==math.floor(n) end
local f=io.open(CONFIG,"r")
if f then
 local value=ser.unserialize(f:read("*a"));f:close()
 assert(type(value)=="table" and value.version==1 and valid(value.target),"缓存配置损坏，请保留文件核对")
 target=value.target
end
local worker=assert(loadfile("/home/bec_cache.lua","t",_ENV),"缺少 /home/bec_cache.lua")
local oldPrint,oldPull=print,event.pull
local oldW,oldH=gpu.getResolution()
local oldFg,fgPalette=gpu.getForeground()
local oldBg,bgPalette=gpu.getBackground()
local mw,mh=gpu.maxResolution()
assert(mw>=80 and mh>=25,"需要至少80×25屏幕")
local w,h=math.min(100,mw),math.min(30,mh)
local busy,editing,quit=false,false,false
local buffer,status,logs=tostring(target),"等待设置或补缓存",{}
local last=-math.huge
local names,page,registryAt={},1,-math.huge
local labels={entangled_chromaticglass="彩色玻璃",entangled_transcendentmetal="超时空金属",
 entangled_infinity="无尽",entangled_dimshiftedsuperfluid="维度偏移超流体",
 entangled_space="空间",entangled_spacetime="时空",entangled_time="时间",
 entangled_neutronium="中子素",entangled_cosmicneutronium="宇宙中子素",entangled_bedrockium="基岩锭",
 entangled_celestialtungsten="天界钨",entangled_hypogen="海珀珍",entangled_phononmedium="声子介质",
 entangled_quarkgluonplasma="夸克胶子等离子体",entangled_cosmicsolder="无尽宇宙焊料",
 entangled_mhdcsm="磁流体约束恒星物质",entangled_magmatter="磁物质",
 entangled_universium="宇宙素",entangled_eternity="永恒"}
local function log(text)
 logs[#logs+1]=tostring(text);if #logs>30 then table.remove(logs,1) end
end
local function refreshNames(stock)
 local wanted={}
 if fs.exists("/home/bec/recipes") then
  for filename in fs.list("/home/bec/recipes") do if filename:sub(-4)==".dat" then
   local input=assert(io.open("/home/bec/recipes/"..filename,"r"))
   local text=input:read("*a");input:close();local recipe=ser.unserialize(text)
   assert(type(recipe)=="table" and recipe.state=="converted" and type(recipe.condensates)=="table","配方记录未完成: "..filename)
   for _,fluid in ipairs(recipe.condensates) do assert(type(fluid.name)=="string","流体记录无效");wanted[fluid.name]=true end
  end end
 end
 for name,n in pairs(stock or {}) do if n>0 then wanted[name]=true end end
 names={};for name in pairs(wanted) do names[#names+1]={labels[name] or name,name} end
 table.sort(names,function(a,b) return a[2]<b[2] end)
 page=math.min(page,math.max(1,math.ceil(#names/8)))
 registryAt=computer.uptime()
end
local function line(y,text,color)
 text=tostring(text):gsub("[\r\n]"," ")
 while unicode.wlen(text)>w-3 do text=unicode.sub(text,1,-2) end
 gpu.setBackground(0x101820);gpu.setForeground(color or 0xeeeeee)
 gpu.fill(2,y,w-2,1," ");gpu.set(2,y,text)
end
local function draw(force)
 if not force and computer.uptime()-last<0.5 then return end
 last=computer.uptime()
 line(2,"BEC 预缓存   |   统一库存配置",0x55ccff)
 line(4,"状态："..status,busy and 0x77ee77 or 0xeeeeee)
 line(6,"每种凝聚物目标："..(editing and buffer.."_" or tostring(target)).." mB",0x55ccff)
 line(7,editing and "输入数字；Enter 保存，Esc 取消，Backspace 删除" or "[ E 修改目标 ]   [ B 补缓存 ]   [ P 预览 ]")
 local ok,stock=pcall(c.invoke,"237a9cac-118a-4b74-8755-0d0b0ad216c0","getStoredCondensate")
 stock=ok and type(stock)=="table" and stock or nil
 if force or computer.uptime()-registryAt>=5 then
  local loaded,reason=pcall(refreshNames,stock);if not loaded then registryAt=computer.uptime();log(reason) end
 end
 line(8,"登记/已有流体 "..#names.." 种   第 "..page.." / "..math.max(1,math.ceil(#names/8)).." 页 [ N 下一页 ]",0x55ccff)
 for i=1,8 do
  local row=names[(page-1)*8+i]
  local value=row and stock and (stock[row[2]] or 0) or nil
  line(8+i,row and row[1].."："..tostring(value or "?").." / "..target.." mB" or "")
 end
 line(17,"只补已登记配方涉及的类型；整批转换可能略超目标。",0xaaaaaa)
 line(18,embedded and "常驻服务空闲时自动补库；Q返回生产界面，补库继续。" or "补缓存前先退出生产服务；完成后可回生产界面。",0xaaaaaa)
 line(19,"最近日志",0x55ccff)
 local count=h-22
 for i=1,count do line(19+i,logs[math.max(1,#logs-count+1)+i-1] or "",0xaaaaaa) end
 line(h-1,embedded and "[ Q 返回生产界面，补库继续 ]" or (busy and "[ Q 暂停补缓存并退出 ]" or "[ Q 退出 ]   [ R 刷新 ]"),0x55ccff)
end
local function write(path,text)
 local out=assert(io.open(path,"w"));assert(out:write(text));out:flush();out:close()
 out=assert(io.open(path,"r"));local saved=out:read("*a");out:close()
 assert(saved==text,"配置保存回读不一致")
end
local function save()
 local n=tonumber(buffer);assert(valid(n),"请输入有效正整数mB")
 local previous=io.open(CONFIG,"r")
 if previous then
  local old=previous:read("*a");previous:close()
  local i=1;while fs.exists(CONFIG..".backup-"..i) do i=i+1 end
  write(CONFIG..".backup-"..i,old)
 end
 write(CONFIG,ser.serialize({version=1,target=n},false))
 target=n;editing=false;status="配置已保存，下次启动仍使用此目标"
end
local function capture(...)
 local parts={...};for i,v in ipairs(parts) do parts[i]=tostring(v) end
 local text=table.concat(parts," ");log(text)
 if text:find("预缓存停止",1,true) then status="补缓存停止，查看日志"
 elseif text:find("预缓存完成",1,true) then status="预缓存完成"
 elseif text:find("只读规划完成",1,true) then status="只读预览完成" end
 if not embedded then draw(false) end
end
local function pull(seconds,filter)
 if quit then return "key_down","ui",113,16 end
 local deadline=computer.uptime()+(seconds or math.huge)
 repeat
  draw(false)
  local e={oldPull(math.max(0,math.min(0.25,deadline-computer.uptime())))}
  if e[1]=="touch" and e[5]==0 and e[4]==h-1 then
   if e[3]>=2 and e[3]<=25 then e={"key_down","ui",113,16}
   elseif e[3]>=w-19 then draw(true);e={}
   else e={} end
  end
  if e[1]=="key_down" and (e[3]==113 or e[3]==81) then quit=true end
  if e[1] and (not filter or e[1]==filter) then return table.unpack(e) end
 until computer.uptime()>=deadline
end
local function execute(preview)
 busy=true;status=preview and "读取配方与库存" or "按差额补缓存";draw(true)
 local ok,err=pcall(worker,preview and "preview-stock" or "run-stock",target)
 busy=false
 if not ok then status="补缓存停止，查看日志";log(err) end
 draw(true)
end
local function handle(e)
  if embedded and ((e[1]=="key_down" and (e[3]==113 or e[3]==81))
   or (e[1]=="touch" and e[5]==0 and e[4]==h-1 and e[3]<=25)) then editing=false;buffer=tostring(target);return "back" end
  if e[1]=="touch" and e[5]==0 then
   if e[4]==6 then e={"key_down","ui",101}
   elseif e[4]==7 then e={"key_down","ui",e[3]<24 and 101 or (e[3]<40 and 98 or 112)}
   elseif e[4]==8 then e={"key_down","ui",110} end
  end
  if e[1]=="key_down" then
   local ch,code=e[3],e[4]
   if editing then
    if code==1 then editing=false
    elseif ch==13 or code==28 then
     local ok,err=pcall(save);if not ok then status=tostring(err) end
    elseif ch==8 or code==14 then buffer=buffer:sub(1,-2)
    elseif type(ch)=="number" and ch>=48 and ch<=57 and #buffer<10 then buffer=buffer..string.char(ch) end
   elseif ch==101 or ch==69 then editing=true;buffer="";status="修改统一库存目标"
   elseif ch==98 or ch==66 then
    if embedded then buffer=tostring(target);local ok,err=pcall(save);status=ok and "已启用自动补缓存，空闲时执行" or tostring(err)
    else execute(false) end
   elseif ch==112 or ch==80 then execute(true) end
   if not editing and (ch==110 or ch==78) then page=page%math.max(1,math.ceil(#names/8))+1 end
   draw(true)
  end
end
if embedded then
 return {draw=draw,handle=handle,log=capture}
end
local function main()
 gpu.setResolution(w,h);gpu.setBackground(0x101820);gpu.fill(1,1,w,h," ")
 print=capture;event.pull=pull;draw(true)
 while not quit do handle({pull(0.5)}) end
end
local ok,err=xpcall(main,debug.traceback)
print,event.pull=oldPrint,oldPull
pcall(gpu.setResolution,oldW,oldH)
pcall(gpu.setForeground,oldFg,fgPalette);pcall(gpu.setBackground,oldBg,bgPalette)
pcall(term.clear);pcall(term.setCursor,1,1)
if not ok then oldPrint("缓存界面退出："..tostring(err)) end
for i=math.max(1,#logs-5),#logs do oldPrint(logs[i]) end
