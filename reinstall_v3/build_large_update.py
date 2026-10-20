"""Preserve the whole physical cohort; update only the V3 production controller."""
import ast
from pathlib import Path
import subprocess
import sys
from build_cache_admission_update import signature
HERE=Path(__file__).resolve().parent;ROOT=HERE.parent
sys.path.insert(0,str(ROOT/'reinstall_v2'))
from build import literal
NAME='runtime/controller.lua';BASE='bf1ae6f'
def baseline(name=NAME):return subprocess.check_output(['git','show',BASE+':reinstall_v2/files/'+name],cwd=ROOT).decode('utf-8')
def build():
 text=(ROOT/'reinstall_v2/files'/NAME).read_text(encoding='utf-8')
 prior=subprocess.check_output(['git','show','3ed7e69:reinstall_v2/files/'+NAME],cwd=ROOT).decode('utf-8')
 row='{name='+repr(NAME)+',source='+literal(text)+',supported={['+repr(signature(baseline()))+']=true,['+repr(signature(prior))+']=true}}'
 tree=ast.parse((ROOT/'reinstall_v2/build_cache_update.py').read_text(encoding='utf-8'))
 body=next(ast.literal_eval(n.value)for n in tree.body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=='body'for t in n.targets))
 body=body.replace('/home/bec_cache_update.lua','/home/bec_v3_surplus_update.lua')
 body=body.replace("if debug.getinfo(1,'S').source=='@'..self then",'do').replace('BEC_V2_CACHE_UPDATE_1','BEC_V3_LARGE_UPDATE_1')
 body=body.replace("assert(fs.remove(self),'无法释放本次临时下载包');print('已释放本次临时安装包；程序备份和运行记录保留。')",'pcall(fs.remove,self)')
 body=body.replace('before-cache-','before-v3-large-').replace('cache-new-','v3-large-new-').replace('cache-failed-','v3-large-failed-')
 body=body.replace('缓存管理功能已安装，无需重复更新。','SURPLUS RECOVERY r2：本版已安装，无需重复更新。')
 body=body.replace('缓存管理已安装：顶部缓存管理设置目标，启动自动化后空闲补库。','V3大总量并行修复已安装。保持同批所有节点并行，不修改力场强度/节点并行数。原生产与蜂群记录保留，重新打开网页启动时按原恢复守卫核对。')
 guards=[]
 for name in ['lib/engine.lua','lib/bridge.lua']:
  guards.append("do local v=normal(read(root.."+repr(name)+"));assert(v and signature(v)=="+repr(signature(baseline(name)))+",'V3配套模块不匹配，未替换: "+name+"')end")
 body=body.replace('local old,identical,bytes={},true,0','\n'.join(guards)+'\nlocal old,identical,bytes={},true,0',1)
 payload="print('BEC V3 SURPLUS RECOVERY r2 / Q to exit the old UI first')\nlocal rows={"+row+'}\n'+body
 script='-- BEC_V3_LARGE_UPDATE_1\nlocal SELF_SIGNATURE='+repr(signature(payload))+'\n'+payload
 (HERE/'update_large.lua').write_text(script,encoding='utf-8',newline='\n')
 print('Built large-total updater:',len(script.encode()),'bytes')
if __name__=='__main__':build()
