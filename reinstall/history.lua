-- Bound completed runtime archives so a 4 MB disk does not fill with old rounds.
local fs=require('filesystem')
local allowed={['/home/bec_auto.journal.stopped-']=true,['/home/bec_auto.journal.before-resume-']=true,
 ['/home/bec_cache.journal.stopped-']=true,['/home/bec_nanites_io.journal.before-run-']=true}
local M={}
function M.prune(prefix,keep)
 assert(allowed[prefix],'Unknown history group')
 keep=keep or 3;assert(type(keep)=='number'and keep>=0 and keep%1==0)
 local namePrefix=prefix:sub(7);local rows={}
 for name in fs.list('/home')do
  if name:sub(1,#namePrefix)==namePrefix then
   local index=tonumber(name:sub(#namePrefix+1))
   if name:sub(#namePrefix+1):match('^%d+$')and not fs.isDirectory('/home/'..name)then
    local ok,time=pcall(fs.lastModified,'/home/'..name)
    rows[#rows+1]={path='/home/'..name,index=index,time=ok and tonumber(time)or 0}
   end
  end
 end
 table.sort(rows,function(a,b)if a.time~=b.time then return a.time>b.time end;return a.index>b.index end)
 for i=keep+1,#rows do assert(fs.remove(rows[i].path),'Could not prune '..rows[i].path)end
end
return M
