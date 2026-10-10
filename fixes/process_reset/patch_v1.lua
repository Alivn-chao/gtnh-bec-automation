-- Patch installed V1 files, preserving their original contents and all journals.
local fs=require('filesystem')
local c=require('component')
local AUTO='/home/bec_auto.lua'
local UI='/home/bec_ui.lua'
local MARK='BEC_V1_NEXT_RECIPE_V1'
local function read(path)
 local f=assert(io.open(path,'r'),'无法读取 '..path);local text=f:read('*a');f:close()
 return assert(text)
end
local function replace(text,from,to)
 local a,b=text:find(from,1,true)
 assert(a and not text:find(from,b+1,true),'V1补丁入口缺失或不唯一，原文件未修改')
 return text:sub(1,a-1)..to..text:sub(b+1)
end
local reset=[=[
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
]=]
local tierOld=[=[
switchNanites();if stopping then break end;verifyGate(filters);pause(0);deadline=computer.uptime()+600;v=call(NODE,"getState") end
]=]
local tierNew=[=[
switchNanites();if stopping then break end
print("蜂群需求变化，保持暂停，重新核对当前配方过滤和库存。")
break end
]=]
local idleOld=[=[
lastRequired=req end if v=="idle" then local consumed=call(NODE,"getConsumedCondensate") assert(type(consumed)=="table","节点空闲后消耗记录不可读") for name,need in pairs(lastRequired) do assert(integer(consumed[name] or 0)>=need, "节点进入空闲但凝聚物未消耗完，可能故障关闭: "..name.."；需求 "..need.."，已消耗 "..tostring(consumed[name] or 0))
end break end if waiting[v] then break end
]=]
local idleNew=[=[
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
 break end if waiting[v] then break end
]=]
local function patchAuto(text)
 if text:find(MARK,1,true) then return text end
 assert(text:find('local NANITES=',1,true) and text:find('local function configureGate',1,true),
  '不是已支持的V1蜂群/过滤控制器')
 text=text:gsub('\r\n','\n')
 text=replace(text,tierOld:sub(1,-2),tierNew:sub(1,-2))
 text=replace(text,idleOld:sub(1,-2),idleNew:sub(1,-2))
 text=replace(text,'mode=="restock", "用法: preview / run / resume / restock，无需填写数量"',
  'mode=="restock" or mode=="reset", "用法: preview / run / resume / restock / reset，无需填写数量"')
 text=replace(text,'tanks(5,nil) if fs.exists(JOURNAL)', 'tanks(5,nil)\n'..reset..'\nif fs.exists(JOURNAL)')
 return text
end
local originalAuto,originalUI=read(AUTO),read(UI)
local modifiedAuto=patchAuto(originalAuto)
local modifiedUI=originalUI
if not modifiedUI:find('mode=="reset"',1,true) then
 modifiedUI=replace(modifiedUI,'mode=="restock","用法: run / resume / monitor / restock"',
  'mode=="restock" or mode=="reset","用法: run / resume / monitor / restock / reset"')
end
local UPLOAD='/home/bec_upload.lua'
local originalUpload,modifiedUpload
if fs.exists(UPLOAD) then
 originalUpload=read(UPLOAD);modifiedUpload=originalUpload
 if not modifiedUpload:find('local recentBackups = {}',1,true) then
  modifiedUpload=replace(modifiedUpload,'local mode = (...) or "full"','local mode = (...) or "recent"')
  local a,b=assert(modifiedUpload:find('assert(mode == "full"',1,true))
  b=assert(modifiedUpload:find('\n',b+1,true))
  modifiedUpload=modifiedUpload:sub(1,a-1)..'assert(mode == "recent" or mode == "full" or mode == "status" or mode == "ioport", "用法：recent/full/status/ioport")\n'..modifiedUpload:sub(b+1)
  modifiedUpload=replace(modifiedUpload,'local files = {}',[=[local files = {}
local recentBackups = {}
if mode == "recent" and fs.exists("/home") then
 local groups={}
 for name in fs.list("/home") do
  local journal,suffix,index=name:match("^(bec_[A-Za-z0-9_%-]+%.journal)%.([A-Za-z0-9_%-]+)%-(%d+)$")
  if journal then
   groups[journal]=groups[journal] or {}
   local ok,time=pcall(fs.lastModified,fs.concat("/home",name))
   groups[journal][#groups[journal]+1]={name=name,index=tonumber(index),time=ok and tonumber(time) or 0}
  end
 end
 for _,group in pairs(groups) do
  table.sort(group,function(a,b)
   if a.time~=b.time then return a.time>b.time end
   if a.index~=b.index then return a.index>b.index end
   return a.name>b.name
  end)
  for i=1,math.min(2,#group) do recentBackups[group[i].name]=true end
 end
end]=])
  modifiedUpload=replace(modifiedUpload,'if name:match("^bec_upload") then return false end',[=[if name:match("^bec_upload") then return false end
  if mode == "recent" then
   return name:match("^bec_[A-Za-z0-9_%-]+%.lua$")
    or name:match("^bec_[A-Za-z0-9_%-]+%.journal$")
    or name:match("^bec_[A-Za-z0-9_%-]+%.journal%.previous$")
    or recentBackups[name] or name:match("^bec_[A-Za-z0-9_%-]+%.config$")
    or name:match("^bec_[A-Za-z0-9_%-]+%.cfg$")
  end]=])
 end
 assert(load(modifiedUpload,'@'..UPLOAD,'t',_ENV),'精简上传器语法检查失败')
end
assert(load(modifiedAuto,'@'..AUTO,'t',_ENV),'控制器语法检查失败')
assert(load(modifiedUI,'@'..UI,'t',_ENV),'UI语法检查失败')
assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先停止生产UI，保持暂停15')
assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
 and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'纠缠装置须停机')
local function install(path,original,modified)
 if original==modified then return end
 local n=1;while fs.exists(path..'.before-next-'..n) or fs.exists(path..'.next-new-'..n) do n=n+1 end
 local backup,temp=path..'.before-next-'..n,path..'.next-new-'..n
 local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close()
 assert(read(temp)==modified,'临时文件回读不符')
 assert(fs.rename(path,backup),'备份失败，原文件保留')
 if not fs.rename(temp,path) then
  assert(fs.rename(backup,path),'还原失败，原文件在 '..backup)
  error('替换失败，已还原原文件')
 end
 assert(read(path)==modified and read(backup)==original,'替换或备份回读不符')
 print('V1补丁已安装；旧程序保留: '..backup)
end
install(AUTO,originalAuto,modifiedAuto)
install(UI,originalUI,modifiedUI)
if modifiedUpload then
 install(UPLOAD,originalUpload,modifiedUpload)
 print('上传默认只传当前文件、上一份日志及最近两次备份；不传全部历史。')
end
print('安装未修改日志或启动生产。重置并重新启动: lua /home/bec_ui.lua reset')
