"""One-file, exact-version fix; never reconciles or deletes runtime journals."""
import ast
from pathlib import Path
import subprocess
import sys
import zlib

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
sys.path.insert(0,str(ROOT/'reinstall_v2'))
from build import literal
NAME='lib/cache.lua'
BASES=['499d433','0e3926a']
def baseline(ref):return subprocess.check_output(['git','show',ref+':reinstall_v2/files/'+NAME],cwd=ROOT).decode('utf-8')
def signature(s):
 data=s.encode('utf-8');return f'{len(data)}:{zlib.adler32(data)&0xffffffff}'
def build():
 text=(ROOT/'reinstall_v2/files'/NAME).read_text(encoding='utf-8')
 supported=','.join('['+repr(s)+']=true'for s in sorted({signature(baseline(ref))for ref in BASES}))
 row='{name='+repr(NAME)+',source='+literal(text)+',supported={'+supported+'}}'
 tree=ast.parse((ROOT/'reinstall_v2/build_cache_update.py').read_text(encoding='utf-8'))
 body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
 body=body.replace('/home/bec_cache_update.lua','/home/bec_v3_cache_admission_update.lua')
 body=body.replace("if debug.getinfo(1,'S').source=='@'..self then",'do')
 body=body.replace('BEC_V2_CACHE_UPDATE_1','BEC_V3_CACHE_ADMISSION_UPDATE_1')
 body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')",'pcall(fs.remove,self)')
 body=body.replace('before-cache-','before-v3-cache-admission-').replace('cache-new-','v3-cache-admission-new-').replace('cache-failed-','v3-cache-admission-failed-')
 body=body.replace('缓存管理功能已安装，无需重复更新。','V3缓存接单隔离修复已安装，无需重复更新。')
 body=body.replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','V3缓存接单隔离修复已安装。未改生产/蜂群/缓存记录；若提示未确认操作，请保留日志核对，不能删除重跑。')
 payload="print('BEC V3 cache admission fix; Q to exit the old UI first')\nlocal rows={"+row+'}\n'+body
 script='-- BEC_V3_CACHE_ADMISSION_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature(payload))+'\n'+payload
 (HERE/'update_cache_admission.lua').write_text(script,encoding='utf-8',newline='\n')
 print('Built V3 cache admission updater:',len(script.encode()),'bytes')
if __name__=='__main__':build()
