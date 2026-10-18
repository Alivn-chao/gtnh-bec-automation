"""Recognize public program backups without embedding their contents."""
from pathlib import Path
import subprocess,io,tarfile,zlib
from build import literal
HERE=Path(__file__).resolve().parent
REFS=['334125a','81b7724','f60f785','933750b','180bf41','bccf281','438f625','dae5e0e','d26100c','9afccb3','9bd9003','3a796b2','6bb05c6','5ad2b03','166f844','a8c9b3e','acfc08c','07522a8']
programs={p.relative_to(HERE/'files').as_posix():set()for p in (HERE/'files').rglob('*')if p.is_file()and p.suffix in ['.lua','.html']and p.name!='disk_cleanup.lua'}
downloads={'bec_hive_update.lua':'update_hive.lua','bec_display_update.lua':'update_display.lua','bec_cohort_update.lua':'update_cohort.lua','bec_cache_partial_update.lua':'update_cache_partial.lua','bec_connection_update.lua':'update_connection.lua','bec_cache_update.lua':'update_cache.lua','bec_web_update.lua':'update_web.lua','bec_patterns_update.lua':'update_patterns.lua','bec_dynamic_update.lua':'update_dynamic_nanites.lua','bec_bulk10.lua':'update_bulk10.lua','bec_v2_install.lua':'install.lua'}
hashes={name:set()for name in downloads}
def sig(b):b=b.replace(b'\r\n',b'\n');return str(len(b))+':'+str(zlib.adler32(b)&0xffffffff)
for ref in REFS:
 data=subprocess.check_output(['git','archive',ref,'reinstall_v2'],cwd=HERE.parent)
 with tarfile.open(fileobj=io.BytesIO(data))as archive:
  for member in archive:
   if not member.isfile():continue
   path=member.name.removeprefix('reinstall_v2/')
   if path.startswith('files/')and path[6:]in programs:programs[path[6:]].add(sig(archive.extractfile(member).read()))
   for name,target in downloads.items():
    if path==target:hashes[name].add(sig(archive.extractfile(member).read()))
for name,known in programs.items():known.add(sig((HERE/'files'/name).read_bytes()))
def keys(v):return '{'+','.join('['+repr(k)+']=true'for k in sorted(v))+'}'
tables='local PROGRAMS={'+','.join('{name='+repr(n)+',known='+keys(v)+'}'for n,v in sorted(programs.items()))+'}\n'
tables+='local DOWNLOADS={'+','.join('{path='+repr('/home/'+n)+',known='+keys(hashes[n])+'}'for n in sorted(downloads))+'}\n'
core=(HERE/'disk_cleanup.lua.inc').read_text(encoding='utf-8')
(HERE/'disk_cleanup_data.lua.inc').write_text(tables,encoding='utf-8',newline='\n')
source="local mode=...;assert(mode==nil or mode=='preview'or mode=='run','用法: preview / run')\n"+tables+'local cleanup=assert(load('+literal(core)+",'@disk-cleanup-core','t',_ENV))()(PROGRAMS,DOWNLOADS)\ncleanup(mode=='run')\n"
(HERE/'files/disk_cleanup.lua').write_text(source,encoding='utf-8',newline='\n')
print('Built disk_cleanup.lua:',len(source.encode()),'bytes;',len(programs),'program paths')
