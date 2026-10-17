-- Heartbeats while large OC reads run. Receipt is not operation completion.
local clock=require('computer')
return function(panel,event,W,address)
 local T={queue={},next=0,last={mode='binding',values={},group=1,groupCount=1,configured=false,notice='正在读取 OC 配置和设备状态'},stopping=false}
 local polling=false
 local function receive(e)
  if e[1]=='key_down'and(e[3]==113 or e[3]==81)then T.stopping=true;return end
  if e[1]~='hd_panel_web'or e[2]~=address then return end
  local ok,args=pcall(W.decode,e[6])
  if not ok or type(args)~='table'then panel.ack(e[5],false,'页面参数无效');return end
  if #T.queue>=16 then panel.ack(e[5],false,'OC 请求队列已满，请等待当前操作完成');return end
  local token=args._token
  if type(token)~='string'or #token>64 then panel.ack(e[5],false,'网页版本不匹配，请重新打开页面');return end
  T.queue[#T.queue+1]={name=e[3],args=args,request=e[5],token=token}
  panel.ack(e[5],true,'BEC_REQUEST_ACCEPTED')
 end
 function T.pulse(force)
  if polling then return end;polling=true
  for i=1,8 do local e={event.pull(0)};if not e[1]then break end;receive(e)end
  local now=clock.uptime()
  if force or now>=T.next then
   local data=T.pending or T.last
   data.transportProtocol=1;data.transportBusy=T.pending==nil;data.transportAt=now
   local accepted,reason=panel.publish(data)
   assert(accepted~=nil,reason)
   if accepted then T.last=data;T.pending=nil;T.next=clock.uptime()+.6 else T.next=clock.uptime()+.1 end
  end
  polling=false
 end
 function T.publish(data,reply)
  if reply then T.reply=reply end
  data.reply=T.reply;T.pending=data;T.pulse()
 end
 function T.poll(seconds)receive({event.pull(seconds or .05)});T.pulse()end
 function T.take()if not T.pending then return table.remove(T.queue,1)end end
 return T
end
