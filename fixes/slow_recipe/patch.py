from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def patch(text):
 pairs=[('local releasedAt=computer.uptime() local deadline=releasedAt+600','local releasedAt=computer.uptime() -- BEC_V3_NO_RECIPE_TIMEOUT_1: slow recipes wait until completion or explicit stop.'),('local lastStock=field() local lastRequired=record.required','local lastRequired=record.required'),('releasedAt=computer.uptime();deadline=releasedAt+600;','releasedAt=computer.uptime();'),('if not same(stock,lastStock) then deadline=computer.uptime()+600;lastStock=stock end assert(computer.uptime()<deadline,"当前配方运行超时") tick(0.1) end','-- Recipe duration and condensate consumption can remain unchanged for hours.\n-- State, demand, gate, refill and cancellation guards above remain active.\ntick(0.1) end')]
 for old,new in pairs:
  assert text.count(old)==1,old
  text=text.replace(old,new)
 assert '当前配方运行超时' not in text
 return text
if __name__=='__main__':
 p=ROOT/'reinstall_v2/files/runtime/controller.lua';p.write_text(patch(p.read_text(encoding='utf-8')),encoding='utf-8')
 actual=ROOT/'outputs/oc-slow-recipe/runtime/controller.lua'
 (Path(__file__).parent/'files/runtime/controller.lua').write_text(patch(actual.read_text(encoding='utf-8')),encoding='utf-8')
