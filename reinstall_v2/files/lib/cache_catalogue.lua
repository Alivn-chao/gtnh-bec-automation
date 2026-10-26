-- Derived recipe requirements. One bounded index, never production/IO state.
local fs=require('filesystem');local ser=require('serialization')
return function(C,directory,storage)
 local M={};local path=C.path('state/cache-catalogue.dat');local entries,loaded={},false
 local LIMIT=65536
 local function integer(n,min)return type(n)=='number'and n>=min and n<=2147483647 and n%1==0 end
 local function stamp(file)
  if not fs.size or not fs.lastModified then return end
  local ok,size,modified=pcall(function()return fs.size(file),fs.lastModified(file)end)
  if ok and type(size)=='number'and size>=0 and type(modified)=='number'and modified>=0 then return tostring(size)..':'..tostring(modified)end
 end
 local function validEntry(e)
  if type(e)~='table'or type(e.stamp)~='string'or type(e.valid)~='boolean'or(e.count~=0 and e.count~=1)then return false end
  for _,key in ipairs({'names','totals','outputs'})do if type(e[key])~='table'then return false end end
  local n=0;for name,v in pairs(e.names)do n=n+1;if n>64 or type(name)~='string'or #name>80 or v~=true then return false end end
  for name,v in pairs(e.totals)do if not e.names[name]or not integer(v,1)then return false end end
  for name,v in pairs(e.outputs)do if type(name)~='string'or #name>256 or v~=true then return false end end
  return true
 end
 local function readIndex()
  if loaded then return end;loaded=true
  if not fs.size or not fs.lastModified or not fs.exists(path)then return end
  local ok,v=pcall(function()assert(fs.size(path)<=LIMIT);return C.read(path)end)
  if not ok or type(v)~='table'or v.version~=1 or v.directory~=directory or type(v.entries)~='table'then return end
  local n=0;for name,e in pairs(v.entries)do n=n+1;if n>512 or type(name)~='string'or not name:match('%.dat$')or not validEntry(e)then return end end
  entries=v.entries
 end
 local function inspect(recipe)
  local e={count=0,valid=false,names={},totals={},outputs={}}
  if not recipe or recipe.state~='converted'then return e end
  e.count=1;e.valid=true
  for _,f in ipairs(recipe.condensates or{})do
   assert(type(f.name)=='string'and #f.name<=80,'配方流体名称无效');e.names[f.name]=true
   if not integer(f.amount,1)then e.valid=false else e.totals[f.name]=(e.totals[f.name]or 0)+f.amount end
  end
  if not next(e.totals)then e.valid=false end
  for k,v in pairs(e.totals)do if not integer(v,1)then e.valid=false;e.totals[k]=nil end end
  for _,v in ipairs(recipe.outputs or{})do e.outputs[tostring(v.name)..':'..tostring(tonumber(v.damage or 0))]=true end
  return e
 end
 function M.scan(force)
  readIndex()
  local nextEntries,found,totals,outputs={},{},{},{};local count,files,reads,reused=0,0,0,0;local valid,changed,durable=true,false,true
  if fs.exists(directory)then for name in fs.list(directory)do if name:match('%.dat$')then
   files=files+1;assert(files<=512,'登记配方超过512份，请整理配方库')
   local file=directory..'/'..name;local version=stamp(file);local e=entries[name]
   if not force and version and e and e.stamp==version then reused=reused+1 else
    e=inspect(C.read(file));e.stamp=version;reads=reads+1;changed=true
   end
   if not version then durable=false end
   nextEntries[name]=e;count=count+e.count;valid=valid and e.valid
   for k in pairs(e.names)do found[k]=true end
   for k,v in pairs(e.totals)do totals[k]=math.max(totals[k]or 0,v)end
   for k in pairs(e.outputs)do outputs[k]=true end
  end end end
  for name in pairs(entries)do if not nextEntries[name]then changed=true end end
  entries=nextEntries
  local stats={recipes=files,read=reads,reused=reused,persisted=false}
  if durable and changed then
   local value={version=1,directory=directory,entries=entries};local text=ser.serialize(value,false)
   local disk=storage.status();stats.bytes=#text
   -- Optional derived data must never consume the 512 KiB production reserve.
   if #text<=LIMIT and disk.known and disk.ok and type(disk.free)=='number'and disk.free-#text*2-4096>=(disk.reserve or 524288)then
    local ok=pcall(C.write,path,value);stats.persisted=ok
   end
  end
  return found,valid and count>0 and{totals=totals,outputs=outputs,count=count}or nil,stats
 end
 return M
end
