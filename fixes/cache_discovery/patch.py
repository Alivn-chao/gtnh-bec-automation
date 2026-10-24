from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def swap(text,old,new):
 assert text.count(old)==1,(old[:100],text.count(old))
 return text.replace(old,new)
def patch(name,text):
 if name=='lib/cache.lua':
  if "E.nodeWork(i,true)" in text:
   text=swap(text,"for i,n in ipairs(cfg.nodes)do if n.group==group then c.invoke(n.redstone,'setOutput',n.pauseSide,15);E.nodeWork(i,true)end end","for i,n in ipairs(cfg.nodes)do if n.group==group then c.invoke(n.redstone,'setOutput',n.pauseSide,15);E.nodeWork(i,false)end end")
   text=swap(text,"  local function guard()", """  -- State reads and workAllowed writes are separate server callbacks. An idle
  -- node may already have admitted an order before the cache closed admission.
  -- Yield the leases BEFORE loading the cache runtime or creating its journal.
  for _,member in ipairs(cfg.nodes)do if member.group==group then
   if c.invoke(member.address,'getState')~='idle'then
    log('节点已接单或不再空闲，缓存尚未搬液/下单，交回生产调度。')
    return true
   end
  end end
  local function guard()""")
   text=swap(text,"   for _,member in ipairs(cfg.nodes)do if member.group==group then\n    assert(c.invoke(member.redstone,'getOutput',member.pauseSide)==15,'缓存期间节点暂停信号变化')", "   for _,member in ipairs(cfg.nodes)do if member.group==group then\n    assert(c.invoke(member.redstone,'getOutput',member.pauseSide)==15,'缓存期间节点暂停信号变化')\n    assert(c.invoke(member.address,'isWorkAllowed')==false,'缓存期间节点接单许可被重新开启')")
   text=swap(text,"    -- Keep immediate pause asserted, but allow idle nodes to admit a new order\n    -- so the V1 priority check can see physical inputs as well as AE queues.","    -- Cache owns the same physical supply path as production. Closing work\n    -- permission prevents a new recipe from racing guard() as crafting while\n    -- the immediate-pause signal is still being processed. AE priority checks\n    -- remain active; admission is reopened by E only after clean lease release.")
  text=swap(text,'local catalogueReady=false;local displayedStock={}','local catalogueReady=false;local displayedStock={}\n local discoveryByGroup,discoveredCatalogue={},nil -- BEC_V3_FIXED_DISCOVERY_1')
  start=text.index(' local function scan(force)');end=text.index(' -- Only these small settings/page operations',start)
  text=text[:start]+''' local function scan(force)
  if catalogueReady and not force then return end
  if force then discoveryByGroup={}end
  local found,totals,outputs={},{},{};local count,valid=0,true
  if fs.exists(cfg.recipeDirectory)then for name in fs.list(cfg.recipeDirectory)do if name:match('%.dat$')then
   local r=C.read(cfg.recipeDirectory..'/'..name)
   if r and r.state=='converted'then
    count=count+1;local demand={}
    for _,f in ipairs(r.condensates or {})do
     assert(type(f.name)=='string'and #f.name<=80,'配方流体名称无效');found[f.name]=true
     if not integer(f.amount,1)then valid=false else demand[f.name]=(demand[f.name]or 0)+f.amount end
    end
    if not next(demand)then valid=false end
    for k,v in pairs(demand)do if not integer(v,1)then valid=false end;totals[k]=math.max(totals[k]or 0,v)end
    for _,v in ipairs(r.outputs or {})do outputs[tostring(v.name)..':'..tostring(tonumber(v.damage or 0))]=true end
   else valid=false end
  end end end
  discoveredCatalogue=valid and count>0 and {totals=totals,outputs=outputs,count=count}or nil
  names={};for name in pairs(found)do names[#names+1]=name end;table.sort(names);assert(#names<=64,'登记缓存类型超过64种');catalogueReady=true
 end
 function K.invalidateCatalogue()
  catalogueReady=false;discoveredCatalogue=nil
  for _,memo in pairs(discoveryByGroup)do memo.catalogue=nil end
 end
'''+text[end:]
  text=swap(text,'env.BEC_V2_CACHE_GUARD=guard', '''local discovery=discoveryByGroup[group]or {rawNames={}}
  discovery.catalogue=discoveredCatalogue;discoveryByGroup[group]=discovery
  env.BEC_V3_CACHE_DISCOVERY=discovery
  env.BEC_V2_CACHE_GUARD=guard''')
  text=swap(text,'local discoveryByGroup,discoveredCatalogue={},nil','local discoveryByGroup,discoveredCatalogue={},nil;local skipSavedDiscovery=false')
  text=swap(text,'if force then discoveryByGroup={}end','if force then discoveryByGroup={};skipSavedDiscovery=true end')
  text=swap(text,'''local discovery=discoveryByGroup[group]or {rawNames={}}
  discovery.catalogue=discoveredCatalogue;discoveryByGroup[group]=discovery
  env.BEC_V3_CACHE_DISCOVERY=discovery''',Path(__file__).with_name('persist_host.lua.inc').read_text(encoding='utf-8'))
 else:
  text=swap(text,'end local function bulkPorts() local allowed,ports={},{}','''end
local discovery=BEC_V3_CACHE_DISCOVERY -- Session memo; bindings recreate the host.
if discovery then for kind,raw in pairs(discovery.rawNames)do
 local base=mapping[kind]
 local valid=base and (raw==base or raw=='fluid.'..base or kind=='entangled_space'and(raw=='spatialfluid'or raw=='fluid.spatialfluid')or kind=='entangled_time'and(raw=='temporalfluid'or raw=='fluid.temporalfluid'))
 if not valid then discovery.rawNames[kind]=nil end
end end
local function probeRoute(route,raw)
 if call(route.address,"getTankCount",route.from)~=1 or call(route.address,"getTankCapacity",route.from,1)~=2147483647
  or call(route.address,"getTankCount",route.to)~=6 or call(route.address,"getTankCapacity",route.to,1)~=16000 then return false end
 local f=call(route.address,"getFluidInTank",route.from,1);if type(f)=="table"and type(f[1])=="table"then f=f[1]end
 return type(f)=="table"and (f.name==raw or not f.name and tonumber(f.amount or 0)==0)
end
local function bulkPorts(required)
 if discovery and discovery.ports then
  local valid=true
  for kind in pairs(required or {})do
   local raw=mapping[kind];local route=discovery.ports[raw]
   local ok,match=false,false;if route then ok,match=pcall(probeRoute,route,raw)end
   if not ok or not match then valid=false;break end
  end
  if valid then return discovery.ports end
  discovery.ports=nil;discovery.rawNames={}
 end
 local allowed,ports={},{}''')
  text=swap(text,'return ports end local function verifyBulk(route,raw)','if discovery then discovery.ports=ports end\nreturn ports end local function verifyBulk(route,raw)')
  text=swap(text,'local function prepareStreaming(target) local ports=bulkPorts()','local function prepareStreaming(target) local ports=bulkPorts(target)')
  text=swap(text,'local totals,count={},0 local selectedBackground','local totals,count={},0 local selectedBackground\nif discovery and discovery.catalogue then\n for name,n in pairs(discovery.catalogue.totals)do assert(mapping[name],"未登记原液映射: "..name);totals[name]=n*copies;assert(totals[name]<=2147483647,"缓存目标过大")end\n count=discovery.catalogue.count;productionOutputs=discovery.catalogue.outputs\nelse')
  text=swap(text,'count=count+1 print("配方 "..count.."："..filename) end end\nassert(count>0,','count=count+1 print("配方 "..count.."："..filename) end end\nend\nassert(count>0,')
  text=swap(text,'local live,stock=network(MAIN),field();for raw,n in pairs(network(SUB)) do live[raw]=math.max(live[raw] or 0,n) end local visibleRoutes=bulkPorts();local waiting for kind in pairs(totals) do local raw=mapping[kind]', '''local live,stock={},field();local visibleRoutes=bulkPorts();local waiting
local unknown=false;for kind in pairs(totals)do if not(discovery and discovery.rawNames[kind])then unknown=true end end
if unknown then live=network(MAIN);for raw,n in pairs(network(SUB))do live[raw]=math.max(live[raw]or 0,n)end end
for kind in pairs(totals) do local raw=mapping[kind]
if discovery and discovery.rawNames[kind]then mapping[kind]=discovery.rawNames[kind]else''')
  text=swap(text,'if n==1 then mapping[kind]=name end end','if n==1 then mapping[kind]=name;if discovery then discovery.rawNames[kind]=name end end\nend end')
  text=swap(text,'local routes=bulkPorts();local stored=field()','local routes=bulkPorts(totals);local stored=field()')
  text=swap(text,'end local function verifyBulk(route,raw)','end local function verifyBulk(route,raw,allowEmpty)')
  text=swap(text,'then f=f[1] end assert(type(f)=="table" and f.name==raw\nand call(route.address','then f=f[1] end assert(type(f)=="table" and (f.name==raw or allowEmpty and not f.name and integer(f.amount or 0)==0)\nand call(route.address')
  text=swap(text,'assert(route,"高速供液口不可用："..raw);verifyBulk(route,raw)','assert(route,"高速供液口不可用："..raw);verifyBulk(route,raw,true)')
  text=swap(text,'if discovery then discovery.ports=ports end','if discovery then discovery.ports=ports;if BEC_V3_CACHE_SAVE_DISCOVERY then BEC_V3_CACHE_SAVE_DISCOVERY()end end')
  text=swap(text,'if discovery then discovery.rawNames[kind]=name end','if discovery then discovery.rawNames[kind]=name;if BEC_V3_CACHE_SAVE_DISCOVERY then BEC_V3_CACHE_SAVE_DISCOVERY()end end')
 return text
if __name__=='__main__':
 out=ROOT/'outputs/oc-cache-discovery/patched'
 prepared=[]
 for name in ['lib/cache.lua','runtime/cache.lua']:
  p=ROOT/'reinstall_v2/files'/name;prepared.append((p,patch(name,p.read_text(encoding='utf-8'))))
  p=ROOT/'outputs/oc-cache-discovery/original'/name;q=out/name;q.parent.mkdir(parents=True,exist_ok=True);q.write_text(patch(name,p.read_text(encoding='utf-8')),encoding='utf-8')
 for p,t in prepared:p.write_text(t,encoding='utf-8')
