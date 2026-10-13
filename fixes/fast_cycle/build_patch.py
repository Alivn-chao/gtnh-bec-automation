from pathlib import Path
folder=Path(__file__).parent
module=(folder.parent/'nanites_io/bec_nanites.lua').read_text(encoding='utf-8')
template=(folder/'installer.lua.inc').read_text(encoding='utf-8')
(folder/'patch_v1.lua').write_text(template.replace('MODULE_BODY',module),encoding='utf-8')
