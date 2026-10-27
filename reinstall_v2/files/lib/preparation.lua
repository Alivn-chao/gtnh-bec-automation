-- One worker owns preparation; child jobs share waits, never physical orders.
local M={}
function M.run(jobs,ctx)
 local start=ctx.now();local live={};local times={};local failure
 for i,j in ipairs(jobs)do live[i]={name=j.name,co=coroutine.create(j.run),at=start,due=start}end
 while true do
  local active=false;local nextWake
  for _,j in ipairs(live)do if coroutine.status(j.co)~='dead'and not j.skipped then
   if failure and not j.started then j.skipped=true
   elseif ctx.now()>=j.due then
    j.started=true
    local ok,kind,deadline=coroutine.resume(j.co)
    if not ok then
     if not failure then failure=tostring(kind);ctx.abort()end
     j.skipped=true
    elseif coroutine.status(j.co)=='dead'then times[j.name]=ctx.now()-j.at
    else
     if kind~='wait'then
      if not failure then failure='准备子任务不能申请另一个资源锁';ctx.abort()end
      j.skipped=true
     else j.due=deadline or ctx.now()end
    end
   end
   if not j.skipped and coroutine.status(j.co)~='dead'then active=true;nextWake=math.min(nextWake or j.due,j.due)end
  end end
  if not active then break end
  -- Preserve the engine's wait protocol, including cancellation. Resuming the
  -- children unwinds the hive module's own IO-off cleanup before failing.
  coroutine.yield('wait',nextWake or ctx.now())
  if ctx.stopping()and not failure then failure='用户暂停并行准备，保留已确认操作';ctx.abort()end
 end
 if failure then ctx.cleanup();error(failure,0)end
 return{version=1,started=start,elapsed=ctx.now()-start,durations=times}
end
local function whole(n)return type(n)=='number'and n>=0 and n%1==0 and n<=9007199254740991 end
-- Conversion can occur between getters. The subnet snapshot must lie between
-- two field snapshots; never count both a consumed raw and its product twice.
function M.balance(base,secured,mapping,before,sub,after)
 local allowed={}
 for _,raw in pairs(mapping)do assert(not allowed[raw],'供液原液映射重复');allowed[raw]=true end
 for raw,n in pairs(sub)do assert(n==0 or allowed[raw],'子网有无关原液: '..raw)end
 for kind,n in pairs(after)do assert(n==0 or mapping[kind],'约束场有未知凝聚物: '..kind)end
 for kind,raw in pairs(mapping)do
  local a,b,n=before[kind]or 0,after[kind]or 0,sub[raw]or 0
  local initial,added=base[kind]or 0,secured[raw]or 0
  assert(whole(a)and whole(b)and whole(n)and whole(initial)and whole(added),'转换账本数量无效')
  assert(initial<=9007199254740991-added,'转换账本总量溢出')
  local total=initial+added
  if a<initial or b<a or a>total or b>total or n>added then return false end
  if a+n>total or b+n<total then return false end
 end
 return true
end
return M
