from pathlib import Path
here = Path(__file__).parent
body = (here/'jobs.lua.inc').read_text(encoding='utf-8')
template = (here/'installer.lua.inc').read_text(encoding='utf-8')
(here/'patch_v1.lua').write_text(template.replace('JOBS_BODY',body),encoding='utf-8')
