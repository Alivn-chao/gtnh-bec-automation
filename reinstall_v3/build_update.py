"""Build a transactional V3 preview update for the existing V2 installation."""
import ast
from pathlib import Path
import subprocess
import sys
import zlib

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
V2=ROOT/'reinstall_v2'
sys.path.insert(0,str(V2))
from build import literal

NAMES=['runtime/controller.lua','runtime/nanites_cell.lua','lib/bridge.lua']
BASES=['a293a34','07522a8']
def signature(data):return str(len(data))+':'+str(zlib.adler32(data)&0xffffffff)
def old(ref,name):return subprocess.check_output(['git','show',ref+':reinstall_v2/files/'+name],cwd=ROOT)

rows=[]
for name in NAMES:
    supported=','.join('['+repr(s)+']=true'for s in sorted({signature(old(ref,name))for ref in BASES}))
    rows.append('{name='+repr(name)+',source='+literal((V2/'files'/name).read_text(encoding='utf-8'))+',supported={'+supported+'}}')

# Reuse the proven flush/read-back/backup/CAS/rollback updater transaction.
tree=ast.parse((V2/'build_cache_update.py').read_text(encoding='utf-8'))
body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
body=body.replace('/home/bec_cache_update.lua','/home/bec_v3_update.lua')
body=body.replace("if debug.getinfo(1,'S').source=='@'..self then",'do')
body=body.replace('BEC_V2_CACHE_UPDATE_1','BEC_V3_PERFORMANCE_UPDATE_1')
body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')",'pcall(fs.remove,self)')
body=body.replace('before-cache-','before-v3-performance-').replace('cache-new-','v3-performance-new-').replace('cache-failed-','v3-performance-failed-')
body=body.replace('缓存管理功能已安装，无需重复更新。','V3提速预览已安装，无需重复更新。')
body=body.replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','V3提速预览已安装：合并读取、批次配方索引、库存命中快速开工、换蜂检查去重。')
guards=[]
for name in ['lib/engine.lua','lib/config.lua']:
    guards.append("do local text=normal(read(root.."+repr(name)+"));assert(text and signature(text)=="+repr(signature(old('a293a34',name)))+",'V2配套模块版本不符，未替换: "+name+"')end")
marker='local old,identical,bytes={},true,0'
assert body.count(marker)==1
body=body.replace(marker,'\n'.join(guards)+'\n'+marker)
payload="print('BEC V3 performance preview; Q to exit the old UI first')\nlocal rows={"+','.join(rows)+'}\n'+body
(HERE/'update.lua').write_text('-- BEC_V3_PERFORMANCE_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature(payload.encode()))+'\n'+payload,encoding='utf-8',newline='\n')
print('Built V3 updater:',len(payload.encode()),'payload bytes;',len(NAMES),'programs')
