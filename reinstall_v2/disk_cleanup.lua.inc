-- Known public program copies only. Never inspect/remove state, config or recipes.
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
