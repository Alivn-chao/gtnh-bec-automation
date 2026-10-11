from pathlib import Path
import runpy
folder=Path(__file__).parent
fast=runpy.run_path(str(folder/'build_maintenance.py'))
workerChanges=[
 ('local fixedStock','local fixedStock -- BEC_V1_CACHE_CUSTOM_V1\nlocal overrides={}'),
 ('assert(count>0,"没有可缓存的已登记配方") if fixedStock then for name in pairs(totals) do totals[name]=fixedStock end',
  '''assert(count>0,"没有可缓存的已登记配方") if fixedStock then
local input=io.open("/home/bec_cache.config","r")
if input then local cfg=ser.unserialize(input:read("*a"));input:close()
 assert(type(cfg)=="table" and cfg.version==1 and (cfg.overrides==nil or type(cfg.overrides)=="table"),"单项缓存配置无效")
 overrides=cfg.overrides or {};for name,n in pairs(overrides) do assert(type(name)=="string" and type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n),"单项缓存目标无效") end
end
for name in pairs(totals) do totals[name]=overrides[name]~=nil and overrides[name] or fixedStock end'''),
 ('selectedBackground=selected;totals={[selected]=fixedStock}', 'selectedBackground=selected;totals={[selected]=totals[selected]}'),
 ('"..fixedStock.." mB；有配方优先让位。"', '"..totals[selectedBackground].." mB；有配方优先让位。"'),
 ('每种凝聚物统一目标 "..fixedStock.." mB，只补差额。', '默认目标 "..fixedStock.." mB，单项设置优先，0停补；只补差额。'),
]
saveBefore='''local n=tonumber(buffer);assert(valid(n),"请输入有效正整数mB")'''
saveAfter='''local n=tonumber(buffer)
assert(valid(n) or (selectedName~=nil and n==0),"默认目标需正整数；单项允许0停补")
local nextOverrides={};for name,value in pairs(overrides) do nextOverrides[name]=value end
local nextTarget=target
if selectedName then if restoreDefault then nextOverrides[selectedName]=nil else nextOverrides[selectedName]=n end else nextTarget=n end'''
rowHandler='''if e[4]>=9 and e[4]<=16 then
 local row=names[(page-1)*8+e[4]-8]
 if row then selectedName=row[2];restoreDefault=false;editing=true;buffer="";status="设置 "..row[1].."；输入新目标，0停止自动补这一种"
  if e[5]==1 then e={"key_down","ui",100} else e={} end
 end
elseif editing and e[4]==7 then
 e={"key_down","ui",e[3]<16 and 13 or e[3]<32 and 0 or 100,e[3]>=16 and e[3]<32 and 1 or 0}
elseif e[4]==6 then'''
uiChanges=[
 ('if e[1]=="touch" and e[5]==0 then','if e[1]=="touch" and (e[5]==0 or e[5]==1) then'),
 ('local target=144000','local target=144000 -- BEC_V1_CACHE_CUSTOM_UI_V1\nlocal overrides,selectedName,restoreDefault={},nil,false'),
 ('target=value.target','''target=value.target
assert(value.overrides==nil or type(value.overrides)=="table","单项缓存配置损坏")
overrides=value.overrides or {};for name,n in pairs(overrides) do assert(type(name)=="string" and type(n)=="number" and n>=0 and n<=2147483647 and n==math.floor(n),"单项缓存目标无效") end'''),
 ('"每种凝聚物目标："..(editing and buffer.."_" or tostring(target))','(selectedName and ((labels[selectedName] or selectedName).." 单项目标：") or "默认缓存目标：")..(editing and buffer.."_" or tostring(target))'),
 ('editing and "输入数字；Enter 保存，Esc 取消，Backspace 删除" or "[ E 修改目标 ]   [ B 补缓存 ]   [ P 预览 ]"',
  'editing and "[ 保存 ]       [ 取消 ]       [ 恢复统一 ]  输入数字，0停补" or "[ E 默认目标 ]   [ B 补缓存 ]   [ P 预览 ]  点击流体设置；右键恢复默认"'),
 ('if (stock[row[2]] or 0)<target then', 'if (stock[row[2]] or 0)<(overrides[row[2]]~=nil and overrides[row[2]] or target) then'),
 ('local value=row and stock and (stock[row[2]] or 0) or nil', 'local desired=row and (overrides[row[2]]~=nil and overrides[row[2]] or target) or target\nlocal value=row and stock and (stock[row[2]] or 0) or nil'),
 ('(value or 0)/target','(value or 0)/math.max(1,desired)'),
 ('value>=target','value>=desired'),
 ('tostring(value or "?").." / "..target','tostring(value or "?").." / "..(desired==0 and "停补" or desired)'),
 (saveBefore,saveAfter),
 ('out:flush();out:close()', 'assert(out:flush());out:close()'),
 ('write(CONFIG,ser.serialize({version=1,target=n},false))\ntarget=n;editing=false;status="配置已保存，下次启动仍使用此目标"',
  'write(CONFIG,ser.serialize({version=1,target=nextTarget,overrides=nextOverrides},false))\ntarget=nextTarget;overrides=nextOverrides;editing=false;selectedName=nil;restoreDefault=false;status="缓存设置已保存，下次补库按单项目标执行"'),
 ('editing=false;buffer=tostring(target);return "back"','editing=false;selectedName=nil;restoreDefault=false;buffer=tostring(target);return "back"'),
 ('if e[4]==6 then',rowHandler),
 ('if editing then if code==1 then editing=false','''if editing then if code==1 then editing=false;selectedName=nil;restoreDefault=false
elseif ch==100 and selectedName then restoreDefault=true;buffer=tostring(target);local ok,err=pcall(save);if not ok then status=tostring(err) end'''),
 ('elseif ch==101 or ch==69 then editing=true;buffer="";status="修改统一库存目标"',
  'elseif ch==101 or ch==69 then selectedName=nil;restoreDefault=false;editing=true;buffer="";status="修改默认目标，已设单项目标保持"'),
 ('if embedded then buffer=tostring(target);local ok,err=pcall(save);',
  'if embedded then selectedName=nil;restoreDefault=false;buffer=tostring(target);local ok,err=pcall(save);'),
]
worker=(folder/'bec_cache_fast.lua').read_text(encoding='utf-8')
for before,after in workerChanges:
 assert worker.count(before)==1,before
 worker=worker.replace(before,after,1)
(folder/'bec_cache_custom.lua').write_text(worker,encoding='utf-8')
engine=(folder/'patch_fast.lua').read_text(encoding='utf-8')
prefix=engine.split("plan('/home/bec_cache.lua'",1)[0].replace('cache-fast','cache-custom')
suffix=engine[engine.index("for _,p in ipairs(plans)do local f=assert"):].replace('快速补库升级完成：取消16桶限制；只为已确认配方让位；修正完成状态。','单项缓存设置已安装：鼠标点击流体，0停补，右键恢复默认。')
installer=prefix+"plan('/home/bec_cache.lua','BEC_V1_CACHE_CUSTOM_V1',function(t)\nif not t:find('BEC_V1_CACHE_FAST_V2',1,true)then\n"
for before,after in fast['changes']:installer+='t=replace(t,[=['+before+']=],[=['+after+']=])\n'
installer+='end\n'
for before,after in workerChanges:installer+='t=replace(t,[=['+before+']=],[=['+after+']=])\n'
installer+='return t end)\n'
installer+="plan('/home/bec_auto.lua','BEC_V1_IDLE_CACHE_FAST_V2',function(t)return replace(t,[=["+fast['controllerBefore']+"]=],[=["+fast['controllerAfter']+"]=])end)\n"
installer+="plan('/home/bec_cache_ui.lua','BEC_V1_CACHE_CUSTOM_UI_V1',function(t)\nif not t:find('BEC_V1_CACHE_STATUS_FAST_V2',1,true)then\n"
for before,after in fast['uiChanges']:installer+='t=replace(t,[=['+before+']=],[=['+after+']=])\n'
installer+='end\n'
for before,after in uiChanges:installer+='t=replace(t,[=['+before+']=],[=['+after+']=])\n'
installer+='return t end)\n'+suffix
(folder/'patch_custom.lua').write_text(installer,encoding='utf-8')
