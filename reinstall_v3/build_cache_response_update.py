"""Small transactional patch for cache UI response on the first V3 preview."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import zlib

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
V2=ROOT/'reinstall_v2'
sys.path.insert(0,str(V2))
from build import literal

NAMES=['lib/cache.lua','lib/web_session.lua','lib/web_transport.lua','web.lua','lib/web_page.html']
BASE='0e3926a'
def signature(data):return str(len(data))+':'+str(zlib.adler32(data)&0xffffffff)
def baseline(name):return subprocess.check_output(['git','show',BASE+':reinstall_v2/files/'+name],cwd=ROOT).decode('utf-8')

def build():
    rows=[]
    for name in NAMES:
        old=baseline(name)
        text=(V2/'files'/name).read_text(encoding='utf-8')
        source=literal(text)
        if name.endswith('.html'):
            # Keep the unchanged embedded 3-D model out of the download.
            prefix=os.path.commonprefix([old,text])
            suffix=os.path.commonprefix([old[::-1],text[::-1]])
            count=min(len(suffix),len(old)-len(prefix),len(text)-len(prefix))
            middle=text[len(prefix):len(text)-count if count else len(text)]
            tail="..old:sub(-"+str(len(text[-count:].encode()))+")"if count else ''
            source="(function()local f=assert(io.open('/home/bec_v2/lib/web_page.html','r'));local old=f:read('*a');f:close();old=old:gsub('\\r\\n','\\n');if sig(old)=="+repr(signature(text.encode()))+"then return old end;assert(sig(old)=="+repr(signature(old.encode()))+",'未知本地网页，保留未覆盖');local new=old:sub(1,"+str(len(prefix.encode()))+").."+literal(middle)+tail+";assert(sig(new)=="+repr(signature(text.encode()))+",'网页补丁核对失败，原文件未改');return new end)()"
        rows.append('{name='+repr(name)+',source='+source+',supported={['+repr(signature(old.encode()))+']=true}}')
    tree=ast.parse((V2/'build_cache_update.py').read_text(encoding='utf-8'))
    body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
    body=body.replace('/home/bec_cache_update.lua','/home/bec_v3_cache_update.lua')
    body=body.replace("if debug.getinfo(1,'S').source=='@'..self then",'do')
    body=body.replace('BEC_V2_CACHE_UPDATE_1','BEC_V3_CACHE_RESPONSE_UPDATE_1')
    body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')",'pcall(fs.remove,self)')
    for old,new in [('before-cache-','before-v3-cache-'),('cache-new-','v3-cache-new-'),('cache-failed-','v3-cache-failed-')]:body=body.replace(old,new)
    body=body.replace('缓存管理功能已安装，无需重复更新。','V3缓存翻页与保存响应修复已安装，无需重复更新。')
    body=body.replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','V3缓存响应修复已安装：本地翻页，后台读取间隙处理缓存值保存。')
    sig="local function sig(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end\n"
    payload="print('BEC V3 cache response update; Q to exit the old UI first')\n"+sig+'local rows={'+','.join(rows)+'}\n'+body
    assert len(payload.encode())<100000,'Compact update unexpectedly large'
    (HERE/'update_cache_response.lua').write_text('-- BEC_V3_CACHE_RESPONSE_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature(payload.encode()))+'\n'+payload,encoding='utf-8',newline='\n')
    print('Built V3 cache response updater:',len(payload.encode()),'payload bytes;',len(NAMES),'programs')

if __name__=='__main__':build()
