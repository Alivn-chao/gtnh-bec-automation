"""Bundle the existing real-block studio into one offline OCHD HTML resource."""
from pathlib import Path
import json
HERE=Path(__file__).resolve().parent
def build():
 html=(HERE/'web/structure-base.html').read_text(encoding='utf-8')
 html=html.replace('refreshStatus();}\nfunction refreshStatus','refreshStatus();if(window.BEC_BINDING_DIRTY)window.BEC_BINDING_DIRTY(draft);}\nfunction refreshStatus',1)
 assert 'window.BEC_BINDING_DIRTY(draft)'in html
 # Notify the OC queue immediately, including direction buttons. A snapshot
 # arriving during the local 300-ms debounce must not overwrite the edit.
 html=html.replace('function save(){clearTimeout(timer);','function save(){clearTimeout(timer);if(window.BEC_BINDING_DIRTY)window.BEC_BINDING_DIRTY(draft);',1)
 # Runtime work indication is separate from the selected-module highlight.
 html=html.replace("m.id===self.hovered?.45:0", "m.id===self.hovered?.45:(self.liveStates&&self.liveStates[m.id]==='active'?.7:0)")
 html=html.replace('</head>','<style>'+(HERE/'web/control.css').read_text(encoding='utf-8')+'</style></head>',1)
 html=html.replace('</body>','<script>'+(HERE/'web/input-controls.js').read_text(encoding='utf-8')+'</script><script>'+(HERE/'web/control.js').read_text(encoding='utf-8')+'</script></body>',1)
 html=html.replace('BEC 结构配置台 · 交互原型','BEC V2 · 结构绑定与自动化流程')
 package={'id':'bec-v2-studio','title':'BEC V2 结构绑定与运行','entry':'index.html','files':{'index.html':html},'events':['save_field','apply_bindings','start','pause','select_group','refresh']}
 encoded=json.dumps(package,ensure_ascii=False,separators=(',',':')).encode()
 assert len(encoded)<262144, f'OCHD encoded package too large: {len(encoded)}'
 target=HERE/'files/lib/web_page.html';target.write_text(html,encoding='utf-8',newline='\n')
 print('OCHD package:',len(encoded),'bytes, limit 262144; HTML:',len(html.encode()))
 return html
if __name__=='__main__':build()
