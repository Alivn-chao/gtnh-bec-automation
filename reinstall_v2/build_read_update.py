"""Build an offline, exact-baseline V2 read-optimization updater."""
from pathlib import Path
import subprocess
from build import literal
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
BASE='549df6e'
NAMES=['lib/bridge.lua','runtime/controller.lua','lib/engine.lua','runtime/nanites_cell.lua','lib/config.lua','lib/storage.lua','main.lua','web.lua','lib/web_session.lua','lib/web_json.lua','lib/web_page.html']
PREVIEW3={'lib/bridge.lua': '14885:2931246636', 'lib/engine.lua': '9855:1405689683', 'lib/config.lua': '7134:2524978389', 'runtime/controller.lua': '36893:1553718572'}
PREVIEW21={'lib/bridge.lua': '14572:3934966185', 'lib/engine.lua': '8215:3066878477'}
PREVIEW2={'lib/bridge.lua':'14483:790541300'}
PREVIEW1={'lib/bridge.lua': '13410:2517241504', 'runtime/controller.lua': '36384:3281062855'}
rows=[]
for name in NAMES:
 result=subprocess.run(['git','show',BASE+':reinstall_v2/files/'+name],cwd=ROOT,capture_output=True)
 before=result.stdout.decode('utf-8')if result.returncode==0 else None
 source=(HERE/'files'/name).read_text(encoding='utf-8')
 rows.append('{path="/home/bec_v2/'+name+'",preview1="'+PREVIEW1.get(name,'')+'",preview2="'+PREVIEW2.get(name,'')+'",preview21="'+PREVIEW21.get(name,'')+'",preview3="'+PREVIEW3.get(name,'')+'",added='+('true'if before is None else 'false')+',before='+(literal(before)if before is not None else 'nil')+',source='+literal(source)+'}')
BODY=r'''
print('BEC V2 OCHD integrated studio preview 4; stop the running UI with Q first.')
local fs=require('filesystem')
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read('*a');f:close();return s end
local function normal(s)return s and s:gsub('\r\n','\n')end
local function signature(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
assert(fs.exists('/home/bec_v2/main.lua'),'仅支持已安装的V2')
local originals,identical={},true
for i,row in ipairs(files)do
 if row.path:sub(-4)=='.lua'then assert(load(row.source,'@'..row.path,'t',_ENV),'更新文件语法错误')end
 originals[i]=read(row.path)
 assert(originals[i]or row.added,'缺少V2程序: '..row.path)
 local current=normal(originals[i])
 assert(row.added and current==nil or current==normal(row.before)or current==normal(row.source)or row.preview1~=''and signature(current)==row.preview1 or row.preview2~=''and signature(current)==row.preview2 or row.preview21~=''and signature(current)==row.preview21 or row.preview3~=''and signature(current)==row.preview3,'程序与支持版本不符，保留本地修改: '..row.path)
 if current~=normal(row.source)then identical=false end
end
if identical then print('读取优化已安装，无需更新。');return end
local C=assert(loadfile('/home/bec_v2/lib/config.lua'))()
local cfg=C.load();C.validate(cfg,false)
local c=require('component')
local function stopped()
 for _,n in ipairs(cfg.nodes)do
  assert(c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'先Q退出并暂停全部节点')
  local state=c.invoke(n.address,'getState')
  assert(state=='idle'or state=='paused-immediate'or state=='nanite-tier-too-low','节点仍在运行')
 end
 for group,g in ipairs(cfg.groups)do
  for _,a in ipairs(g.generators)do
   assert(c.invoke(a,'isWorkAllowed')==false and c.invoke(a,'isMachineActive')==false,'先Q退出，等待全部纠缠器停止活动')
  end
  if g.nanites and g.nanites.enabled and g.nanites.mode=='cell-io'then
   local old=C.read(C.path('state/group-'..group..'/nanites-cell.journal'))
   assert(not old or old.stage=='done','存在未完成蜂群IO，保留盘和日志，不更新运行模块')
   for _,side in ipairs({g.nanites.loadSide,g.nanites.returnSide})do
    assert(c.invoke(g.nanites.transposer,'getInventorySize',side)==12,'蜂群端口必须为12槽ME IO')
    for slot=1,12 do assert(c.invoke(g.nanites.transposer,'getStackInSlot',side,slot)==nil,'先核对并清空两端ME IO，保留未完成操作')end
   end
   for _,pair in ipairs({{g.nanites.loadRedstone,g.nanites.loadOutputSide},{g.nanites.returnRedstone,g.nanites.returnOutputSide}})do
    assert(c.invoke(pair[1],'getOutput',pair[2])==0,'蜂群IO仍在工作，保持现场')
   end
  end
 end
end
stopped()
local n=1
while true do
 local conflict=false
 for _,row in ipairs(files)do for _,suffix in ipairs({'.before-read-opt-','.read-opt-new-','.read-opt-failed-'})do
  if fs.exists(row.path..suffix..n)then conflict=true end
 end end
 if not conflict then break end;n=n+1
end
for _,row in ipairs(files)do
 local p=row.path..'.read-opt-new-'..n;local f=assert(io.open(p,'w'))
 assert(f:write(row.source));assert(f:flush());f:close();assert(read(p)==row.source,'临时程序回读失败')
end
stopped()
for i,row in ipairs(files)do assert(read(row.path)==originals[i],'更新期间程序变化，未替换原文件')end
local retired,installed={},{}
local ok,err=pcall(function()
 for i,row in ipairs(files)do
  if originals[i]then assert(fs.rename(row.path,row.path..'.before-read-opt-'..n),'备份失败');retired[i]=true end
  assert(fs.rename(row.path..'.read-opt-new-'..n,row.path),'安装失败');installed[i]=true
  assert(read(row.path)==row.source,'安装回读失败')
 end
end)
if not ok then
 for i=#files,1,-1 do local row=files[i]
  if installed[i]then assert(fs.rename(row.path,row.path..'.read-opt-failed-'..n),'移出失败程序失败，保留所有备份')end
  if retired[i]then assert(fs.rename(row.path..'.before-read-opt-'..n,row.path),'恢复失败，保留所有备份')end
 end
 error('更新失败，旧程序已恢复: '..tostring(err))
end
print('V2批次接单控制已同步。原程序备份后缀: .before-read-opt-'..n)
print('配置、配方、当前/历史日志未修改；未启动或控制机器。')
print('蜂群硬盘仅管理箱子前10格；两端ME IO按输入1/输出7搬运。')
print('这是模拟验证的预览版，需在游戏中比较实际耗时。')
'''
(HERE/'update_reads.lua').write_text('local files={'+','.join(rows)+'}\n'+BODY,encoding='utf-8',newline='\n')
print('Built update_reads.lua for',len(rows),'programs, baseline',BASE)
