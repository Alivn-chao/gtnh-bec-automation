-- Bounded maintenance: completed archives only; never remove live/recovery data.
local fs=require('filesystem');local ser=require('serialization')
return function(C)
 local S={reserve=524288}
 local function record(path)
  local f=io.open(path,'r');if not f then return end
  local text=f:read(65537);f:close();if not text or #text>65536 then return end
  local ok,r=pcall(ser.unserialize,text);if ok and type(r)=='table'then return r end
 end
 local function complete(r)
  if not r or r.stage~='stopped'or r.pending or r.plan or r.configOwned or r.naniteStage or r.pipeline then return false end
  for _,m in ipairs(r.transfers or {})do if m.ok~=true then return false end end
  for _,j in ipairs(r.requests or {})do if j.state~='done'then return false end end
  return true
 end
 local function prune(directory,pattern,valid,keep)
  if not fs.exists(directory)then return 0 end
  local rows={}
  for name in fs.list(directory)do
   local id=name:match(pattern)
   if id then local path=directory..'/'..name
    if valid(record(path))then rows[#rows+1]={path=path,id=tonumber(id),modified=fs.lastModified and fs.lastModified(path)or 0}end
   end
  end
  table.sort(rows,function(a,b)if a.modified==b.modified then return a.id>b.id end;return a.modified>b.modified end)
  local removed=0;for i=keep+1,#rows do if fs.remove(rows[i].path)then removed=removed+1 end end
  return removed
 end
 function S.prune(cfg)
  local removed=prune(C.ROOT,'^config%.dat%.hd%.bak%.(%d+)$',function(r)return r and r.version==2 and type(r.nodes)=='table'and type(r.groups)=='table'end,2)
  for i in ipairs(cfg.nodes)do
   local dir=C.path('state/node-'..i)
   for _,pattern in ipairs({'^production%.journal%.stopped%-(%d+)$','^production%.journal%.before%-resume%-(%d+)$'})do removed=removed+prune(dir,pattern,complete,3)end
  end
  return removed
 end
 function S.status()
  if not fs.get then return {known=false,ok=false,reserve=S.reserve}end
  local ok,device=pcall(fs.get,C.ROOT)
  if not ok or not device or not device.spaceTotal or not device.spaceUsed then return {known=false,ok=false,reserve=S.reserve}end
  local valid,total,used=pcall(function()return device.spaceTotal(),device.spaceUsed()end)
  if not valid or type(total)~='number'or type(used)~='number'then return {known=false,ok=false,reserve=S.reserve}end
  local free=math.max(0,total-used)
  return {known=true,free=free,total=total,reserve=S.reserve,ok=free>=S.reserve}
 end
 return S
end
