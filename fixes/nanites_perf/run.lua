-- Temporary in-memory profiler. Does not replace installed Lua files.
local clock=require('computer')
local originalLoadfile=loadfile
local unpack=table.unpack or unpack
local reportPath='/home/bec_nanites_perf.txt'
local sourcePath='/home/bec_nanites.lua'
local mode=(...) or 'resume'
assert(mode=='resume','用法：lua /home/bec_nanites_perf.lua resume')
local function read(path)
 local f=assert(io.open(path,'r'), '缺少 '..path)
 local text=f:read('*a');f:close();return text
end
local source=read(sourcePath)
assert(source:find('M.fastStages=true',1,true),'此测试需要当前快速换蜂模块；未启动程序')
local phases={
 {'discover','组件和端口检查'}, {'oldRecord','读取旧记录'},
 {'emptyPorts','端口空闲检查'}, {'bank','扫描硬盘盒'},
 {'archive','归档旧日志'}, {'save','保存换蜂日志'},
 {'move','搬盘及前后核对'}, {'runPort','ME IO处理和确认'},
 {'recover','回收旧蜂群'}, {'loadCell','装入新蜂群'},
 {'guard','节点与控制器检查'}, {'tick','轮询等待及界面回调'}
}
local bindings={}
for _,p in ipairs(phases) do
 assert(source:find('local function '..p[1]..'(',1,true),'模块结构不匹配：'..p[1]..'；未启动程序')
 bindings[#bindings+1]=p[1]..'=__perf.phase('..string.format('%q',p[2])..','..p[1]..')'
end
bindings[#bindings+1]='call=__perf.call(call)'
bindings[#bindings+1]='read=__perf.metric("日志读取",read)'
bindings[#bindings+1]='write=__perf.metric("日志写入含回读",write)'
local function insertOnce(text,needle,replacement)
 local a,b=text:find(needle,1,true);assert(a and not text:find(needle,b+1,true),'模块结构不匹配；未启动程序')
 return text:sub(1,a-1)..replacement..text:sub(b+1)
end
source=insertOnce(source,'local M={}',table.concat(bindings,'\n')..'\nlocal M={}')
source=insertOnce(source,'local mode=(...)','M.ensure=__perf.ensure(M.ensure)\nlocal mode=(...)')
assert(load('return function(__perf) return function(...)\n'..source..'\nend end', '@'..sourcePath,'t',_ENV))
local active,sequence,history=nil,0,{}
local function packed(...) return {n=select('#',...),...} end
local function timed(fn,args)
 return packed(xpcall(function()return fn(unpack(args,1,args.n))end,debug.traceback))
end
local function record(rows,key,seconds)
 local r=rows[key] or {count=0,total=0};rows[key]=r
 r.count=r.count+1;r.total=r.total+seconds;return r
end
local perf={}
function perf.phase(label,fn)
 return function(...)
  if not active then return fn(...) end
  local run=active;local frame={started=clock.uptime(),children=0}
  local parent=run.stack[#run.stack];run.stack[#run.stack+1]=frame
  local values=timed(fn,packed(...));local elapsed=clock.uptime()-frame.started
  run.stack[#run.stack]=nil
  if parent then parent.children=parent.children+elapsed end
  local r=record(run.phases,label,elapsed)
  r.own=(r.own or 0)+math.max(0,elapsed-frame.children)
  if not values[1] then error(values[2],0) end
  return unpack(values,2,values.n)
 end
end
function perf.metric(label,fn)
 return function(...)
  if not active then return fn(...) end
  local run=active;local start=clock.uptime();local values=timed(fn,packed(...))
  record(run.metrics,label,clock.uptime()-start)
  if not values[1] then error(values[2],0) end
  return unpack(values,2,values.n)
 end
end
function perf.call(fn)
 return function(address,method,...)
  if not active then return fn(address,method,...) end
  local run=active;local start=clock.uptime();local values=timed(fn,packed(address,method,...))
  record(run.calls,method,clock.uptime()-start)
  if not values[1] then error(values[2],0) end
  return unpack(values,2,values.n)
 end
end
local function sorted(rows)
 local keys={};for key in pairs(rows)do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return rows[a].total>rows[b].total end);return keys
end
local function report(run,values)
 sequence=sequence+1
 local lines={'BEC NANITES TIMING / 换蜂计时 #'..sequence,
  string.format('总耗时 %.3f 秒；结果 %s',run.elapsed,values[1] and tostring(values[2]) or '失败'),
  '阶段：次数 / 含子步骤秒 / 自身秒（自身可相加，含子步骤不可相加）'}
 local accounted=0
 for _,key in ipairs(sorted(run.phases))do local r=run.phases[key]
  accounted=accounted+r.own
  lines[#lines+1]=string.format('%s: %d / %.3f / %.3f',key,r.count,r.total,r.own)
 end
 lines[#lines+1]=string.format('决策及其他: %.3f 秒',math.max(0,run.elapsed-accounted))
 lines[#lines+1]='日志读写子项（已包含在上面，不重复相加；写入包含回读）'
 for _,key in ipairs(sorted(run.metrics))do local r=run.metrics[key]
  lines[#lines+1]=string.format('%s: %d 次 / %.3f 秒',key,r.count,r.total)
 end
 lines[#lines+1]='组件调用子项（已包含在上面，不重复相加）'
 for _,key in ipairs(sorted(run.calls))do local r=run.calls[key]
  lines[#lines+1]=string.format('%s: %d 次 / %.3f 秒',key,r.count,r.total)
 end
 if not values[1]then lines[#lines+1]='原始错误：'..tostring(values[2])end
 history[#history+1]=table.concat(lines,'\n')
 if #history>10 then table.remove(history,1)end
 local text=table.concat(history,'\n\n')..'\n'
 local f=assert(io.open(reportPath,'w'));assert(f:write(text));assert(f:flush());f:close()
 assert(read(reportPath)==text,'计时报告回读失败')
 print(string.format('换蜂计时 #%d：%.2f 秒；报告 %s',sequence,run.elapsed,reportPath))
end
function perf.ensure(fn)
 return function(...)
  assert(not active,'计时器不支持重入')
  local run={phases={},metrics={},calls={},stack={}};active=run
  local start=clock.uptime();local values=timed(fn,packed(...))
  run.elapsed=clock.uptime()-start;active=nil
  -- No-switch inventory checks must not flood the UI or write on every poll.
  if not values[1] or values[2] then
   local ok,err=pcall(report,run,values)
   if not ok then print('计时报告保存失败：'..tostring(err))end
  end
  if not values[1]then error(values[2],0)end
  return unpack(values,2,values.n)
 end
end
loadfile=function(path,loadMode,env)
 if path==sourcePath then
  -- Preserve the caller's environment, including the UI's captured print.
  local adapted=assert(load('return function(__perf) return function(...)\n'..source..'\nend end','@'..sourcePath,loadMode or 't',env or _ENV))()
  return adapted(perf)
 end
 return originalLoadfile(path,loadMode,env)
end
print('临时换蜂计时已启用：正常运行，至少等一次换蜂完成后按 Q 退出。')
local values=timed(function()
 return assert(originalLoadfile('/home/bec_ui.lua','t',_ENV))(mode)
end,packed())
loadfile=originalLoadfile
if not values[1] then error(values[2],0)end
print(sequence>0 and '报告已保存：'..reportPath or '本次没有发生换蜂，没有生成新报告。')
return unpack(values,2,values.n)
