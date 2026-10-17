"""Compact exact-baseline patch; shared model HTML is reconstructed locally."""
from pathlib import Path
import ast,subprocess,zlib,os
from build import literal
HERE=Path(__file__).resolve().parent
REFS=['9bd9003','3a796b2','6bb05c6','5ad2b03','166f844','a8c9b3e','acfc08c']
def signature(data):return str(len(data))+':'+str(zlib.adler32(data)&0xffffffff)
rows=[]
for name in ['lib/cache.lua','lib/web_session.lua','lib/web_page.html']:
 supported={}
 for ref in REFS:
  data=subprocess.check_output(['git','show',ref+':reinstall_v2/files/'+name],cwd=HERE.parent)
  supported[signature(data)]=data.decode('utf-8')
 text=(HERE/'files'/name).read_text(encoding='utf-8')
 source=literal(text)
 if name.endswith('.html'):
  old=next(iter(supported.values()));assert all(v==old for v in supported.values()),'HTML bases differ'
  prefix=os.path.commonprefix([old,text]);suffix=os.path.commonprefix([old[::-1],text[::-1]])[::-1]
  suffix=suffix[-min(len(suffix),len(old)-len(prefix),len(text)-len(prefix)):]
  middle=text[len(prefix):len(text)-len(suffix)]
  prefix_bytes=len(prefix.encode());suffix_bytes=len(suffix.encode())
  checks=' or '.join('sig(old)=='+repr(k)for k in supported)
  source="(function()local f=assert(io.open('/home/bec_v2/lib/web_page.html','r'));local old=f:read('*a');f:close();old=old:gsub('\\r\\n','\\n');if sig(old)=="+repr(signature(text.encode()))+"then return old end;assert("+checks+",'未知本地网页，保留未覆盖');local new=old:sub(1,"+str(prefix_bytes)+").."+literal(middle)+"..old:sub(-"+str(suffix_bytes)+");assert(sig(new)=="+repr(signature(text.encode()))+",'网页补丁核对失败，原文件未改');return new end)()"
 keys=','.join('['+repr(k)+']=true'for k in supported)
 rows.append('{name='+repr(name)+',source='+source+',supported={'+keys+'}}')
tree=ast.parse((HERE/'build_cache_update.py').read_text(encoding='utf-8'))
body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
body=body.replace('/home/bec_cache_update.lua','/home/bec_browse_update.lua').replace("if debug.getinfo(1,'S').source=='@'..self then",'do').replace('BEC_V2_CACHE_UPDATE_1','BEC_V2_BROWSE_UPDATE_1')
body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')",'pcall(fs.remove,self)')
body=body.replace('before-cache-','before-browse-').replace('cache-new-','browse-new-').replace('cache-failed-','browse-failed-')
body=body.replace('缓存管理功能已安装，无需重复更新。','浏览与提交分离修复已安装，无需重复更新。').replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','缓存提交期间可浏览分页；输入保留，重复保存仍受保护。')
sig="local function sig(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end\n"
payload="print('BEC browse update; Q to exit the old UI first')\n"+sig+'local rows={'+','.join(rows)+'}\n'+body
(HERE/'update_browse.lua').write_text('-- BEC_V2_BROWSE_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature(payload.encode()))+'\n'+payload,encoding='utf-8',newline='\n')
print('Built update_browse.lua:',len(payload.encode()),'payload bytes')
