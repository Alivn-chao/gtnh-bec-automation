from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
CHANGES={
 'lib/web_session.lua':[("return request.name=='cache'and type(request.args)=='table'and K and K.canServeFast(request.args)","return request.name=='pause'or request.name=='cache'and type(request.args)=='table'and K and K.canServeFast(request.args)"),("H.running=false;if P and P.co then P.stop=true end;if E then E.pauseAll()end;H.notice=","H.running=false;if P and P.co then P.stop=true end;if K then K.requestStop()end;if E then E.pauseAll()end;H.notice=")],
 'lib/cache.lua':[("local active,nextScan,nextGroup,names=nil,0,1,{}","local active,nextScan,nextGroup,names=nil,0,1,{}\n -- BEC_V3_PAUSE_RESPONSE_1: memory-only cancellation, safe between callbacks.\n function K.requestStop()if active then active.stop=true;active.deadline=0 end end"),("if clock.uptime()<(active.deadline or 0)then return end","if not active.stop and clock.uptime()<(active.deadline or 0)then return end")],
 'runtime/cache.lua':[("do if filename:sub(-4)==\".dat\" then local f=assert(io.open", "do if background and BEC_V2_CACHE_YIELD and BEC_V2_CACHE_YIELD()then return {} end if filename:sub(-4)==\".dat\" then local f=assert(io.open"),("local target,waiting=cacheTarget(cacheCopies)\nwhile waiting", "local target,waiting=cacheTarget(cacheCopies)\nif background and BEC_V2_CACHE_YIELD and BEC_V2_CACHE_YIELD()then return end\nwhile waiting")],
}
def patch(name,text):
 text=text.replace('-- BEC_V3_CACHE_RESPONSE_1: no hardware controls or binding edits in this lane.','-- BEC_V3_PAUSE_RESPONSE_1: cache edits and pause can run between callbacks.')
 for old,new in CHANGES[name]:
  assert text.count(old)==1,(name,old,text.count(old))
  text=text.replace(old,new)
 return text
if __name__=='__main__':
 out=ROOT/'outputs/oc-pause-20261025/patched'
 prepared=[]
 for name in CHANGES:
  p=ROOT/'reinstall_v2/files'/name;actual=ROOT/'outputs/oc-pause-20261025'/name
  prepared.append((p,patch(name,p.read_text(encoding='utf-8'))))
  q=out/name;q.parent.mkdir(parents=True,exist_ok=True);q.write_text(patch(name,actual.read_text(encoding='utf-8')),encoding='utf-8')
 for p,text in prepared:p.write_text(text,encoding='utf-8')
