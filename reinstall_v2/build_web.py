"""Bundle the existing real-block studio into one offline OCHD HTML resource."""
from pathlib import Path
from collections import Counter
import json,sys,re
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent/'work/build_tools'))
from rjsmin import jsmin
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
 def compact(name):
  return jsmin((HERE/'web'/name).read_text(encoding='utf-8'))
 def script(m):
  source=m[2]
  # Losslessly share blank structure rows; geometry and source data stay exact.
  if source.startswith('window.BEC_DATA = '):
   counts=Counter(re.findall(r'" {8,}"',source))
   rows=[s for s,n in counts.items()if n>2]
   indices={s:'r['+str(i)+']'for i,s in enumerate(rows)}
   source='(function(){var r=['+','.join(rows)+'];'+re.sub(r'" {8,}"',lambda x:indices.get(x[0],x[0]),source)+'})();'
  return m[1]+jsmin(source)+m[3]
 html=re.sub(r'(<script>)(.*?)(</script>)',script,html,flags=re.S)
 def css(m):
  text=re.sub(r'\s*([{}:;,])\s*',r'\1',m[2])
  text=re.sub(r'#([0-9a-f])\1([0-9a-f])\2([0-9a-f])\3(?![0-9a-f])',r'#\1\2\3',text,flags=re.I)
  text=re.sub(r'(?<![\w.-])0\.(\d+)',r'.\1',text)
  return m[1]+text+m[3]
 html=re.sub(r'(<style>)(.*?)(</style>)',css,html,flags=re.S)
 html=html.replace('</body>','<script>'+compact('input-controls.js')+'</script><script>'+compact('control.js')+'</script></body>',1)
 html=html.replace('BEC 结构配置台 · 交互原型','BEC V2 · 结构绑定与自动化流程')
 html=re.sub(r'>\s+<','><',html)
 package={'id':'bec-v2-studio','title':'BEC V2 结构绑定与运行','entry':'index.html','files':{'index.html':html},'events':['save_field','apply_bindings','start','pause','select_group','refresh','scan_components','patterns','cache']}
 encoded=json.dumps(package,ensure_ascii=False,separators=(',',':')).encode()
 assert len(encoded)<262144, f'OCHD encoded package too large: {len(encoded)}'
 target=HERE/'files/lib/web_page.html';target.write_text(html,encoding='utf-8',newline='\n')
 print('OCHD package:',len(encoded),'bytes, limit 262144; HTML:',len(html.encode()))
 return html
if __name__=='__main__':build()
