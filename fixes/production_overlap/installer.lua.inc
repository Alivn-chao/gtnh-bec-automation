-- Upgrade the existing pipeline; preserve installed bee, filter and UI fixes.
local fs=require('filesystem');local c=require('component')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local s=f:read('*a');f:close();return assert(s)end
local original=read(path)
if original:find('BEC_V1_PRODUCTION_OVERLAP_V2',1,true)then print('生产/纠缠并行补丁V2已安装');return end
local function section(s,first,last,new)
 local a,b=s:find(first,1,true);assert(a and not s:find(first,b+1,true),'入口缺失或不唯一: '..first)
 local z=assert(s:find(last,b+1,true),'结束入口缺失: '..last)
 return s:sub(1,a-1)..new..s:sub(z)
end
local upgrading=original:find('BEC_V1_PRODUCTION_OVERLAP_V1',1,true)~=nil
local modified=section(original,upgrading and '-- BEC_V1_PRODUCTION_OVERLAP_V1:' or '-- BEC_V1_PIPELINE_V1:','local function serve()',[==[PREPARE_BODY]==]..'\n')
modified=section(modified,'if type(old)=="table" and type(old.pipeline)=="table" and old.plan~=nil then','local streaming=',[==[RECOVER_BODY]==]..'\n')
if not upgrading then
local marker='local expected=prepareStreaming(target)'
local a,b=modified:find(marker,1,true);assert(a and not modified:find(marker,b+1,true),'生产入口不唯一')
modified=modified:sub(1,b)..' if record.productionOverlapHandled then record.productionOverlapHandled=nil else '..modified:sub(b+1)
local count
modified,count=modified:gsub('end%s+end%s+end%s+pause%(15%);generator%(false%);record.configOwned=false',
 'end end end end pause(15);generator(false);record.configOwned=false')
assert(count==1,'生产循环结束入口不唯一，原文件未改')
end
assert(load(modified,'@'..path,'t',_ENV),'并行生产补丁语法检查失败')
assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'先在面板按Q正常停止')
assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false
 and c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isMachineActive')==false,'先等纠缠装置停机')
local n=1;while fs.exists(path..'.before-overlap-'..n)or fs.exists(path..'.overlap-new-'..n)do n=n+1 end
local backup,temp=path..'.before-overlap-'..n,path..'.overlap-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close();assert(read(temp)==modified,'临时文件回读失败')
assert(fs.rename(path,backup),'备份失败')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'备份还原失败');error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'文件回读失败')
print('生产/供液/纠缠并行补丁已安装；备份: '..backup)
print('配置、订单和日志保留。继续: lua /home/bec_ui.lua resume')
