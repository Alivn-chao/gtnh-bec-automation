"""Small, transactional partial-cache fix plus explicit receipt reconciliation."""
from pathlib import Path
import ast,subprocess,zlib
from build import literal
HERE=Path(__file__).resolve().parent
NAMES=['runtime/cache.lua','cache_recover.lua']
rows=[]
for name in NAMES:
 signatures=[]
 for ref in ['9afccb3','9bd9003','3a796b2','6bb05c6','5ad2b03']:
  result=subprocess.run(['git','show',ref+':reinstall_v2/files/'+name],cwd=HERE.parent,capture_output=True)
  if result.returncode:continue
  data=result.stdout
  signatures.append('['+repr(str(len(data))+':'+str(zlib.adler32(data)&0xffffffff))+']=true')
 rows.append('{name='+repr(name)+',added='+('true'if name=='cache_recover.lua'else 'false')+',source='+literal((HERE/'files'/name).read_text(encoding='utf-8'))+',supported={'+','.join(signatures)+'}}')
tree=ast.parse((HERE/'build_cache_update.py').read_text(encoding='utf-8'))
body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
body=body.replace('/home/bec_cache_update.lua','/home/bec_cache_partial_update.lua').replace("if debug.getinfo(1,'S').source=='@'..self then",'do')
body=body.replace('BEC_V2_CACHE_UPDATE_1','BEC_V2_CACHE_PARTIAL_UPDATE_1')
body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')",'pcall(fs.remove,self)')
body=body.replace('before-cache-','before-cache-partial-').replace('cache-new-','cache-partial-new-').replace('cache-failed-','cache-partial-failed-')
body=body.replace('缓存管理功能已安装，无需重复更新。','缓存部分返回修复已安装，无需重复更新。').replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','缓存部分返回修复已安装；原未确认日志保留，须另行核对收尾。')
payload="print('BEC partial cache update; Q to exit the old UI first')\nlocal rows={"+','.join(rows)+'}\n'+body
data=payload.encode('utf-8');signature=str(len(data))+':'+str(zlib.adler32(data)&0xffffffff)
(HERE/'update_cache_partial.lua').write_text('-- BEC_V2_CACHE_PARTIAL_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature)+'\n'+payload,encoding='utf-8',newline='\n')
print('Built update_cache_partial.lua:',len(data),'payload bytes')
