"""Patch the deployed fixed-quota V3 to GTNH 2.9.0 with atomic rollback."""
import ast
from pathlib import Path
import subprocess
import sys
import zlib

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
sys.path.insert(0,str(ROOT/'reinstall_v2'))
from build import literal

NAMES=['lib/config.lua','lib/cell_feed.lua','web.lua','cache_zero_recover.lua']
BASE='ff5da13'
def signature(data):return str(len(data))+':'+str(zlib.adler32(data)&0xffffffff)

GUARD=r'''
local c=require('component')
for a in c.list('hd_panel',true)do
 local owner=rawget(c.proxy(a),'_becWebOwner')
 assert(not owner or owner.closed or owner.root and coroutine.status(owner.root)=='dead','先在OC按Q退出网页，等待完整收尾')
end
local C=assert(loadfile(root..'lib/config.lua'))();local cfg=C.load()
local function stopped(path,kind)
 local r=C.read(C.path(path));if not r then return end
 assert(r.stage=='stopped'and not r.pending and not r.plan and not r.incomplete,kind..'尚未完整结束，保留现场，不更新')
 for _,job in pairs(r.requests or{})do assert(job.state=='done'or job.state=='rejected'and job.preSubmissionFailed,'AE申请尚未确认，不更新')end
end
for group,g in ipairs(cfg.groups)do
 stopped('state/group-'..group..'/cell-feed.journal','原料盘')
 stopped('state/group-'..group..'/cohort.dat','生产组')
 stopped('state/group-'..group..'/cache.journal','缓存')
 local io=C.read(C.path('state/group-'..group..'/nanites-cell.journal'))
 assert(not io or io.stage=='done'and not io.pending,'蜂群IO尚未完成，不更新')
 for _,a in ipairs(g.generators)do assert(not c.invoke(a,'isWorkAllowed')and not c.invoke(a,'isMachineActive'),'纠缠器未完整停止，不更新')end
end
for i,n in ipairs(cfg.nodes)do
 stopped('state/node-'..i..'/production.journal','节点生产')
 assert(c.invoke(n.address,'getState')=='idle'and c.invoke(n.address,'isWorkAllowed')==false and c.invoke(n.redstone,'getOutput',n.pauseSide)==15,'节点尚未空闲/关闭/暂停，不更新')
end
'''

def build():
 rows=[]
 for name in NAMES:
  old=[subprocess.check_output(['git','show',ref+':reinstall_v2/files/'+name],cwd=ROOT)for ref in (BASE,'2adf11f','0848982')]
  text=(ROOT/'reinstall_v2/files'/name).read_text(encoding='utf-8')
  known=','.join('['+repr(s)+']=true'for s in sorted({signature(v)for v in old}))
  rows.append('{name='+repr(name)+',source='+literal(text)+',supported={'+known+'}}')
 tree=ast.parse((ROOT/'reinstall_v2/build_cache_update.py').read_text(encoding='utf-8'))
 body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
 for old,new in [('BEC_V2_CACHE_UPDATE_1','BEC_RELEASE_290_UPDATE_1'),('/home/bec_cache_update.lua','/home/bec_290_update.lua'),('before-cache-','before-release290-'),('cache-new-','release290-new-'),('cache-failed-','release290-failed-')]:body=body.replace(old,new)
 body=body.replace("if debug.getinfo(1,'S').source=='@'..self then",'do')
 body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');",'pcall(fs.remove,self);')
 body=body.replace('缓存管理功能已安装，无需重复更新。','2.9.0兼容更新已安装，无需重复更新。')
 body=body.replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','2.9.0兼容更新已安装：异步写入确认、固定配额同时接单。')
 body=body.replace('local disk=assert(fs.get(root));',GUARD+'\nlocal disk=assert(fs.get(root));')
 payload="print('BEC GTNH 2.9.0 compatibility; finish all batches and press Q first')\nlocal rows={"+','.join(rows)+'}\n'+body
 (HERE/'update_290.lua').write_text('-- BEC_RELEASE_290_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature(payload.encode()))+'\n'+payload,encoding='utf-8',newline='\n')
 print('Built 2.9.0 compatibility updater:',len(payload.encode()),'bytes;',len(NAMES),'programs')

if __name__=='__main__':build()
