"""Create a self-contained OpenOS installer and distributable clean-install ZIP."""
from pathlib import Path
import hashlib
import json
import zipfile

HERE=Path(__file__).resolve().parent
def literal(s):
    for n in range(1,20):
        ending=']'+'='*n+']'
        if ending not in s:return '['+'='*n+'['+s+ending
    raise ValueError('delimiter collision')

def build():
    from build_web import build as build_web
    build_web()
    entries=[]; manifest={}
    for p in sorted((HERE/'files').rglob('*')):
        if not p.is_file():continue
        name=p.relative_to(HERE/'files').as_posix()
        data=p.read_bytes().replace(b'\r\n',b'\n')
        entries.append('{'+json.dumps(name)+','+literal(data.decode('utf-8'))+'}')
        manifest[name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    text='-- BEC V2 clean-install bundle; no V1 dependency.\nlocal FILES={\n'+',\n'.join(entries)+'\n}\n'+(HERE/'installer.lua.inc').read_text(encoding='utf-8')
    (HERE/'install.lua').write_text(text,encoding='utf-8',newline='\n')
    (HERE/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
    output=HERE/'dist';output.mkdir(exist_ok=True)
    with zipfile.ZipFile(output/'bec-v2-clean-install.zip','w',zipfile.ZIP_DEFLATED)as z:
        for p in [HERE/'install.lua',HERE/'README.md',HERE/'manifest.json',HERE/'OCHD_PROGRESS.md',HERE/'WEB_INPUT.md',HERE/'BULK10.md',HERE/'COMPONENT_PICKER.md',HERE/'WEB_PATTERNS.md',HERE/'READ_OPTIMIZATION.md',HERE/'STAGE_LATENCY.md',HERE/'BATCH_STOP.md',HERE/'update_reads.lua',HERE/'update_web.lua',HERE/'update_bulk10.lua',HERE/'update_discovery.lua',HERE/'update_patterns.lua',HERE/'update_cache.lua',HERE/'update_connection.lua',HERE/'WEB_CONNECTION.md',HERE/'update_hive.lua',HERE/'HIVE_INSPECTION.md',HERE/'update_cohort.lua',HERE/'IDLE_COHORT.md',HERE/'update_cache_partial.lua',HERE/'CACHE_PARTIAL.md',HERE/'update_display.lua',HERE/'DISPLAY_LATENCY.md',HERE/'update_browse.lua',HERE/'CACHE_BROWSE.md',HERE/'update_finish.lua',HERE/'DISK_FINISH.md',*(HERE/'files').rglob('*')]:
            if p.is_file():z.writestr(p.relative_to(HERE).as_posix(),p.read_bytes().replace(b'\r\n',b'\n'))
    print('Bundled',len(entries),'files;',len(text.encode('utf-8')),'installer bytes')

if __name__=='__main__':build()
