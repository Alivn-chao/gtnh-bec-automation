"""Run two different test recipes through the real V2 Lua controllers.

Hardware timings below are explicit scenario assumptions, not game measurements.
No artificial latency is injected into component calls; sensitivity estimates
are reported separately and must not be confused with simulated elapsed time.
"""
import json
from pathlib import Path
import subprocess
from test_read_optimization import fixture
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
WORLD=(HERE/'two_recipe_world.lua').read_text(encoding='utf-8-sig')

def run(baseline=False,bank_size=27,latency_ms=0,controlled_input=False,force_v2_directory=False,bulk_count=5):
 l=fixture();l.globals().BANK_SIZE=bank_size;l.globals().RPC_LATENCY=latency_ms/1000;l.globals().CONTROLLED_INPUT=controlled_input
 l.globals().BULK_COUNT=bulk_count
 if baseline:
  for name in ['lib/bridge.lua','lib/engine.lua','runtime/controller.lua','runtime/nanites_cell.lua']:
   l.globals().s.files['/home/bec_v2/'+name]=subprocess.check_output(['git','show','549df6e:reinstall_v2/files/'+name],cwd=ROOT).decode('utf-8')
  l.execute("Bridge=loadfile('/home/bec_v2/lib/bridge.lua')();factory=loadfile('/home/bec_v2/lib/engine.lua')()")
 directory="/home/bec/recipes"if baseline and not force_v2_directory else "/home/bec_v2/recipes"
 l.execute("cfg.recipeDirectory="+repr(directory))
 l.execute(WORLD)
 error=None
 try:l.execute(r'''
for step=1,20000 do
 E.step()
 assert(not E.tasks[1].fault,table.concat(E.logs,' / '))
 if #world.outputs==2 then break end
 world.advance(.05)
 if #world.outputs==2 then break end
end
assert(#world.outputs==2,'second output not reached: '..table.concat(E.logs,' / '))
assert(world.outputs[1].item~=world.outputs[2].item)
assert(world.outputs[1].count==1 and world.outputs[2].count==1)
assert(world.heldItem.tier==5 and world.held==12000)
for _,amount in pairs(world.stock)do assert(amount==0,'extra condensate')end;assert(next(world.sub)==nil,'raw fluid left behind')
for _,side in ipairs({2,3})do for slot=1,12 do assert(world.io[side][slot]==nil,'cell left in IO')end end
''')
 except Exception as exc:error=str(exc)
 def conv(v):
  if hasattr(v,'items'):
   keys=list(v.keys())
   if keys and all(isinstance(k,(int,float))for k in keys):return [conv(v[i])for i in range(1,len(keys)+1)]
   return {str(k):conv(x)for k,x in v.items()}
  return v
 events=conv(l.globals().world.events);calls=conv(l.globals().world.calls)
 return {'version':'baseline-549df6e'if baseline else 'batch-stop-preview3','bank_size':bank_size,'component_delay_ms':latency_ms,'input_mode':'controlled-after-cohort'if controlled_input else 'rapid-one-tick-after-output','error':error,'healthy_completion':error is None,'second_product_output':len(l.globals().world.outputs)==2,'recipe_directory':directory,'stop_seconds':round(float(l.globals().s.now),3),'total_seconds':round(float(l.globals().world.outputs[2].time),3)if len(l.globals().world.outputs)==2 else None,'component_calls':sum(calls.values()),'calls_by_method':calls,'events':events,'outputs':conv(l.globals().world.outputs),'journal_writes':int(l.globals().s.writes)}

if __name__=='__main__':
 out=ROOT/'outputs/two_recipe_sim';out.mkdir(parents=True,exist_ok=True)
 results=[]
 for bank in [27,243]:
  for latency in [0,1,5,10]:
   for baseline in [True,False]:
    result=run(baseline,bank,latency);results.append(result)
    brief={k:v for k,v in result.items()if k not in ['events','calls_by_method','error']}
    brief['success']=result['error']is None
    if result['error']:brief['error']=result['error'][:140]
    print(json.dumps(brief,ensure_ascii=False),flush=True)
 for latency in [0,1,5,10]:
  for baseline in [True,False]:
   result=run(baseline,27,latency,True);results.append(result)
   brief={k:v for k,v in result.items()if k not in ['events','calls_by_method','error']}
   brief['success']=result['error']is None
   if result['error']:brief['error']=result['error'][-180:]
   print(json.dumps(brief,ensure_ascii=False),flush=True)
 (out/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
