local c=require('component');local event=require('event');local clock=require('computer')
local ROOT='/home/bec_v2'
local function module(n)return assert(loadfile(ROOT..'/lib/'..n..'.lua'))()end
local C,B,W=module('config'),module('ochd_bindings'),module('web_json')
local address,count=nil,0;for a in c.list('hd_panel',true)do address=a;count=count+1 end
assert(count==1,'请只连接一面 OCHD 屏幕墙的主组件')
local methods=c.methods(address)
assert(methods.setWebApp~=nil and methods.publish~=nil,'需要支持 HTML 页面的 OCHD alpha7 或兼容版 JAR')
local f=assert(io.open(C.path('lib/web_page.html'),'r'));local page=f:read('*a');f:close()
local package={id='bec-v2-studio',title='BEC V2 结构绑定与运行',entry='index.html',files={['index.html']=page},
 events={'save_field','apply_bindings','start','pause','select_group','refresh','scan_components','patterns','cache'}}
local panel=c.proxy(address)
-- BEC_V3_WEB_SINGLE_INSTANCE_1: cached component proxies are shared by OpenOS
-- processes. Acquire before constructing a session or changing the panel.
local previous=rawget(panel,'_becWebOwner')
assert(not previous or previous.closed or coroutine.status(previous.root)=='dead',
 'BEC 网页程序已经运行，请使用现有页面；先在 OC 按 Q 正常退出后才能重开')
local owner={root=coroutine.running(),startedAt=clock.uptime(),closed=false}
rawset(panel,'_becWebOwner',owner)
local function session()
local H=module('web_session')(C,B,W)
local snapshot=H.snapshot
H.snapshot=function(...)
 local data=snapshot(...);owner.state=data;owner.updatedAt=clock.uptime()
 local engine=H.engine();owner.logs=engine and engine.logs
 return data
end
local T=module('web_transport')(panel,event,W,address);C.pulse=T.pulse
T.snapshot=function()return H.snapshot(true)end
T.observe=H.observe
T.canServe=H.canServeFast
local function handle(request)
 local success,message=pcall(function()return H.handle(request.name,request.args,request.request)end)
 if not success then H.notice=tostring(message)end
 T.publish(H.snapshot(true),{token=request.token,name=request.name,ok=success,message=tostring(message):sub(1,400)})
end
T.serve=handle
local ok,err=xpcall(function()
 while true do local accepted,reason=panel.setWebApp(package);assert(accepted~=nil,reason);if accepted then break end;event.pull(.6)end
 print('OCHD 已显示结构绑定与流程图。右键屏幕操作；OC 按 Q 退出并暂停。')
 local nextPush=0
 T.pulse(true)
 while not T.stopping do
  T.poll(.05)
  local request=T.take()
  if request then
   T.handling=true;handle(request);T.handling=false
   nextPush=clock.uptime()+.6
  end
  if T.stopping then break end
  H.step();T.pulse()
  if clock.uptime()>=nextPush then
   T.publish(H.snapshot(true));nextPush=clock.uptime()+.6
  end
 end
end,debug.traceback)
local errors=H.close();for _,reason in ipairs(errors)do print('需人工检查：'..reason)end
pcall(function()panel.release()end)
assert(ok,err);assert(#errors==0,'暂停存在回读失败，请核对机器')
end
local success,reason=xpcall(session,debug.traceback)
owner.closed=true
if rawget(panel,'_becWebOwner')==owner then rawset(panel,'_becWebOwner',nil)end
assert(success,reason)
