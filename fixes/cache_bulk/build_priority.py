"""Generate a locating installer, preserving the installed cache worker."""
from pathlib import Path
folder=Path(__file__).parent
original=(folder/'bec_cache.lua').read_text(encoding='utf-8')
helper=(folder/'priority.lua.inc').read_text(encoding='utf-8')
handoff='''
local priority=false
local function handoff()
 for _,job in ipairs(record.requests) do assert(job.state=="done","缓存申请尚未完成，不能交回生产") end
 for raw,n in pairs(previous) do
  local known=false;for name in pairs(target) do if mapping[name]==raw then known=true;assert(integer(n)%(units[name] or 144)==0,"已搬缓存不是整批") end end
  assert(known,"交回生产前子网有无关原液")
 end
 for name in pairs(target) do target[name]=(stock[name] or 0)+(previous[mapping[name]] or 0) end
 expected=previous;record.target=target;record.expected=previous;record.secured=previous;record.plan=nil
 record.yieldedToRecipe=true;save("stream-prepared")
 print("已有配方，停止补缓存；仅转换已搬入原液后交回生产。")
 return previous
end
if productionWaiting() then return handoff() end
'''
changes=[
 ('local function prepareStreaming(target)',helper+'\nlocal function prepareStreaming(target)'),
 ('local expected,raws={},{} for name,need in pairs(target)', 'local expected,raws={},{}\n'+handoff+'\nfor name,need in pairs(target)'),
 ('for _,item in ipairs(raws) do local raw,need,batch=item.raw,item.amount,item.batch local route=ports[raw]',
  'for _,item in ipairs(raws) do if productionWaiting() then return handoff() end local raw,need,batch=item.raw,item.amount,item.batch local route=ports[raw]'),
 ('local remaining=need-(previous[raw] or 0) local buffered=network(MAIN)[raw] or 0 local amount=math.floor(math.min(remaining,buffered,chunk)/batch)*batch',
  'priority=priority or productionWaiting()\nlocal remaining=need-(previous[raw] or 0) local buffered=network(MAIN)[raw] or 0 local amount=priority and 0 or math.floor(math.min(remaining,buffered,chunk)/batch)*batch'),
 ('end end if remaining==0 and (not job or job.state=="done") then break end',
  'end end if priority and (not job or job.state=="done") then return handoff() end if remaining==0 and (not job or job.state=="done") then break end'),
 ('if remaining>0 and (not job or job.state=="done") then',
  'if not priority and remaining>0 and (not job or job.state=="done") then'),
 ('if missing>0 then job={raw=raw,amount=missing,unit="mB",state="pending",securedBefore=previous[raw] or 0}',
  'if missing>0 then if productionWaiting() then return handoff() end job={raw=raw,amount=missing,unit="mB",state="pending",securedBefore=previous[raw] or 0}'),
 ('local demand={}\nfor _,fluid in ipairs(recipe.condensates)',
  'local demand={}\nfor _,out in ipairs(recipe.outputs or {}) do productionOutputs[tostring(out.name)..":"..tostring(tonumber(out.damage or 0))]=true end\nfor _,fluid in ipairs(recipe.condensates)'),
 ('if call(NODE,"getState")~="idle" then return {} end local stock=field();',
  'if productionWaiting() then return {} end local stock=field();'),
 ('local live,stock=network(MAIN),field();local visibleRoutes=bulkPorts();local waiting',
  'local live,stock=network(MAIN),field();for raw,n in pairs(network(SUB)) do live[raw]=math.max(live[raw] or 0,n) end local visibleRoutes=bulkPorts();local waiting'),
 ('local routes=bulkPorts();local stored=field()',
  'if productionWaiting() then return totals end local routes=bulkPorts();local stored=field()'),
 ('selectedBackground=selected;totals={[selected]=fixedStock}',
  'selectedBackground=selected;totals={[selected]=math.min(fixedStock,(stock[selected] or 0)+math.floor(16000/(units[selected] or 144))*(units[selected] or 144))}'),
 ('print("高速后台缓存：本种按剩余缺口补到 "..fixedStock.." mB，不受16桶轮次限制。")',
  'print("后台补缓存按最多16桶分段；有配方优先交回生产，本段目标 "..totals[selectedBackground].." mB。")'),
]
patched=original
for old,new in changes:
 assert patched.count(old)==1,old
 patched=patched.replace(old,new,1)
(folder/'bec_cache_priority.lua').write_text(patched,encoding='utf-8')
installer='''local fs=require('filesystem')
local path='/home/bec_cache.lua'
local function read(p)local f=assert(io.open(p,'r'));local text=f:read('*a');f:close();return assert(text)end
local function replace(text,from,to)
 local a,b=text:find(from,1,true);assert(a and not text:find(from,b+1,true),'缓存优先级补丁入口缺失或不唯一，原文件未改')
 return text:sub(1,a-1)..to..text:sub(b+1)
end
local original=read(path)
if original:find('BEC_V1_CACHE_PRIORITY_V1',1,true)then print('配方优先补丁已安装');return end
local modified=original:gsub('\\r\\n','\\n')
'''
for old,new in changes:installer+='modified=replace(modified,[=['+old+']=],[=['+new+']=])\n'
installer+='''assert(load(modified,'@'..path,'t',_ENV),'缓存优先级语法检查失败')
local n=1;while fs.exists(path..'.before-priority-'..n) or fs.exists(path..'.priority-new-'..n)do n=n+1 end
local backup,temp=path..'.before-priority-'..n,path..'.priority-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close();assert(read(temp)==modified,'临时文件回读失败')
assert(fs.rename(path,backup),'备份失败，原文件保留')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'还原失败，原文件在 '..backup);error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'替换/备份回读不符')
print('配方优先补丁已安装；备份: '..backup)
print('未启停机器或修改日志。正常Q退出后: lua /home/bec_ui.lua run')
'''
(folder/'patch_priority.lua').write_text(installer,encoding='utf-8')
