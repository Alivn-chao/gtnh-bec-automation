-- UI-only patch. Display caching never supplies data to the controller.
local fs=require('filesystem')
local path='/home/bec_ui.lua'
local function read(p)
 local f=assert(io.open(p,'r'));local text=f:read('*a');f:close();return assert(text)
end
local function replace(text,from,to)
 local a,b=text:find(from,1,true)
 assert(a and not text:find(from,b+1,true),'UI版本入口缺失或不唯一，原文件未改')
 return text:sub(1,a-1)..to..text:sub(b+1)
end
local original=read(path)
if original:find('BEC_V1_UI_SPEED_V1',1,true) then print('UI响应补丁已安装');return end
local modified=original:gsub('\r\n','\n')
local cache=[=[
-- BEC_V1_UI_SPEED_V1
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
]=]
modified=replace(modified,'local gate="cf2a0c4a-ab8d-4958-b1df-253094d6690c" local function get(address,method,...)',
 cache..'\nlocal gate="cf2a0c4a-ab8d-4958-b1df-253094d6690c" local function get(address,method,...)')
modified=replace(modified,[=[local ok,value=pcall(c.invoke,address,method,...) if ok then return value end
return nil end]=],[=[pollUI()
local key=address..":"..method
local cached=displayCache[key];local now=computer.uptime()
if cached and (now<cached.untilAt or stopRequested) then return cached.value end
if stopRequested then return nil end
local ttl=(method=="getMaxParallel") and 30 or 2
local ok,value=pcall(c.invoke,address,method,...)
if not ok then value=nil end
displayCache[key]={value=value,untilAt=computer.uptime()+ttl}
if ok then return value end return nil end]=])
modified=replace(modified,'local f=io.open(path or "/home/bec_auto.journal","r") if not f then return {} end',
 [=[path=path or "/home/bec_auto.journal";pollUI()
local cached=displayFiles[path];local now=computer.uptime()
if cached and (now<cached.untilAt or stopRequested) then return cached.value end
if stopRequested then return {} end
local f=io.open(path,"r") if not f then
 displayFiles[path]={value={},untilAt=now+2};return {} end]=])
modified=replace(modified,'return ok and type(value)=="table" and value or {} end',
 [=[value=ok and type(value)=="table" and value or {}
displayFiles[path]={value=value,untilAt=computer.uptime()+(path:match("%.config$") and 10 or path:match("%.dat$") and 60 or 2)}
return value end]=])
modified=replace(modified,'computer.uptime()-registryAt<5','computer.uptime()-registryAt<60')
modified=replace(modified,'local required,consumed=get(node,"getRequiredCondensate"),get(node,"getConsumedCondensate")',
 'local required=get(node,"getRequiredCondensate")')
modified=replace(modified,'computer.uptime()-lastFrame<1','computer.uptime()-lastFrame<2')
modified=replace(modified,'local nr=journal("/home/bec_nanites.journal") local ns={draining="退回旧蜂群",filling="装入蜂群",verifying="核对蜂群",done="切换完成"}',
 [=[local nr=journal("/home/bec_nanites_io.journal")
if nr.kind~="cell-io" then nr=journal("/home/bec_nanites.journal") end
local ns={draining="退回旧蜂群",filling="装入蜂群",verifying="核对蜂群",done="待命",
 loading="装入蜂群",loaded="装入已核对",recovering="回收蜂群",recovered="回收已核对",
 ["moving-cell"]="搬运存储盘",["waiting-port"]="端口传输中",["cell-moved"]="存储盘已搬入",
 ["port-complete"]="端口完成",prepared="准备换蜂"}]=])
modified=replace(modified,'elseif e[3]>=w-19 then draw(true);e={} end end',
 'elseif e[3]>=w-19 then clearDisplayCache();registryAt=-math.huge;draw(true);e={} end end')
modified=replace(modified,'(e[3]==114 or e[3]==82) then draw(true);e={} end',
 '(e[3]==114 or e[3]==82) then clearDisplayCache();registryAt=-math.huge;draw(true);e={} end')
modified=replace(modified,'draw(false) local e=handle({oldPull(math.max(0,math.min(0.1,deadline-computer.uptime())))})',
 'local e=handle({pullUI(math.max(0,math.min(0.1,deadline-computer.uptime())))})')
modified=replace(modified,'elseif computer.uptime()>=deadline then advance() end end',
 'elseif computer.uptime()>=deadline then advance() end if not stopRequested then draw(false) end end')
modified=replace(modified,'repeat handle({oldPull(0.25)});draw(false) until stopRequested else',
 'repeat handle({pullUI(0.1)});if not stopRequested then draw(false) end until stopRequested else')
modified=replace(modified,'if fault then repeat handle({oldPull(0.25)});draw(false) until stopRequested end',
 'if fault then repeat handle({pullUI(0.1)});if not stopRequested then draw(false) end until stopRequested end')
modified=replace(modified,'end draw(true)\nif initialView=="cache"',
 'end draw(true)\nif stopRequested then return end\nif initialView=="cache"')
assert(load(modified,'@'..path,'t',_ENV),'补丁后语法检查失败')
local n=1;while fs.exists(path..'.before-ui-speed-'..n) or fs.exists(path..'.ui-speed-new-'..n) do n=n+1 end
local backup,temp=path..'.before-ui-speed-'..n,path..'.ui-speed-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close()
assert(read(temp)==modified,'临时文件回读失败')
assert(fs.rename(path,backup),'备份失败，原文件保留')
if not fs.rename(temp,path) then assert(fs.rename(backup,path),'还原失败，原文件在 '..backup);error('替换失败，已还原') end
assert(read(path)==modified and read(backup)==original,'替换或备份回读失败')
print('UI响应补丁已安装；备份: '..backup)
print('生产控制器、订单和日志均未修改。正常Q停止后继续: lua /home/bec_ui.lua run')
