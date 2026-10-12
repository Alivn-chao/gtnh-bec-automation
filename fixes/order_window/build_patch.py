"""Refresh the embedded helper without altering the installer's safety checks."""
from pathlib import Path
root=Path(__file__).parent
p=root/'patch_v1.lua'
s=p.read_text(encoding='utf-8')
start=s.index('[==[')+4
end=s.index(']==]',start)
p.write_text(s[:start]+(root/'window.lua.inc').read_text(encoding='utf-8')+s[end:],encoding='utf-8')
