from pathlib import Path
folder=Path(__file__).parent
worker=(folder/'reset.lua').read_text(encoding='utf-8')
template=(folder/'installer.lua.inc').read_text(encoding='utf-8')
(folder/'patch_v1.lua').write_text(template.replace('RESET_BODY',worker),encoding='utf-8')
