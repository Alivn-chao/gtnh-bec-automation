(function(){'use strict';
var $=function(id){return document.getElementById(id);},app=window.BEC_APP,last=null,online=false,receivedAt=0,receiving=false,queue={},inflight=false,waiting=null,failed=false,group=1,switching=null,currentSave=null,actionPending=null,actionMessage=null,picking=null,pickerPending=false,pickerSerial=0,patternPending=false;
var order=['detect','nanites','gate','supply','convert','produce','finish'],titles={idle:'等待订单',detect:'读取配方',nanites:'蜂群检查',gate:'韦门确认',supply:'原液备料',convert:'凝聚物转换',produce:'配方运行',finish:'批次收尾',fault:'保护暂停'};
function list(v){return Array.isArray(v)?v:[];}
function esc(s){return String(s==null?'':s).replace(/[&<>"']/g,function(c){return({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c];});}
function time(n){n=Math.max(0,Number(n)||0);return n<60?n.toFixed(1)+'s':Math.floor(n/60)+'m '+(n%60).toFixed(1)+'s';}
function status(s,bad){$('save-status').textContent=s;$('save-status').classList.toggle('offline-alert',!!bad);}
function saving(){return inflight||!!waiting||!!Object.keys(queue).length;}
function showAction(message,bad){actionMessage={text:message,bad:!!bad};refreshActions();}
function refreshActions(){
 var patternBusy=last&&last.patterns&&last.patterns.status==='running';var running=last&&last.mode==='running',reason=!online?'OC 未连接，暂不能启动。':running?'自动化运行中。':patternBusy?'样板处理中，请在样板处理窗口等待完成或停止。':saving()?'正在保存草稿，请稍候。':!last.configured?'草稿已保存还不等于绑定已应用。请先点击「应用绑定」，校验通过后再启动。':'绑定已应用，可以启动；修改地址后需重新应用绑定。';
 var hint=$('action-feedback');hint.textContent=actionPending?({'apply_bindings':'正在校验并应用绑定…',start:'正在启动自动化…',pause:'正在暂停自动化…'}[actionPending]):actionMessage?actionMessage.text:reason;
 hint.classList.toggle('action-error',!!(actionMessage&&actionMessage.bad&&!actionPending));hint.setAttribute('role',actionMessage&&actionMessage.bad?'alert':'status');
 $('start-run').textContent=running?'运行中':'启动自动化';$('start-run').disabled=!online||running||!!actionPending||patternBusy||saving();$('start-run').title=reason;
 $('apply-config').disabled=!online||running||!!actionPending||patternBusy||saving();$('stop-run').disabled=!online||!running||!!actionPending;
}
function send(name,args){if(!online)return Promise.reject(Error('OC 未连接，未执行操作'));return OC.emit(name,args||{});}
function key(id,k){var m={'field':'g'+group+'.storage','generator':'g'+group+'.generator1','gate':'g'+group+'.gate','main-me':'mainInterface','workshop-me':'workshopInterface','sub-me':'g'+group+'.subInterface','fluid-transposer':'g'+group+'.transposer','nanite-transposer':'g'+group+'.bee_transposer','load-redstone':'g'+group+'.bee_loadRedstone','return-redstone':'g'+group+'.bee_returnRedstone'};
 if(id.indexOf('node-')===0)return 'n'+id.slice(5)+'.'+(k==='address'?'address':k==='redstone'?'redstone':k);
 if(k==='address')return m[id]||(id.indexOf('generator-')===0?'g'+group+'.generator'+id.slice(10):id.indexOf('bulk-transposer-')===0?'g'+group+'.bulk'+id.slice(16):null);
 return 'g'+group+'.'+(['bankSide','loadSide','returnSide','loadOutputSide','returnOutputSide'].indexOf(k)>=0?'bee_':'')+k;
}
function fieldKeys(m){return ['address'].concat(m.kind==='node'?['redstone','group','pauseSide','gate']:(m.sides||[]).map(function(f){return f[0];}));}
function toValues(draft){var out={};app.scene.modules.forEach(function(m){var v=draft.modules[m.id];if(!v||!m.role)return;fieldKeys(m).forEach(function(k){if(v[k]!=null){var name=key(m.id,k);if(name)out[name]=String(v[k]);}});});return out;}
function importValues(values){var draft={version:1,modules:{}};app.scene.modules.forEach(function(m){if(!m.role)return;var v={};fieldKeys(m).forEach(function(k){var value=values[key(m.id,k)];if(value!=null)v[k]=k==='address'||k==='redstone'||k==='gate'?value:Number(value);});draft.modules[m.id]=v;});receiving=true;app.importDraft(draft);receiving=false;}
function dirty(draft){if(receiving||switching||!last||last.mode==='running'||last.patterns&&last.patterns.status==='running')return;var values=toValues(draft);Object.keys(values).forEach(function(k){if(values[k]!==last.values[k]||(currentSave&&currentSave.key===k&&currentSave.value!==values[k])||(waiting&&waiting.key===k&&waiting.value!==values[k]))queue[k]=values[k];});status('正在保存到 OC…');pump();}
window.BEC_BINDING_DIRTY=dirty;
function pump(){if(inflight||waiting||failed||switching||!online||!last)return;var keys=Object.keys(queue);if(!keys.length){status('草稿已保存到 OC');return;}var k=keys[0],v=queue[k],revision=last.revision;delete queue[k];inflight=true;currentSave={key:k,value:v};status('正在保存到 OC…');send('save_field',{key:k,value:v,revision:revision}).then(function(){inflight=false;currentSave=null;waiting={revision:revision,key:k,value:v};if(last&&(last.revision!==revision||last.values[k]===v)){waiting=null;pump();}}).catch(function(e){inflight=false;currentSave=null;if(!Object.prototype.hasOwnProperty.call(queue,k))queue[k]=v;failed=true;status('保存未确认 · 点击重试',true);$('runtime-notice').textContent=e.message;});}
function syncModels(d){var scene=app.scene,base=scene.modules.find(function(m){return m.id==='generator';});if(!base)return;var count=Math.min(16,Math.max(4,d.generatorSlots||4));scene.modules=scene.modules.filter(function(m){return m.id.indexOf('generator-')!==0||Number(m.id.slice(10))<=count;});if(!scene.modules.some(function(m){return m.id===scene.selected;}))scene.selected='assembler';
 for(var j=2;j<=count;j++)if(!scene.modules.some(function(m){return m.id==='generator-'+j;})){var m=Object.assign({},base),dx=Math.floor((j-1)/4)*40,dz=((j-1)%4)*26;m.id='generator-'+j;m.title='纠缠器 '+String(j).padStart(2,'0');m.role='groups['+group+'].generators['+j+']';m.p=[base.p[0]+dx,base.p[1],base.p[2]+dz];m.center=[base.center[0]+dx,base.center[1],base.center[2]+dz];m.marker=[base.marker[0]+dx,base.marker[1],base.marker[2]+dz];scene.modules.push(m);}
 scene.modules.forEach(function(m){if(m.role)m.role=m.role.replace(/^groups\[\d+\]/,'groups['+group+']');if(m.kind==='generator')m.role='groups['+group+'].generators['+(m.id==='generator'?1:m.id.slice(10))+']';});scene.runtimeGroup=group;scene.runtimeValues=d.values||{};scene.request();}
function markMachines(){if(!last)return;app.scene.liveStates=last.machines||{};document.querySelectorAll('[data-label],[data-module]').forEach(function(el){el.dataset.live=(last.machines||{})[el.dataset.label||el.dataset.module]||'unknown';});}
var render=app.scene.onRender;app.scene.onRender=function(s){render(s);markMachines();pickerButtons();};
function flow(){if(!last)return;var age=online?Math.min(3,(Date.now()-receivedAt)/1000):0,active=last.mode==='running'&&last.phase!=='idle'&&last.phase!=='finish'&&!last.fault;var elapsed=(last.elapsed||0)+(active?age:0);$('flow-elapsed').textContent=time(elapsed);$('flow-current').textContent=titles[last.phase]||last.phase;$('flow-stage-time').textContent='当前步骤 '+time((last.phaseElapsed||0)+(active?age:0));
 $('flow-steps').innerHTML=order.map(function(p,i){var duration=Number((last.flow||{})[p]||0)+(active&&p===last.phase?age:0),current=last.phase===p,done=duration>0&&!current;return '<div class="flow-step '+(current?'current ':done?'done ':'')+(current&&last.fault?'fault':'')+'"><div class="index">'+(done?'✓ ':String(i+1).padStart(2,'0'))+'</div><strong>'+titles[p]+'</strong><time>'+((duration>0||current)?time(duration):'待执行')+'</time></div>';}).join('');
 $('node-status-list').innerHTML=(Array.isArray(last.nodes)?last.nodes:[]).map(function(n){return '<span class="node-chip '+(n.state==='crafting'?'active':'')+'">N'+String(n.slot).padStart(2,'0')+' · '+esc(n.state)+' · '+(n.workAllowed?'允许接单':'关闭接单')+'</span>';}).join('')||'<span class="node-chip">尚未绑定节点</span>';
 var machines=Object.keys(last.machines||{}).filter(function(id){return id==='field'||id==='gate'||id.indexOf('generator')===0;}).map(function(id){var active=last.machines[id]==='active';return '<span class="node-chip '+(active?'active':'')+'">'+(id==='field'?'约束场':id==='gate'?'韦门':id==='generator'?'纠缠器 1':'纠缠器 '+id.split('-')[1])+' · '+(active?'运行中':last.machines[id]==='unknown'?'不可读':'未运行')+'</span>';}).join('');$('node-status-list').innerHTML=machines+$('node-status-list').innerHTML;
 var events=(Array.isArray(last.timeline)?last.timeline:[]).map(function(e){return '+'+time(e.offset)+'  '+(titles[e.phase]||e.phase);});$('runtime-log').textContent=events.concat(Array.isArray(last.logs)?last.logs:[]).join('\n');
}
function data(d){var changed=group!==(d.group||1);last=d;online=d._online!==false;receivedAt=Date.now();group=d.group||1;if(switching===group)switching=null;if(waiting&&(waiting.revision!==d.revision||(d.values||{})[waiting.key]===waiting.value))waiting=null;
 syncModels(d);if(!switching&&!inflight&&!waiting&&!Object.keys(queue).length&&(changed||!/INPUT|TEXTAREA/.test(document.activeElement.tagName)))importValues(d.values||{});
 $('runtime-notice').textContent=(online?'': 'OC 离线，显示最后快照。')+(d.notice||'')+(d.disk&&d.disk.known?' · 磁盘剩余 '+(d.disk.free/1024).toFixed(0)+' KiB / 保留 '+(d.disk.reserve/1024).toFixed(0)+' KiB':' · 磁盘容量不可读');$('runtime-notice').classList.toggle('offline-alert',!online);
 document.body.classList.toggle('runtime-running',d.mode==='running');$('flow-panel').hidden=false;refreshActions();$('global-settings').disabled=d.mode==='running'||!!(d.patterns&&d.patterns.status==='running');document.body.classList.toggle('pattern-busy',!!(d.patterns&&d.patterns.status==='running'));renderPatterns();
 if(!online)status('OC 离线 · 未保存操作',true);else if(failed)status('保存未确认 · 点击重试',true);else if(!inflight&&!waiting&&!Object.keys(queue).length)status('OC 已连接 · 草稿已保存');
 if($('group-select').options.length!==d.groupCount){$('group-select').innerHTML=Array.from({length:d.groupCount||1},function(_,i){return '<option value="'+(i+1)+'">设备组 '+String(i+1).padStart(2,'0')+'</option>';}).join('');}$('group-select').value=group;if(window.BEC_REFRESH_SELECTS)window.BEC_REFRESH_SELECTS();
 markMachines();flow();pump();renderPicker(d.scan);
}
function pickerRole(id,field){if(field==='redstone'||id==='load-redstone'||id==='return-redstone')return 'redstone';if(field==='gate'||id==='gate')return 'gate';if(id.indexOf('node-')===0)return 'node';if(id==='field')return 'storage';if(id.indexOf('generator')===0)return 'generator';if(id==='main-me')return 'mainme';if(id==='sub-me')return 'subme';if(id==='workshop-me')return 'workshop';if(id==='nanite-transposer')return 'items';return 'fluid';}
function pickerButtons(){
 ['address','redstone','gate'].forEach(function(field){var input=$('field-'+field);if(!input||!input.parentNode)return;var existing=input.parentNode.querySelector('.pick-component');if(existing){existing.disabled=!online||last&&last.mode==='running';return;}var b=document.createElement('button');b.type='button';b.className='pick-component';b.textContent='从 OC 识别 / 选择';b.disabled=!online||last&&last.mode==='running';b.onclick=function(){openPicker(app.scene.selected,field);};input.parentNode.appendChild(b);});
}
function openPicker(id,field){
 if(pickerPending){showAction('请等待上一次扫描请求返回，再打开选择框。',true);return;}
 if(!online||last.mode==='running'){showAction('先连接 OC 并暂停自动化，再识别绑定。',true);return;}
 if(saving()){showAction('请先等待草稿保存完成。',true);return;}
 picking={id:id,field:field,key:key(id,field),role:pickerRole(id,field)};
 $('component-picker').showModal();var model=app.scene.modules.find(function(m){return m.id===id;});$('picker-title').textContent='识别 / '+(model?model.title:id)+' · '+({address:'设备地址',redstone:'暂停红石',gate:'独立韦门'}[field]||field);scanPicker();
}
function scanPicker(page){
 if(!picking||pickerPending)return;pickerPending=true;$('picker-status').textContent='读取 OC 组件中…';$('picker-results').innerHTML='';
 picking.token=++pickerSerial;var args={role:picking.role,token:picking.token};if(page!=null)args.page=page;
 send('scan_components',args).then(function(){pickerPending=false;}).catch(function(e){pickerPending=false;$('picker-status').textContent='扫描失败：'+e.message;});
}
function closePicker(){picking=null;$('component-picker').close();}
function bindingName(k){var n=k.match(/^n(\d+)\.(.+)$/),g=k.match(/^g(\d+)\.(.+)$/),labels={address:'节点组件',redstone:'暂停红石',gate:'韦门',storage:'约束场',subInterface:'原液子网ME接口',transposer:'供液转运器',bee_transposer:'蜂群转运器',bee_loadRedstone:'装入端口红石',bee_returnRedstone:'回收端口红石',mainInterface:'主网ME接口',workshopInterface:'样板工坊ME接口'};if(n)return '节点'+n[1]+' '+(labels[n[2]]||n[2]);if(g)return '组'+g[1]+' '+(labels[g[2]]||g[2].replace('generator','纠缠器').replace('bulk','高速供液口'));return labels[k]||k;}
function renderPicker(scan){
 pickerButtons();if(!picking||!scan||scan.role!==picking.role||scan.token!==picking.token||pickerPending)return;
 $('picker-status').textContent=scan.status==='scanning'?'扫描中，已检查 '+scan.checked+' 个组件…':scan.status==='failed'?scan.message:'找到 '+scan.total+' 项 · 第 '+(scan.page+1)+' 页'+(scan.baseline?' · 比上次减少 '+scan.removed+' 项':' · 首次扫描作为比较基准')+(scan.message?' · '+scan.message:'');
 $('picker-results').innerHTML=list(scan.rows).map(function(r){return '<button class="component-choice" type="button" data-address="'+esc(r.address)+'"><strong>'+(r.fresh?'新增 / 重新接入 · ':'')+esc(r.kind)+'</strong><code>'+esc(r.address)+'</code><small>'+esc(r.name||'')+(r.used?' · 已填写于 '+esc(r.used.split(', ').map(bindingName).join('、')):' · 尚未填写')+'</small></button>';}).join('')||(scan.status==='done'?'<p>没有匹配设备。当前 OC 组件网络看不到这种设备，检查适配器连接及 P2P。</p>':'');
 $('picker-results').querySelectorAll('button').forEach(function(b){b.onclick=function(){
  if(!picking||!online||last.mode==='running'||saving()){showAction('状态已改变，请等待保存完成并保持暂停后重新选择。',true);return;}
  var selected=picking;app.select(selected.id);var input=$('field-'+selected.field);if(!input){$('picker-status').textContent='当前字段不可用，请关闭后重试';return;}
  input.value=b.dataset.address;input.dispatchEvent(new Event('input',{bubbles:true}));closePicker();showAction('已选择 OC 实际地址，正在保存草稿；方向和节点配对仍需按实物确认。',false);
 };});
 $('picker-prev').disabled=scan.status!=='done'||scan.page===0;$('picker-next').disabled=scan.status!=='done'||(scan.page+1)*6>=scan.total;
 $('picker-prev').onclick=function(){scanPicker(scan.page-1);};$('picker-next').onclick=function(){scanPicker(scan.page+1);};
}
function bindingIssues(){
 var v=last&&last.values||{},p='g'+group+'.',issues=[],uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 function value(k){return String(v[k]||'').trim();}
 function add(label,id,field){issues.push({label:label,id:id,field:field||'address'});}
 function address(k,label,id,required,field){var x=value(k);if(!x&&required)add(label+'：未填写',id,field);else if(x&&!uuid.test(x))add(label+'：地址需为完整 UUID',id,field);}
 address('mainInterface','主网供液 ME 接口','main-me',true);
 address(p+'storage','约束场','field',true);address(p+'subInterface','原液子网 ME 接口','sub-me',true);address(p+'transposer','供液转运器','fluid-transposer',true);
 var generators=0;for(var j=1;j<=Math.max(4,last.generatorSlots||4);j++){var k=p+'generator'+j;if(value(k))generators++;address(k,'纠缠器 '+j,j===1?'generator':'generator-'+j,false);}if(!generators)add('至少填写一台纠缠器','generator');
 address(p+'gate','公共韦门','gate',false);address('workshopInterface','样板工坊 ME 接口','workshop-me',false);
 for(var j=1;j<=10;j++)address(p+'bulk'+j,'高速供液口 '+j,'bulk-transposer-'+j,false);
 var bees=[['transposer','蜂群转运器','nanite-transposer'],['loadRedstone','装入端口红石','load-redstone'],['returnRedstone','回收端口红石','return-redstone']],beeOn=bees.some(function(b){return !!value(p+'bee_'+b[0]);});
 bees.forEach(function(b){address(p+'bee_'+b[0],b[1],b[2],beeOn);});
 if(v[p+'mainSide']===v[p+'subSide'])add('供液主网侧与子网侧不能相同','fluid-transposer');
 if(beeOn){var sides=['bankSide','loadSide','returnSide'].map(function(k){return v[p+'bee_'+k];});if(sides.some(function(x,i){return sides.indexOf(x)!==i;}))add('蜂群箱子、装入端口、回收端口必须是三个不同方向','nanite-transposer');}
 var total=0,localCount=0;for(var i=1;i<=16;i++){var n='n'+i+'.';if(!value(n+'address')&&!value(n+'redstone'))continue;total++;if(Number(v[n+'group'])!==group)continue;localCount++;
 address(n+'address','节点 '+i+' 组件','node-'+i,true);address(n+'redstone','节点 '+i+' 暂停红石','node-'+i,true,'redstone');address(n+'gate','节点 '+i+' 独立韦门','node-'+i,false,'gate');
 if(!value(n+'gate')&&!value(p+'gate'))add('节点 '+i+' 需要韦门：填写独立韦门或本组公共韦门','node-'+i,'gate');}
 if(!total)add('至少填写一组传送节点和暂停红石，空位会自动跳过','node-1');else if(!localCount)add('当前设备组还没有分配传送节点','node-1','group');
 if(!value('recipeDirectory'))add('配方目录：未填写','settings');return issues;
}
function showIssues(issues){
 $('binding-issues-list').innerHTML=issues.map(function(x){return '<button type="button" data-issue-module="'+esc(x.id)+'" data-issue-field="'+esc(x.field)+'">'+esc(x.label)+' → 去填写</button>';}).join('');
 $('binding-issues-list').querySelectorAll('button').forEach(function(b){b.onclick=function(){$('binding-issues').close();if(b.dataset.issueModule==='settings'){settings();return;}document.body.classList.toggle('flow-full',false);app.select(b.dataset.issueModule);var field=$('field-'+b.dataset.issueField);if(field)field.focus();};});
 $('binding-issues').showModal();showAction('当前设备组有 '+issues.length+' 项绑定需要补充或修正，点击清单可跳转。',true);
}
function action(name){
 if(actionPending)return;
 if(saving()){showAction('请先等待草稿保存完成。',true);return;}
 if(name==='start'&&last&&!last.configured){showAction('尚未应用绑定：请先点击「应用绑定」。如果校验失败，这里会显示具体原因。',true);return;}
 if(name==='apply_bindings'){var issues=bindingIssues();if(issues.length){showIssues(issues);return;}}
 actionMessage=null;actionPending=name;refreshActions();
 send(name,{revision:last&&last.revision}).then(function(r){actionPending=null;showAction(r.message||'请求已确认，等待 OC 状态更新。',false);}).catch(function(e){actionPending=null;showAction((name==='apply_bindings'?'应用绑定失败：':name==='start'?'启动失败：':'暂停失败：')+e.message,true);});
}
function renderPatterns(){
 var p=last&&last.patterns,busy=p&&p.status==='running';$('patterns-status').textContent=p?({running:'进行中',done:'已完成',failed:'处理失败',stopped:'已停止'}[p.status]||p.status)+' · 槽位 '+p.slot+' / 9 · '+p.message:!last||!last.configured?'请先绑定并应用独立的样板工坊 ME 接口。':'先预览工坊接口内的样板，再处理原样板的副本。';
 $('patterns-log').textContent=p?(list(p.rows).join('\n')+'\n'+list(p.logs).join('\n')):'';['patterns-preview','patterns-run'].forEach(function(id){$(id).disabled=!online||!last||last.mode==='running'||!last.configured||busy||patternPending||saving();});$('patterns-stop').disabled=!online||!busy||patternPending;
 $('patterns-open').textContent=busy?'样板处理中':'样板处理';
 $('patterns-target').textContent=last?'工坊接口：'+(last.values.workshopInterface||'未绑定')+' · 配方目录：'+(last.values.recipeDirectory||'未设置'):'';
}
function patternAction(mode){
 if(patternPending)return;if(mode!=='stop'&&saving()){$('patterns-status').textContent='请先等待草稿保存完成。';return;}
 patternPending=true;renderPatterns();$('patterns-status').textContent=mode==='stop'?'正在请求停止…':'正在提交样板操作…';
 send('patterns',{mode:mode,revision:last&&last.revision}).then(function(r){patternPending=false;renderPatterns();$('patterns-status').textContent=r.message||'请求已确认，等待处理状态。';}).catch(function(e){patternPending=false;renderPatterns();$('patterns-status').textContent='未执行：'+e.message;showAction('样板操作失败：'+e.message,true);});
}
function settings(){if(!last)return;var specs=[['recipeDirectory','配方目录'],['cacheTarget','库存参考目标']];for(var i=1;i<=Math.max(4,last.generatorSlots||4);i++)specs.push(['g'+group+'.generator'+i,'纠缠器 '+i+'（多余可空）']);$('extra-fields').innerHTML=specs.map(function(f){return '<label>'+f[1]+'<input data-config="'+f[0]+'" value="'+esc(last.values[f[0]]||'')+'" maxlength="160" spellcheck="false"></label>';}).join('');$('extra-fields').querySelectorAll('input').forEach(function(input){input.onchange=function(){queue[input.dataset.config]=input.value;pump();};});$('runtime-settings').showModal();}
document.querySelector('.top-actions').innerHTML='<span id="save-status" class="save-status">等待 OC 连接</span><button class="button quiet" id="patterns-open">样板处理</button><button class="button quiet" id="global-settings">公共设置</button><button class="button quiet" id="apply-config">应用绑定</button><button class="button primary run-button" id="start-run">启动自动化</button><button class="button quiet stop-button" id="stop-run">暂停</button>';
var feedback=document.createElement('div');feedback.id='action-feedback';feedback.className='action-feedback';feedback.textContent='等待 OC 连接…';feedback.setAttribute('aria-live','polite');document.body.appendChild(feedback);
var tabs=document.createElement('nav');tabs.className='runtime-tabs';tabs.innerHTML='<button class="active" data-tab="structure">结构 / 绑定</button><button data-tab="flow">运行流程</button>';document.querySelector('.topbar').insertBefore(tabs,document.querySelector('.top-actions'));
var flowPanel=document.createElement('section');flowPanel.className='flow-panel';flowPanel.id='flow-panel';flowPanel.innerHTML='<div class="flow-title"><div><h2>自动化流程 <span id="flow-current">等待 OC</span></h2><p id="flow-stage-time">当前步骤 —</p></div><div><div class="elapsed" id="flow-elapsed">0.0s</div><small>当前 / 最近批次总耗时</small></div></div><div class="flow-path" id="flow-steps"></div><div class="flow-bottom"><div><h4>TRANSFER NODES / 接单控制</h4><div class="node-list" id="node-status-list"></div><div class="runtime-legend"><b>绿色：机器回读运行中</b> · <em>金色：当前步骤使用的外设</em><br>外设阶段占用不等同于硬件正在搬运</div></div><div><h4>EXECUTION / 阶段时间线</h4><div id="runtime-log" class="runtime-log" style="white-space:pre-wrap"></div></div></div>';
document.querySelector('.main').appendChild(flowPanel);var notice=document.createElement('div');notice.id='runtime-notice';notice.className='runtime-notice';notice.textContent='等待 OC 数据，网页预览不控制机器。';document.querySelector('.main').appendChild(notice);
var patternsDialog=document.createElement('dialog');patternsDialog.id='patterns-dialog';patternsDialog.className='runtime-settings';patternsDialog.innerHTML='<h2>样板处理</h2><p>将原加工样板的副本放入独立工坊 ME 接口。预览只读；处理一次会去除凝聚物输入并保存配方需求。请先暂停生产和纠缠器。</p><p id="patterns-target"></p><div id="patterns-status" role="status" aria-live="polite"></div><pre id="patterns-log"></pre><footer><button id="patterns-preview" class="button">只读预览</button><button id="patterns-run" class="button primary">处理一次</button><button id="patterns-stop" class="button">停止处理</button><button id="patterns-close" class="button">关闭</button></footer>';document.body.appendChild(patternsDialog);$('patterns-open').onclick=function(){$('patterns-dialog').showModal();renderPatterns();};$('patterns-close').onclick=function(){$('patterns-dialog').close();};$('patterns-preview').onclick=function(){patternAction('preview');};$('patterns-run').onclick=function(){patternAction('run');};$('patterns-stop').onclick=function(){patternAction('stop');};
var pickerDialog=document.createElement('dialog');pickerDialog.id='component-picker';pickerDialog.className='runtime-settings';pickerDialog.innerHTML='<h2 id="picker-title">从 OC 选择设备</h2><p>只读取组件。点击候选地址填入草稿，不启动机器。</p><p>同类机器位置识别：暂停自动化后，仅断开目标适配器的 OC 信号分支，扫描一次；接回原线再「重新扫描」。新增/重新接入项就是候选。不要拆机器或适配器，也不要断整条共用主线。若出现多项新增，逐项确认，不按 UUID 排列猜位置。</p><div id="picker-status"></div><div id="picker-results"></div><footer><button id="picker-prev" class="button">上一页</button><button id="picker-next" class="button">下一页</button><button id="picker-refresh" class="button">重新扫描</button><button id="picker-close" class="button primary">关闭</button></footer>';document.body.appendChild(pickerDialog);$('picker-refresh').onclick=function(){scanPicker();};$('picker-close').onclick=closePicker;
var issuesDialog=document.createElement('dialog');issuesDialog.id='binding-issues';issuesDialog.className='runtime-settings binding-issues';issuesDialog.innerHTML='<h2>绑定检查 / 当前设备组</h2><p>点击下列项目跳转填写。这里只检查填写内容；通过后还会由 OC 校验设备是否在线、方法和机器状态。</p><div id="binding-issues-list"></div><p>空传送节点会跳过。额外纠缠器、高速供液口、样板工坊可留空；自动换蜂的三项地址须全部填写或全部留空。每个节点须有独立韦门或使用本组公共韦门。</p><footer><button id="close-issues" class="button primary">返回修改</button></footer>';document.body.appendChild(issuesDialog);$('close-issues').onclick=function(){$('binding-issues').close();};
var dialog=document.createElement('dialog');dialog.id='runtime-settings';dialog.className='runtime-settings';dialog.innerHTML='<h2>公共配置</h2><p>填写后自动暂存。应用绑定通过设备校验后，才能启动。</p><label>当前模型对应 <select id="group-select"></select></label><div id="extra-fields"></div><footer><button id="close-settings" class="button primary">完成</button></footer>';document.body.appendChild(dialog);
document.querySelectorAll('[data-tab]').forEach(function(b){b.onclick=function(){document.querySelectorAll('[data-tab]').forEach(function(x){x.classList.toggle('active',x===b);});document.body.classList.toggle('flow-full',b.dataset.tab==='flow');app.scene.request();};});

 document.querySelector('.inspector-bottom p').textContent='草稿由 OC 自动保存，支持 Ctrl+V。应用绑定前不控制机器。';$('model-callout').querySelector('p').innerHTML='点击机器填写地址，自动暂存到 OC。<br>拖动旋转 · 滚轮缩放 · 右键平移';document.querySelector('.pill').textContent='V2 / OCHD';
document.querySelector('.stage-title').innerHTML='<span class="live-dot"></span>结构与机器状态<span class="stage-sub">/ 实际回读 + 阶段标记</span>';
$('save-status').onclick=function(){if(failed){failed=false;pump();}};$('apply-config').onclick=function(){action('apply_bindings');};$('start-run').onclick=function(){action('start');};$('stop-run').onclick=function(){action('pause');};$('global-settings').onclick=settings;$('close-settings').onclick=function(){$('runtime-settings').close();};$('group-select').onchange=function(){if(inflight||waiting||Object.keys(queue).length){this.value=group;return;};switching=Number(this.value);send('select_group',{group:switching}).then(function(){$('runtime-settings').close();}).catch(function(e){switching=null;$('runtime-notice').textContent=e.message;});};
 window.BEC_CONTROL={receive:data,values:toValues,openPicker:openPicker,issues:bindingIssues,queue:function(){return queue;}};
if(window.OC&&OC.onData)OC.onData(data);else{$('runtime-notice').textContent='浏览器预览：未连接 OC，所有机器操作禁用。';$('start-run').disabled=$('stop-run').disabled=$('apply-config').disabled=true;}
setInterval(function(){flow();if(last&&Date.now()-receivedAt>7000){online=false;status('OC 数据已过期',true);refreshActions();}},250);
})();
