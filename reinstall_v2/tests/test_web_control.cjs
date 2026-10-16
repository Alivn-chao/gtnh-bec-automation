// Exercise the actual page controller with deferred OC acknowledgements.
const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../web/control.js'),'utf8');
function fixture(){
 const elements=new Map(),sent=[];
 function el(id){if(!elements.has(id))elements.set(id,{textContent:'',innerHTML:'',disabled:false,dataset:{},options:[],value:'',classList:{toggle(){}},querySelector:()=>el('child'),querySelectorAll:()=>[],appendChild(){},insertBefore(){},addEventListener(){},setAttribute(){},showModal(){},close(){}});return elements.get(id);}
 const imports=[],scene={modules:[{id:'node-1',kind:'node',role:'node'},{id:'generator',kind:'generator',role:'generator',p:[164,6,6],center:[180,15,15],marker:[164,15,15]}],onRender(){},request(){}},app={scene,importDraft(d){imports.push(d);},getDraft(){return{};}};
 const context={window:{BEC_APP:app},document:{getElementById:el,querySelector:el,querySelectorAll:()=>[],createElement:el,body:el('body'),activeElement:{tagName:'INPUT'}},OC:{emit(name,args){return new Promise((resolve,reject)=>sent.push({name,args,resolve,reject}));},onData(){}},setInterval(){},Date,Promise,console};
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
 console.log('Page save races, action feedback, checklist and component picker: 19 scenarios passed');
})().catch(e=>{console.error(e);process.exitCode=1;});
