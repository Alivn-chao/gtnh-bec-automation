local mode=...;assert(mode==nil or mode=='preview'or mode=='run','用法: preview / run')
local PROGRAMS={{name='cache_recover.lua',known={['11033:838290433']=true,['12616:1684725797']=true}},{name='lib/bridge.lua',known={['14972:1082549461']=true,['15577:279131571']=true,['16213:3509786521']=true,['16388:3843904074']=true,['17531:3804172498']=true,['17823:639475635']=true}},{name='lib/cache.lua',known={['14523:2427812688']=true,['14567:1872071256']=true,['15028:3434102137']=true,['15289:2748686704']=true}},{name='lib/config.lua',known={['7134:2524978389']=true,['7343:3682171505']=true,['7974:4162409531']=true,['8062:887779258']=true}},{name='lib/engine.lua',known={['11288:931933717']=true,['11346:3895804489']=true}},{name='lib/ochd_bindings.lua',known={['11343:2039590392']=true,['11367:2589897742']=true}},{name='lib/patterns.lua',known={['1254:2564943297']=true,['1565:1253859302']=true}},{name='lib/reports.lua',known={['12631:1425317797']=true}},{name='lib/scan.lua',known={['1084:563919335']=true}},{name='lib/setup.lua',known={['6584:3362520925']=true}},{name='lib/storage.lua',known={['2444:2080658477']=true}},{name='lib/ui.lua',known={['4830:1035520708']=true}},{name='lib/web_json.lua',known={['3795:1982527645']=true}},{name='lib/web_page.html',known={['223881:1516270899']=true,['226106:568371390']=true,['230757:852275199']=true,['231820:3886138659']=true,['232745:4075596562']=true,['232777:4208215465']=true,['239085:3601861998']=true,['239131:4115017095']=true,['245579:582996710']=true,['249319:940837747']=true,['254230:29138424']=true}},{name='lib/web_session.lua',known={['12354:680836750']=true,['15309:92251915']=true,['16316:2774872648']=true,['16360:2391294288']=true,['18381:3708681390']=true,['18504:2508797642']=true,['7956:3662685464']=true,['8356:432333941']=true,['8357:2294998177']=true}},{name='lib/web_transport.lua',known={['1818:2212865866']=true,['1959:2130565450']=true}},{name='main.lua',known={['2807:377377484']=true}},{name='report_setup.lua',known={['1769:3440927484']=true}},{name='runtime/cache.lua',known={['28595:725651639']=true,['28964:1580602570']=true}},{name='runtime/controller.lua',known={['37080:3439859331']=true,['37104:3097960326']=true,['37299:3439879977']=true,['37397:2834073227']=true,['37578:2459755070']=true,['38228:1284903203']=true}},{name='runtime/nanites.lua',known={['9966:880098026']=true}},{name='runtime/nanites_cell.lua',known={['14773:160252700']=true,['15338:3488554873']=true,['15841:1499134119']=true}},{name='runtime/patterns.lua',known={['7499:1281814973']=true,['7842:1953465280']=true}},{name='setup_hd.lua',known={['3112:3100826946']=true}},{name='web.lua',known={['2027:1356401707']=true,['2045:2430604015']=true,['2056:4125103834']=true,['2064:3017087304']=true,['2106:3736808363']=true,['2184:2645903512']=true}}}
local DOWNLOADS={{path='/home/bec_bulk10.lua',known={['255639:2500448323']=true,['262025:4113804180']=true,['262149:797237062']=true,['274910:1296939599']=true,['291583:1694457254']=true,['341200:1375549675']=true,['394319:3806346271']=true,['395462:835648152']=true,['395935:4218479931']=true,['396304:984049998']=true,['399093:3955966536']=true,['401465:560126815']=true}},{path='/home/bec_cache_partial_update.lua',known={['43720:655304920']=true,['45353:2402535808']=true}},{path='/home/bec_cache_update.lua',known={['320212:1478472029']=true,['373255:1676910998']=true,['373303:3517756284']=true,['374447:4175983147']=true,['374920:2942262493']=true,['375289:1580589275']=true,['378078:156416461']=true,['380450:328094450']=true}},{path='/home/bec_cohort_update.lua',known={['59206:3150078082']=true}},{path='/home/bec_connection_update.lua',known={['342990:2806147553']=true,['343149:3293685129']=true,['344293:936666190']=true,['344766:3823324925']=true,['347555:183969778']=true,['349926:1177862356']=true}},{path='/home/bec_display_update.lua',known={['50060:1268535965']=true,['50444:4045009043']=true}},{path='/home/bec_dynamic_update.lua',known={['72389:1384906948']=true,['72662:3678231255']=true,['74308:721678989']=true,['74781:2838617392']=true}},{path='/home/bec_hive_update.lua',known={['37052:3017454802']=true,['37343:2363245455']=true}},{path='/home/bec_patterns_update.lua',known={['287560:3902876756']=true,['337175:2395932425']=true,['382638:1302411663']=true,['383781:3402496008']=true,['384254:1625547435']=true,['384623:4041565886']=true,['387412:2281521080']=true,['389784:4004042959']=true}},{path='/home/bec_v2_install.lua',known={['392399:691799228']=true,['395755:2693533191']=true,['401476:2795711367']=true,['402555:2512187329']=true,['408863:4075009926']=true,['408909:368564127']=true,['419581:2723724122']=true,['426941:389342297']=true,['428337:1527835199']=true,['456908:1189504718']=true,['458554:3049586308']=true,['459027:2631657767']=true,['470459:4254909307']=true,['472042:588011438']=true,['474831:2092052648']=true,['477203:2834287039']=true,['477437:1954228483']=true}},{path='/home/bec_web_update.lua',known={['234099:2141107319']=true,['234121:3687871671']=true,['235297:3666124959']=true,['236290:2226634824']=true,['241563:1667714973']=true,['241636:3074258541']=true,['248416:2239211125']=true,['252371:3864805353']=true,['257436:3248101813']=true}}}
local cleanup=assert(load([=[-- Known public program copies only. Never inspect/remove state, config or recipes.
return function(PROGRAMS,DOWNLOADS)
local fs=require('filesystem')
local function read(p)local f=io.open(p,'r');if not f then return end;local s=f:read(1048577);f:close();if not s or #s>1048576 then return end;return s end
local function sig(s)local a,b=1,0;for i=1,#s do a=(a+s:byte(i))%65521;b=(b+a)%65521 end;return string.format('%d:%.0f',#s,b*65536+a)end
local function fingerprint(p)local s=read(p);if not s then return end;return sig((s:gsub('\r\n','\n'))),sig(s),#s end
local function modified(p)local ok,n=pcall(fs.lastModified or function()return 0 end,p);return ok and type(n)=='number'and n or 0 end
local function free()local d=fs.get('/home/bec_v2');return d and d.spaceTotal()-d.spaceUsed()end
local function cleanup(run)
 local plan={};local reclaim=0
 for _,entry in ipairs(PROGRAMS)do
  local current='/home/bec_v2/'..entry.name;local version,currentExact=fingerprint(current)
  if entry.known[version]then
   local directory=current:match('^(.*)/');local base=current:match('([^/]+)$');local rows={}
   for name in fs.list(directory)do
    if not name:find('[/\\]')and not name:find('..',1,true)and name:match('^'..base:gsub('([^%w])','%%%1')..'%.before%-%w[%w%-]*%-%d+$')then
     local path=directory..'/'..name;local v,exact,bytes=fingerprint(path)
     if entry.known[v]then rows[#rows+1]={path=path,exact=exact,bytes=bytes,modified=modified(path),id=tonumber(name:match('(%d+)$'))or 0}end
    end
   end
   table.sort(rows,function(a,b)if a.modified~=b.modified then return a.modified>b.modified end;if a.id~=b.id then return a.id>b.id end;return a.path>b.path end)
   -- Retain one verified rollback copy per currently recognized program.
   for i=2,#rows do local r=rows[i];r.current=current;r.currentExact=currentExact;r.keep=rows[1].path;r.keepExact=rows[1].exact;plan[#plan+1]=r;reclaim=reclaim+r.bytes end
  end
 end
 for _,entry in ipairs(DOWNLOADS)do local version,exact,bytes=fingerprint(entry.path)
  if entry.known[version]then plan[#plan+1]={path=entry.path,exact=exact,bytes=bytes};reclaim=reclaim+bytes end
 end
 print('已识别可清理 '..#plan..' 个旧程序副本/更新器，约 '..math.floor(reclaim/1024)..' KiB；每个程序保留1份已验证回滚副本。')
 if not run then print('只读预览；实际清理使用 run。');return #plan,reclaim end
 local removed,bytes=0,0
 for _,r in ipairs(plan)do
  local _,exact=fingerprint(r.path);assert(exact==r.exact,'待清理文件已变化，保留停止：'..r.path)
  if r.current then local _,current=fingerprint(r.current);local _,kept=fingerprint(r.keep);assert(current==r.currentExact and kept==r.keepExact,'当前程序或保留备份变化，保留停止')end
  local ok,result,reason=pcall(fs.remove,r.path)
  if not fs.exists(r.path)then removed=removed+1;bytes=bytes+r.bytes
  else print('未能清理，保留：'..r.path..' / '..tostring(ok and reason or result))end
 end
 local available=free();print('已清理 '..removed..' 个文件，约 '..math.floor(bytes/1024)..' KiB；剩余 '..(available and math.floor(available/1024)..' KiB'or '不可读'))
 print('配置、配方、state、故障报告和未确认日志均未清理。')
 return removed,bytes
end
return cleanup
end
]=],'@disk-cleanup-core','t',_ENV))()(PROGRAMS,DOWNLOADS)
cleanup(mode=='run')
