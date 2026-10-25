-- Compatible with the background cache's binding-scoped route record.
local ser=require('serialization')
return function(C,cfg,group)
 local function raw(path)local f=io.open(path,'r');if not f then return end;local text=f:read('*a');f:close();return text end
 local formal=raw(C.path('config.dat'));local path=C.path('state/group-'..group..'/cache-discovery.dat')
 local memo={ports=nil,rawNames={}};local persisted
 local allowed={};for _,a in ipairs(cfg.groups[group].bulkTransposers or {})do allowed[a]=true end
 local function side(v)return type(v)=='number'and v%1==0 and v>=0 and v<=5 end
 local function valid(v)
  if not formal or type(v)~='table'or v.version~=1 or v.binding~=formal or type(v.ports)~='table'or type(v.rawNames)~='table'then return false end
  local count=0
  for name,r in pairs(v.ports)do
   count=count+1;if count>64 or type(name)~='string'or #name>80 or type(r)~='table'or not allowed[r.address]or not side(r.from)or not side(r.to)or r.from==r.to then return false end
  end
  count=0;for k,v in pairs(v.rawNames)do count=count+1;if count>64 or type(k)~='string'or #k>80 or type(v)~='string'or #v>80 then return false end end
  return true
 end
 if formal then local ok,saved=pcall(C.read,path)
  if ok and valid(saved)then memo.ports=saved.ports;memo.rawNames=saved.rawNames;persisted=ser.serialize(saved,false)end
 end
 local function save()
  if not formal or not memo.ports then return end
  assert(raw(C.path('config.dat'))==formal,'生产期间正式绑定变化，保留供液记录')
  local value={version=1,binding=formal,ports=memo.ports,rawNames=memo.rawNames};local text=ser.serialize(value,false)
  if text~=persisted then C.write(path,value);persisted=text end
 end
 return memo,save
end
