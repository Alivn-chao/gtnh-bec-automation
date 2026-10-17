"""Exact cache-release update for heartbeats and post-swap release recovery."""
from pathlib import Path
import ast,subprocess,zlib
from build import literal
HERE=Path(__file__).resolve().parent
NAMES=['lib/cache.lua','web.lua','lib/web_session.lua','lib/web_page.html','lib/web_transport.lua','lib/config.lua','lib/engine.lua','lib/bridge.lua','runtime/controller.lua']
rows=[]
for name in NAMES:
 result=subprocess.run(['git','show','9afccb3:reinstall_v2/files/'+name],cwd=HERE.parent,capture_output=True)
 old=result.stdout
 supported=repr(str(len(old))+':'+str(zlib.adler32(old)&0xffffffff))
 rows.append('{name='+repr(name)+',added='+('true'if name=='lib/web_transport.lua'else 'false')+',source='+literal((HERE/'files'/name).read_text(encoding='utf-8'))+',supported={['+supported+']=true}}')
# Share the verified staging/backup/rollback transaction, without running its builder.
tree=ast.parse((HERE/'build_cache_update.py').read_text(encoding='utf-8'))
body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
body=body.replace('/home/bec_cache_update.lua','/home/bec_connection_update.lua')
body=body.replace("if debug.getinfo(1,'S').source=='@'..self then",'do')
body=body.replace('BEC_V2_CACHE_UPDATE_1','BEC_V2_CONNECTION_UPDATE_1')
body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')", "local ok,removed,reason=pcall(fs.remove,self)\n  if not fs.exists(self)then print('已释放临时安装包；程序备份和运行记录保留。')\n  else print('临时包保留，继续检查可用空间：'..tostring(ok and reason or removed))end")
body=body.replace('before-cache-','before-connection-').replace('cache-new-','connection-new-').replace('cache-failed-','connection-failed-')
body=body.replace('缓存管理功能已安装，无需重复更新。','连接与换蜂恢复修复已安装，无需重复更新。')
body=body.replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','连接心跳与换蜂后恢复修复已安装；请重新打开网页。')
payload="print('BEC connection update; Q to exit the old UI first')\nlocal rows={"+','.join(rows)+'}\n'+body
data=payload.encode('utf-8');signature=str(len(data))+':'+str(zlib.adler32(data)&0xffffffff)
(HERE/'update_connection.lua').write_text('-- BEC_V2_CONNECTION_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature)+'\n'+payload,encoding='utf-8',newline='\n')
print('Built update_connection.lua:',len(rows),'files;',len(data),'payload bytes')
