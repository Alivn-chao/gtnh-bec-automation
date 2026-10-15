"""Empty OpenOS disk, failed transactions and entry points; no game hardware claim."""
import hashlib
import json
import sys
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=ROOT/'reinstall_v2'
from lupa.lua52 import LuaRuntime

INSTALL=(HERE/'install.lua').read_text(encoding='utf-8')
SETUP=r'''
files={['/home/bec_auto.lua']='old-v1', ['/home/bec_auto.journal']='old-evidence'}
dirs={['/home']=true};count=0
local fs={}
fs.exists=function(p)return files[p]~=nil or dirs[p]~=nil end
fs.makeDirectory=function(p)dirs[p]=true;return true end
fs.remove=function(p)files[p]=nil;dirs[p]=nil;return true end
fs.rename=function(a,b)
 if failRename then return false end
 assert(not fs.exists(b));assert(dirs[a]);dirs[b]=true;dirs[a]=nil
 local move={};for p,s in pairs(files)do if p:sub(1,#a+1)==a..'/'then move[p]=s end end
 for p,s in pairs(move)do files[b..p:sub(#a+1)]=s;files[p]=nil end
 local moveDirs={};for p in pairs(dirs)do if p:sub(1,#a+1)==a..'/'then moveDirs[#moveDirs+1]=p end end
 for _,p in ipairs(moveDirs)do dirs[b..p:sub(#a+1)]=true;dirs[p]=nil end
 return true
end
package.preload.filesystem=function()return fs end
package.preload.component=function()error('Installer must not load hardware')end
package.preload.shell=function()error('No network downloads allowed during install')end
io.open=function(p,mode)
 if mode=='r'then if files[p]==nil then return end
  return {read=function()return corruptRead and files[p]..'corrupt' or files[p]end,close=function()return true end}
 end
 assert(mode=='w');count=count+1;if failWrite==count then return nil end
 files[p]='';return {write=function(_,s)files[p]=s;return true end,
 flush=function()return not failFlush end,close=function()return true end}
end
print=function()end
'''

def fixture():
    lua=LuaRuntime(unpack_returned_tuples=True);lua.execute(SETUP);return lua

class InstallTests(unittest.TestCase):
    def test_blank_disk_installs_exact_manifest_without_v1_or_machine_access(self):
        lua=fixture();lua.execute(INSTALL)
        manifest=json.loads((HERE/'manifest.json').read_text())
        for p,m in manifest.items():
            s=lua.globals().files['/home/bec_v2/'+p]
            self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),m['sha256'])
        self.assertEqual(lua.globals().files['/home/bec_auto.lua'],'old-v1')
        self.assertEqual(lua.globals().files['/home/bec_auto.journal'],'old-evidence')
        self.assertIsNone(lua.globals().files['/home/bec_v2/config.dat'])
        self.assertIsNone(lua.globals().files['/home/bec_v2/github-upload.dat'])
        self.assertTrue(lua.globals().dirs['/home/bec_v2/recipes'])

    def test_existing_install_refused_without_changing_config(self):
        lua=fixture();lua.execute("dirs['/home/bec_v2']=true;files['/home/bec_v2/config.dat']='keep'")
        with self.assertRaisesRegex(Exception,'已有'):lua.execute(INSTALL)
        self.assertEqual(lua.globals().files['/home/bec_v2/config.dat'],'keep')
        self.assertEqual(lua.eval('count'),0)

    def test_failure_at_every_file_does_not_publish_partial_install(self):
        for n in range(1,len(json.loads((HERE/'manifest.json').read_text()))+1):
            lua=fixture();lua.globals().failWrite=n
            with self.assertRaises(Exception):lua.execute(INSTALL)
            self.assertIsNone(lua.globals().dirs['/home/bec_v2'])
            self.assertFalse(any('.bec-v2-new-'in p for p in lua.globals().files))

    def test_flush_readback_and_final_rename_failure(self):
        for flag in ['failFlush','corruptRead','failRename']:
            lua=fixture();lua.globals()[flag]=True
            with self.assertRaises(Exception):lua.execute(INSTALL)
            self.assertIsNone(lua.globals().dirs['/home/bec_v2'])
            self.assertFalse(any('.bec-v2-new-'in p for p in lua.globals().files))

    def test_leftover_staging_directory_is_not_reused_or_deleted(self):
        lua=fixture();lua.execute("dirs['/home/.bec-v2-new-1']=true;files['/home/.bec-v2-new-1/evidence']='keep'")
        lua.execute(INSTALL)
        self.assertEqual(lua.globals().files['/home/.bec-v2-new-1/evidence'],'keep')

    def test_initial_setup_routes_before_config_load(self):
        for mode,path in [('setup-hd','setup_hd.lua'),('reports','report_setup.lua')]:
            lua=fixture();lua.globals().mode=mode;lua.globals().destination=path
            lua.execute("""
            loadfile=function(p)
             if p=='/home/bec_v2/lib/config.lua'then return function()return {load=function()error('No config yet')end}end end
             assert(p=='/home/bec_v2/'..destination);return function()called=true end
            end
            """)
            main=(HERE/'files/main.lua').read_text(encoding='utf-8')
            lua.eval('function(...)'+main+'\nend')(mode)
            self.assertTrue(lua.globals().called)

if __name__=='__main__':unittest.main()
