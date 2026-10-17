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
 events={'save_field','apply_bindings','start','pause','select_group','refresh','scan_components','patterns'}}
local panel=c.proxy(address);local H=module('web_session')(C,B,W)
local ok,err=xpcall(function()
 while true do local accepted,reason=panel.setWebApp(package);assert(accepted~=nil,reason);if accepted then break end;event.pull(.6)end
 print('OCHD 已显示结构绑定与流程图。右键屏幕操作；OC 按 Q 退出并暂停。')
 local running,nextPush=true,0
 while running do
  H.step()
  if clock.uptime()>=nextPush then
   local accepted,reason=panel.publish(H.snapshot());assert(accepted~=nil,reason)
   nextPush=clock.uptime()+(accepted and 2 or .6)
  end
  local e={event.pull(.05)}
  if e[1]=='key_down'and(e[3]==113 or e[3]==81)then running=false end
  if e[1]=='hd_panel_web'and e[2]==address then
   local success,message=pcall(function()return H.handle(e[3],W.decode(e[6]),e[5])end)
   if not success then H.notice=tostring(message)end
   panel.ack(e[5],success,tostring(message));nextPush=clock.uptime()+.6
  end
 end
end,debug.traceback)
local errors=H.close();for _,reason in ipairs(errors)do print('需人工检查：'..reason)end
pcall(function()panel.release()end)
assert(ok,err);assert(#errors==0,'暂停存在回读失败，请核对机器')
