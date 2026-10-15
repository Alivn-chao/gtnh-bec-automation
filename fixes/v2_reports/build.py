from pathlib import Path

HERE=Path(__file__).parent
def literal(s):
    for n in range(1,12):
        close=']'+'='*n+']'
        if close not in s:return '['+'='*n+'['+s+close
    raise ValueError('Lua long string delimiter collision')

(HERE/'patch_v1.lua').write_text(
    'local REPORT_SOURCE='+literal((HERE/'reports.lua').read_text(encoding='utf-8'))+'\n'
    +'local SETUP_SOURCE='+literal((HERE/'setup.lua').read_text(encoding='utf-8'))+'\n'
    +(HERE/'installer.lua.inc').read_text(encoding='utf-8'),encoding='utf-8',newline='\n')
