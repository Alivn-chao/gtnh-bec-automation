from pathlib import Path
folder=Path(__file__).parent
control=(folder/'control.lua.inc').read_text(encoding='utf-8')
body=(folder/'batch.lua.inc').read_text(encoding='utf-8').replace('CONTROL_BODY',control)
installer=(folder/'installer.lua.inc').read_text(encoding='utf-8')
(folder/'patch_v1.lua').write_text(installer.replace('CONTROL_BODY',control).replace('BATCH_BODY',body),encoding='utf-8')
(folder/'check.lua').write_text("local c=require('component')\n"+control+"\nlocal a=batchControlAddress(c)\nprint('节点启停组件: '..a)\nprint('允许工作: '..tostring(c.invoke(a,'isWorkAllowed')))\nprint('状态: '..tostring(c.invoke(a,'getState')))\nprint('只读检查；未启停或搬料。')\n",encoding='utf-8')
