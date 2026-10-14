-- BEC history cleanup. Never removes active files, .previous, programs or reset evidence.
local mode=(...)or 'clean'
assert(mode=='clean'or mode=='check','usage: clean / check')
local fs=require('filesystem');local c=require('component')
assert(c.invoke('266f65b5-20be-4543-8f2f-bfd2d0816611','getOutput',1)==15,'Exit UI with Q first')
assert(c.invoke('c1ae3f7c-f714-4c27-baf3-392d94a0aa50','isWorkAllowed')==false,'Stop the controller first')
local prefixes={'bec_cache.journal.stopped-','bec_auto.journal.stopped-',
 'bec_auto.journal.before-resume-','bec_nanites_io.journal.before-run-'}
local groups={};local total,removed=0,0
for name in fs.list('/home')do
 if not name:find('/',1,true)then
  for _,prefix in ipairs(prefixes)do
   local suffix=name:sub(#prefix+1)
   if name:sub(1,#prefix)==prefix and suffix:match('^%d+$')then
    local p='/home/'..name
    assert(not fs.isDirectory(p),'Unexpected directory: '..p)
    local ok,time=pcall(fs.lastModified,p)
    local rows=groups[prefix]or {};groups[prefix]=rows
    rows[#rows+1]={path=p,index=tonumber(suffix),time=ok and tonumber(time)or 0,size=fs.size(p)or 0}
   end
  end
 end
end
for _,prefix in ipairs(prefixes)do
 local rows=groups[prefix]or {}
 table.sort(rows,function(a,b)
  local x,y=a.time or 0,b.time or 0
  if x~=y then return x>y end
  return a.index>b.index
 end)
 for i=4,#rows do
  local row=rows[i]
  if mode=='clean'then assert(fs.remove(row.path),'Could not remove '..row.path)end
  removed=removed+1;total=total+row.size
 end
end
print((mode=='check'and 'Would remove 'or 'Removed ')..removed..' old history files; '..total..' bytes')
print('Kept 3 per history group. Active journals, .previous, reset backups, settings, recipes and programs kept.')
local ok,disk=pcall(fs.get,'/home')
if ok and disk and type(disk.spaceTotal)=='function'and type(disk.spaceUsed)=='function'then
 print('Free space: '..(disk.spaceTotal()-disk.spaceUsed())..' bytes')
end
print('If an IO journal write failed, check it before restarting a disk transfer.')
