// Exercise the actual page controller with deferred OC acknowledgements.
const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../web/control.js'),'utf8');
const original={window:{}},packed={window:{}};
for(const [file,context]of [['../web/structure-base.html',original],['../files/lib/web_page.html',packed]]){
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,file),'utf8').match(/<script>([\s\S]*?)<\/script>/)[1],context);
}
assert.equal(JSON.stringify(original.window.BEC_DATA),JSON.stringify(packed.window.BEC_DATA),'packed geometry must preserve all structure rows and textures');
function fixture(){
 const elements=new Map(),sent=[];
 function el(id){if(!elements.has(id))elements.set(id,{textContent:'',innerHTML:'',disabled:false,dataset:{},options:[],value:'',classList:{toggle(){}},querySelector:()=>el('child'),querySelectorAll:()=>[],appendChild(){},insertBefore(){},addEventListener(){},setAttribute(){},showModal(){},close(){}});return elements.get(id);}
 const imports=[],scene={modules:[{id:'node-1',kind:'node',role:'node'},{id:'generator',kind:'generator',role:'generator',p:[164,6,6],center:[180,15,15],marker:[164,15,15]}],onRender(){},request(){}},app={scene,importDraft(d){imports.push(d);},getDraft(){return{};}};
 const context={window:{BEC_APP:app},document:{getElementById:el,querySelector:s=>s==='#cache-rows input:focus'?null:el(s),querySelectorAll:()=>[],createElement:el,body:el('body'),activeElement:{tagName:'INPUT'}},OC:{emit(name,args){return new Promise((resolve,reject)=>sent.push({name,args,resolve,reject}));},onData(){}},setInterval(){},Date,Promise,console};
 context.window.OC=context.OC;vm.createContext(context);vm.runInContext(source,context);
 const snapshot=(revision,values={},extra={})=>context.window.BEC_CONTROL.receive(Object.assign({revision,values:Object.assign({'n1.address':'','n1.redstone':'','n1.group':'1','n1.pauseSide':'1'},values),group:1,groupCount:1,mode:'binding',configured:true},extra));
 const edit=value=>context.window.BEC_BINDING_DIRTY({modules:{'node-1':{address:value}}});
 return{context,sent,snapshot,edit,el,scene,imports,queue:()=>context.window.BEC_CONTROL.queue()};
}
const flush=()=>new Promise(resolve=>setImmediate(resolve));
(async()=>{
 let f=fixture();f.snapshot('1');f.edit('old');f.edit('new');f.sent[0].reject(Error('ack timeout'));await flush();
 assert.equal(f.queue()['n1.address'],'new','failed older request must not replace newer input');
 f.el('save-status').onclick();assert.equal(f.sent[1].args.value,'new');

 f=fixture();f.snapshot('1');f.edit('partial');f.edit('');f.sent[0].resolve({});await flush();
 f.snapshot('2',{'n1.address':'partial'});assert.equal(f.sent[1].args.value,'','reverting to saved value during a pending save must be preserved');

 f=fixture();f.snapshot('1');f.edit('same');f.snapshot('1',{'n1.address':'same'});f.sent[0].resolve({});await flush();
 f.edit('next');assert.equal(f.sent.length,2,'identical revision acknowledged save must not deadlock');

 f=fixture();f.snapshot('1');f.edit('a');f.snapshot('2',{'n1.address':'a'});f.sent[0].resolve({});await flush();
 f.edit('b');assert.equal(f.sent[1].args.revision,'2','snapshot arriving before ack must advance revision');

 f=fixture();f.snapshot('1');f.edit('a');f.sent[0].reject(Error('conflict'));await flush();f.snapshot('2');
 assert.match(f.el('save-status').textContent,/未确认/,'new snapshots must not hide failure');
 assert.equal(f.sent.length,1,'failed saves require explicit retry');
 f=fixture();f.snapshot('1',{}, {generatorSlots:6});
 assert.equal(f.scene.modules.filter(m=>m.kind==='generator').length,6);
 f.context.window.BEC_BINDING_DIRTY({modules:{'generator-6':{address:'sixth'}}});
 assert.equal(f.sent[0].args.key,'g1.generator6');

 f=fixture();f.snapshot('1');f.snapshot('2',{'g2.generator2':'second-group'},{group:2,groupCount:2});
 assert.equal(f.imports.at(-1).modules['generator-2'].address,'second-group','group switch replaces focused stale inspector');
 f.context.window.BEC_BINDING_DIRTY({modules:{'generator-2':{address:'changed'}}});
 assert.equal(f.sent[0].args.key,'g2.generator2');
 f=fixture();f.snapshot('1',{}, {generatorSlots:6});f.snapshot('2',{}, {group:2,groupCount:2,generatorSlots:4});
 assert.equal(f.scene.modules.filter(m=>m.kind==='generator').length,4,'another group must not expose unsupported leftover fields');
 f=fixture();f.scene.modules.push({id:'bulk-transposer-10',kind:'peripheral',role:'bulk'});f.snapshot('1');
 f.context.window.BEC_BINDING_DIRTY({modules:{'bulk-transposer-10':{address:'tenth'}}});assert.equal(f.sent[0].args.key,'g1.bulk10');
 const valid={'mainInterface':'11111111-1111-1111-1111-111111111111','recipeDirectory':'/home/bec_v2/recipes','g1.storage':'22222222-2222-2222-2222-222222222222','g1.subInterface':'33333333-3333-3333-3333-333333333333','g1.transposer':'44444444-4444-4444-4444-444444444444','g1.generator1':'55555555-5555-5555-5555-555555555555','g1.mainSide':'4','g1.subSide':'5','g1.gate':'66666666-6666-6666-6666-666666666666','n1.address':'77777777-7777-7777-7777-777777777777','n1.redstone':'88888888-8888-8888-8888-888888888888'};
 f=fixture();f.snapshot('1',valid, {configured:false});
 assert.equal(f.el('start-run').disabled,false);
 f.el('start-run').onclick();assert.equal(f.sent.length,0);assert.match(f.el('action-feedback').textContent,/尚未应用绑定/);
 f.el('apply-config').onclick();assert.equal(f.sent[0].name,'apply_bindings');assert.equal(f.el('apply-config').disabled,true);
 f.el('apply-config').onclick();assert.equal(f.sent.length,1);
 f.sent[0].reject(Error('纠缠器地址无效'));await flush();assert.match(f.el('action-feedback').textContent,/应用绑定失败.*纠缠器地址无效/);
 f.snapshot('2',valid, {configured:false});assert.match(f.el('action-feedback').textContent,/纠缠器地址无效/);
 f.el('apply-config').onclick();f.sent[1].resolve({message:'绑定校验通过'});await flush();f.snapshot('3',valid);
 f.el('start-run').onclick();assert.equal(f.sent[2].name,'start');f.sent[2].reject(Error('节点仍在工作'));await flush();assert.match(f.el('action-feedback').textContent,/启动失败.*节点仍在工作/);
 f=fixture();f.context.document.activeElement.tagName='BODY';f.snapshot('1',{'n1.gate':'12345678-1234-1234-1234-123456789abc'});assert.equal(f.imports.at(-1).modules['node-1'].gate,'12345678-1234-1234-1234-123456789abc');
 f=fixture();f.snapshot('1');f.el('apply-config').onclick();assert.equal(f.sent.length,0);assert.match(f.el('binding-issues-list').innerHTML,/主网供液.*未填写/);assert.match(f.el('binding-issues-list').innerHTML,/至少填写一组传送节点/);
 f.snapshot('2',valid);assert.equal(f.context.window.BEC_CONTROL.issues().length,0,'blank optional ports and nodes are allowed');
 f.snapshot('3',Object.assign({},valid,{'g1.gate':'','n1.gate':'99999999-9999-9999-9999-999999999999'}));assert.equal(f.context.window.BEC_CONTROL.issues().length,0,'independent node gate replaces group gate');
 f.snapshot('4',Object.assign({},valid,{'g1.bee_transposer':'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','g1.bee_bankSide':'0','g1.bee_loadSide':'3','g1.bee_returnSide':'2'}));assert.equal(f.context.window.BEC_CONTROL.issues().filter(x=>/端口红石/.test(x.label)).length,2);
 f=fixture();f.snapshot('1',valid);f.context.window.BEC_CONTROL.openPicker('node-1','redstone');assert.equal(f.sent[0].name,'scan_components');assert.equal(f.sent[0].args.role,'redstone');f.sent[0].resolve({});await flush();
 var scan={role:'redstone',token:1,status:'done',page:0,total:1,checked:4,rows:[{address:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',kind:'redstone',fresh:true,used:'n2.redstone'}]};
 f.snapshot('2',valid,{scan});assert.match(f.el('picker-results').innerHTML,/新增.*redstone/);assert.match(f.el('picker-results').innerHTML,/节点2 暂停红石/);
 f.el('picker-refresh').onclick();assert.equal(f.sent[1].args.token,2);f.sent[1].resolve({});await flush();f.snapshot('3',valid,{scan});assert.equal(f.el('picker-results').innerHTML,'','stale scan cannot be offered for a new request');
 f=fixture();f.snapshot('1',valid);f.el('patterns-open').onclick();f.el('patterns-preview').onclick();assert.equal(f.sent[0].name,'patterns');assert.equal(f.sent[0].args.mode,'preview');assert.equal(f.sent[0].args.revision,'1');
 f.el('patterns-run').onclick();assert.equal(f.sent.length,1,'pending pattern request is not duplicated');f.sent[0].reject(Error('工坊未绑定'));await flush();assert.match(f.el('patterns-status').textContent,/工坊未绑定/);assert.match(f.el('action-feedback').textContent,/样板操作失败/);
 f.snapshot('2',valid,{patterns:{status:'running',mode:'run',slot:2,message:'处理中',rows:['槽1完成'],logs:['处理中']}});assert.equal(f.el('start-run').disabled,true);assert.equal(f.el('apply-config').disabled,true);assert.equal(f.el('patterns-run').disabled,true);assert.equal(f.el('patterns-stop').disabled,false);
 f.el('patterns-stop').onclick();assert.equal(f.sent[1].args.mode,'stop');f.sent[1].resolve({message:'正在停止'});await flush();
 f.snapshot('3',valid,{patterns:{status:'failed',mode:'run',slot:2,message:'保留现场',rows:['槽1完成'],logs:['还原失败']}});assert.match(f.el('patterns-status').textContent,/处理失败.*保留现场/);assert.match(f.el('patterns-log').textContent,/槽1完成/);
 f.snapshot('4',valid,{patterns:{status:'running',mode:'preview',slot:0,message:'准备中',rows:{},logs:{}}});assert.match(f.el('patterns-status').textContent,/准备中/);
 f=fixture();var cache={revision:'cache-1',enabled:false,target:144000,busy:false,blocked:false,message:'待补',logs:{},page:0,total:0,rows:{}};f.snapshot('1',valid,{cache:cache});
 f.el('cache-default').value='200000';f.el('cache-save-default').onclick();assert.equal(f.sent[0].name,'cache');assert.equal(f.sent[0].args.value,'200000');
 f.el('cache-save-default').onclick();assert.equal(f.sent.length,1,'pending cache save must not send twice');
 f.sent[0].resolve({message:'已保存'});await flush();assert.equal(f.el('cache-default').value,'200000','old snapshot after ack must not erase edited target');
 cache=Object.assign({},cache,{revision:'cache-2',target:200000});f.snapshot('2',valid,{cache:cache});assert.equal(f.el('cache-default').value,200000);
 f.el('cache-enable').onclick();assert.equal(f.sent[1].args.mode,'enable');f.sent[1].reject(Error('设备未绑定'));await flush();assert.match(f.el('cache-feedback').textContent,/未执行.*设备未绑定/);
 f.el('cache-disable').onclick();assert.equal(f.sent[2].args.mode,'disable');f.sent[2].resolve({message:'正在收尾'});await flush();assert.match(f.el('cache-feedback').textContent,/收尾/);
 f=fixture();f.snapshot('1',valid,{cache});f.el('cache-enable').onclick();var req=f.sent[0];
 req.resolve({message:'BEC_REQUEST_ACCEPTED'});await flush();
 assert.equal(f.el('cache-enable').disabled,true,'receipt alone is not completion');
 f.snapshot('2',valid,{cache,transportBusy:true,reply:{token:'other',ok:true,message:'wrong request'}});await flush();
 assert.equal(f.el('cache-enable').disabled,true,'unrelated result must not release action');
 f.snapshot('3',valid,{cache,reply:{token:req.args._token,name:'cache',ok:true,message:'实际启用完成'}});await flush();
 assert.match(f.el('cache-feedback').textContent,/实际启用完成/);
 assert.equal(f.el('cache-enable').disabled,false);
 f.el('cache-disable').onclick();var next=f.sent[1];next.resolve({message:'BEC_REQUEST_ACCEPTED'});await flush();
 f.snapshot('4',valid,{cache,reply:{token:req.args._token,ok:true,message:'stale'}});await flush();
 assert.equal(f.el('cache-disable').disabled,true,'old result cannot finish newer request');
 f.snapshot('5',valid,{cache,_online:false});await flush();
 assert.match(f.el('cache-feedback').textContent,/结果待核对/);assert.equal(f.el('start-run').textContent,'状态待确认');
 f.snapshot('6',valid,{cache,reply:{token:next.args._token,name:'cache',ok:false,message:'设备回读失败'}});await flush();
 assert.match(f.el('cache-feedback').textContent,/设备回读失败/,'late result replaces unknown state');
 assert.equal(f.sent.length,2,'disconnect must never replay machine action');
 f=fixture();f.snapshot('1',valid);f.el('start-run').onclick();req=f.sent[0];req.resolve({message:'BEC_REQUEST_ACCEPTED'});await flush();
 assert.equal(f.el('start-run').disabled,true);
 f.snapshot('2',valid,{mode:'running',reply:{token:req.args._token,ok:true,message:'启动已完成'}});await flush();
 assert.equal(f.el('start-run').textContent,'运行中');assert.match(f.el('action-feedback').textContent,/启动已完成/);
 f=fixture();cache={revision:'c1',enabled:false,target:4000000,busy:false,message:'idle',logs:[],page:0,total:16,rows:[{name:'first',label:'第一页',stock:1,target:4000000}]};
 f.snapshot('1',valid,{cache});f.el('cache-next').onclick();assert.equal(f.sent[0].args.mode,'page');
 f.snapshot('2',valid,{cache:Object.assign({},cache,{page:1,rows:[{name:'second',label:'第二页',stock:2,target:4000000}]})});f.sent[0].resolve({});await flush();
 f.el('cache-save-default').onclick();const save=f.sent[1];assert.equal(f.el('cache-prev').disabled,false,'save must not lock previous page');
 f.el('cache-prev').onclick();assert.equal(f.el('cache-page').textContent,'1 / 2');assert.match(f.el('cache-rows').innerHTML,/第一页/);assert.equal(f.sent[2].args.mode,'page');
 f.sent[2].resolve({message:'page'});await flush();assert.match(f.el('cache-feedback').textContent,/正在提交/,'page ack must not finish pending save');assert.equal(f.el('cache-save-default').disabled,true);
 f.snapshot('3',valid,{cache:Object.assign({},cache,{page:1,rows:[{name:'second',label:'迟到第二页',stock:3,target:4000000}]})});assert.equal(f.el('cache-page').textContent,'1 / 2','late page response cannot change user selection');
 save.resolve({message:'保存完成'});await flush();assert.match(f.el('cache-feedback').textContent,/保存完成/);
 f.el('cache-next').onclick();assert.match(f.el('cache-rows').innerHTML,/迟到第二页/,'loaded page opens immediately');
 f.snapshot('4',valid,{cache,_online:false});f.el('cache-prev').onclick();assert.match(f.el('cache-rows').innerHTML,/第一页/,'offline browsing of loaded pages stays available');
 f=fixture();f.snapshot('1',valid,{cache});f.el('cache-default').value='987654';f.el('cache-default').oninput.call(f.el('cache-default'));f.snapshot('2',valid,{cache:Object.assign({},cache,{target:555})});assert.equal(f.el('cache-default').value,'987654','unsubmitted default edit survives snapshots');
 f=fixture();f.snapshot('1',valid);f.edit('pending-address');f.el('group-select').value=2;f.el('group-select').onchange.call(f.el('group-select'));assert.equal(f.sent.length,1);assert.match(f.el('action-feedback').textContent,/地址还在保存/);
 f=fixture();cache={revision:'all-1',enabled:true,target:4000000,busy:true,message:'配方36',logs:[],page:0,total:16,rows:[],catalogue:Array.from({length:16},(_,i)=>['fluid'+i,'流体'+i,i,i===8?0:false])};
 f.snapshot('1',valid,{cache});f.el('cache-next').onclick();assert.equal(f.sent.length,0,'first visit uses downloaded catalogue without OC request');assert.match(f.el('cache-rows').innerHTML,/流体8/);assert.equal(f.el('cache-page').textContent,'2 / 2');
 f.el('cache-default').value='222';f.el('cache-save-default').onclick();assert.equal(f.sent[0].args.group,1);f.el('cache-prev').onclick();f.el('cache-next').onclick();assert.equal(f.sent.length,1,'page browsing stays local during pending write');assert.match(f.el('cache-feedback').textContent,/正在提交/);
 f.sent[0].resolve({message:'BEC_REQUEST_ACCEPTED'});await flush();assert.equal(f.el('cache-save-default').disabled,true);
 f.snapshot('2',valid,{cache,reply:{token:f.sent[0].args._token,ok:true,message:'已保存回读'}});await flush();assert.match(f.el('cache-feedback').textContent,/已保存回读/);
 f.snapshot('3',valid,{cache,_online:false});f.el('cache-prev').onclick();assert.match(f.el('cache-rows').innerHTML,/流体0/);assert.equal(f.sent.length,1);
 console.log('Page save races, feedback, picker, patterns, cache and browsing: 41 scenarios passed');
})().catch(e=>{console.error(e);process.exitCode=1;});
