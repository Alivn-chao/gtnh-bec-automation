from pathlib import Path
here=Path(__file__).parent
template=(here/'installer.lua.inc').read_text(encoding='utf-8')
for key,path in [('CPU_INSTALL',here.parent/'cpu_wait/patch_v1.lua'),('RESET_BODY',here/'reset.lua'),('SEQUENTIAL_BODY',here/'sequential.lua.inc')]:
    template=template.replace(key,path.read_text(encoding='utf-8'))
(here/'patch_v1.lua').write_text(template,encoding='utf-8')
