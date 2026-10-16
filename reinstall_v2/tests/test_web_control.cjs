// Exercise the actual page controller with deferred OC acknowledgements.
const assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
const source=fs.readFileSync(path.join(__dirname,'../web/control.js'),'utf8');
function fixture(){
 const elements=new Map(),sent=[];
 function el(id){if(!elements.has(id))elements.set(id,{textContent:'',innerHTML:'',disabled:false,dataset:{},options:[],value:'',classList:{toggle(){}},querySelector:()=>el('child'),querySelectorAll:()=>[],appendChild(){},insertBefore(){},addEventListener(){},showModal(){},close(){}});return elements.get(id);}
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
 console.log('Page save races and model binding: 8 scenarios passed');
})().catch(e=>{console.error(e);process.exitCode=1;});
