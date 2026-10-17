"""Small two-file update for repeated whole-cohort hive inspection reads."""
from pathlib import Path
import ast,subprocess,zlib
from build import literal
HERE=Path(__file__).resolve().parent
NAMES=['lib/bridge.lua','runtime/nanites_cell.lua']
rows=[]
for name in NAMES:
 signatures=[]
 for ref in ['d26100c','9afccb3','9bd9003','3a796b2']:
  data=subprocess.check_output(['git','show',ref+':reinstall_v2/files/'+name],cwd=HERE.parent)
  signatures.append('['+repr(str(len(data))+':'+str(zlib.adler32(data)&0xffffffff))+']=true')
 rows.append('{name='+repr(name)+',source='+literal((HERE/'files'/name).read_text(encoding='utf-8'))+',supported={'+','.join(signatures)+'}}')
tree=ast.parse((HERE/'build_cache_update.py').read_text(encoding='utf-8'))
body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
body=body.replace('/home/bec_cache_update.lua','/home/bec_hive_update.lua').replace("if debug.getinfo(1,'S').source=='@'..self then",'do')
body=body.replace('BEC_V2_CACHE_UPDATE_1','BEC_V2_HIVE_UPDATE_1')
body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')", "pcall(fs.remove,self)")
body=body.replace('before-cache-','before-hive-').replace('cache-new-','hive-new-').replace('cache-failed-','hive-failed-')
body=body.replace('缓存管理功能已安装，无需重复更新。','蜂群检查优化已安装，无需重复更新。').replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','蜂群检查优化已安装：每轮合并整组读取，保留搬盘前后核对。')
payload="print('BEC hive inspection update; Q to exit the old UI first')\nlocal rows={"+','.join(rows)+'}\n'+body
data=payload.encode('utf-8');signature=str(len(data))+':'+str(zlib.adler32(data)&0xffffffff)
(HERE/'update_hive.lua').write_text('-- BEC_V2_HIVE_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature)+'\n'+payload,encoding='utf-8',newline='\n')
print('Built update_hive.lua:',len(data),'payload bytes')
