local memo=discoveryByGroup[group]
  local discoveryPath=C.path('state/group-'..group..'/cache-discovery.dat')
  local function validSaved(v)
   if type(v)~='table'or v.version~=1 or v.binding~=ctx.formal or type(v.ports)~='table'or type(v.rawNames)~='table'then return false end
   local allowed={};for _,a in ipairs(g.bulkTransposers or {})do allowed[a]=true end
   local count=0
   for raw,r in pairs(v.ports)do
    count=count+1;if count>64 or type(raw)~='string'or #raw>80 or type(r)~='table'or not allowed[r.address]
     or not integer(r.from,0)or r.from>5 or not integer(r.to,0)or r.to>5 or r.from==r.to then return false end
   end
   count=0;for kind,raw in pairs(v.rawNames)do count=count+1;if count>64 or type(kind)~='string'or #kind>80 or type(raw)~='string'or #raw>80 then return false end end
   return true
  end
  if not memo then
   memo={rawNames={}}
   if not skipSavedDiscovery then local ok,saved=pcall(C.read,discoveryPath);if ok and validSaved(saved)then memo.ports=saved.ports;memo.rawNames=saved.rawNames;memo.persisted=ser.serialize(saved,false)end end
  end
  memo.catalogue=discoveredCatalogue;discoveryByGroup[group]=memo
  env.BEC_V3_CACHE_DISCOVERY=memo
  env.BEC_V3_CACHE_SAVE_DISCOVERY=function()
   if not memo.ports then return end
   local saved={version=1,binding=ctx.formal,ports=memo.ports,rawNames=memo.rawNames};local text=ser.serialize(saved,false)
   if text~=memo.persisted then C.write(discoveryPath,saved);memo.persisted=text end
  end