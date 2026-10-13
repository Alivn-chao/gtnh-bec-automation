from pathlib import Path
folder = Path(__file__).parent
template = (folder / 'installer.lua.inc').read_text(encoding='utf-8')
body = (folder / 'stage.lua.inc').read_text(encoding='utf-8')
(folder / 'patch_v1.lua').write_text(template.replace('STAGE_BODY', body), encoding='utf-8')
