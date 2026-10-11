from pathlib import Path
folder=Path(__file__).parent
prepare=(folder/'prepare.lua.inc').read_text(encoding='utf-8')
recover=(folder/'recover.lua.inc').read_text(encoding='utf-8')
template='''-- Upgrade only the installed production controller, preserving every journal.
local fs=require('filesystem')
local path='/home/bec_auto.lua'
local function read(p)local f=assert(io.open(p,'r'));local text=f:read('*a');f:close();return assert(text)end
local function replace(text,from,to)
 local a,b=text:find(from,1,true)
 assert(a and not text:find(from,b+1,true),'流水补丁入口缺失或不唯一，原文件未改')
 return text:sub(1,a-1)..to..text:sub(b+1)
end
local original=read(path)
if original:find('BEC_V1_PIPELINE_V1',1,true)then print('流水备料补丁已安装');return end
local modified=original:gsub('\\r\\n','\\n')
local prepare=[=[PREPARE]=]
local recover=[=[RECOVER]=]
modified=replace(modified,'end local function serve()', 'end\\n'..prepare..'\\nlocal function serve()')
modified=replace(modified,'local old=ser.unserialize(contents) local streaming=',
 'local old=ser.unserialize(contents)\\n'..recover..'\\nlocal streaming=')
modified=replace(modified,'for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.25) end',
 'if record.pipelineComplete then unchanged();assert(next(network(SUB))==nil,"流水转换后子网非空");record.pipelineComplete=nil else for i=1,20 do unchanged();assert(same(network(SUB),expected),"原液不稳定");os.sleep(0.25) end end')
assert(load(modified,'@'..path,'t',_ENV),'流水补丁后语法检查失败')
local n=1;while fs.exists(path..'.before-pipeline-'..n) or fs.exists(path..'.pipeline-new-'..n)do n=n+1 end
local backup,temp=path..'.before-pipeline-'..n,path..'.pipeline-new-'..n
local f=assert(io.open(temp,'w'));assert(f:write(modified));assert(f:flush());f:close()
assert(read(temp)==modified,'流水临时文件回读失败')
assert(fs.rename(path,backup),'备份失败，原文件保留')
if not fs.rename(temp,path)then assert(fs.rename(backup,path),'还原失败，原文件在 '..backup);error('替换失败，已还原')end
assert(read(path)==modified and read(backup)==original,'流水替换或备份回读失败')
print('并行下单/收液纠缠补丁已安装；备份: '..backup)
print('未启停机器或改日志。正常Q停止后继续: lua /home/bec_ui.lua run')
'''
(folder/'patch_v1.lua').write_text(template.replace('PREPARE',prepare).replace('RECOVER',recover),encoding='utf-8')
