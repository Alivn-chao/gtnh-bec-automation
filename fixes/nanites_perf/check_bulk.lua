-- Read-only format probe: no transfers, configuration or redstone writes.
local c=require('component')
local clock=require('computer')
local T='13070035-3a3f-4468-b896-1c084288fdc9'
local PATH='/home/bec_nanites_bulk_check.txt'
local lines={}
local function out(s)lines[#lines+1]=tostring(s);print(s)end
local function pack(...)return {n=select('#',...),...}end
local unpack=table.unpack or unpack
local function attempt(label,fn)
 local start=clock.uptime();local values=pack(pcall(fn))
 out(string.format('%s: %s / %.3f s',label,values[1] and 'OK' or 'ERROR',clock.uptime()-start))
 if not values[1]then out('  '..tostring(values[2]));return false end
 return true,unpack(values,2,values.n)
end
local function field(v,key)
 local ok,result=pcall(function()return v[key]end)
 return ok and result or nil
end
local function keys(v)
 if type(v)~='table'then return 'not-table' end
 local result={};for k,x in pairs(v)do result[#result+1]=tostring(k)..'='..type(x)end
 table.sort(result);local n=#result
 while #result>18 do table.remove(result)end
 return table.concat(result,', ')..(n>18 and ' ...' or '')
end
local function summary(v)
 if v==nil then return 'nil' end
 if type(v)~='table'then return type(v)..':'..tostring(v)end
 return string.format('name=%s size=%s storedItemCount=%s available=%s; keys: %s',
  tostring(v.name),tostring(v.size),tostring(v.storedItemCount),type(v.getAvailableItems),keys(v))
end
out('BEC BULK FORMAT CHECK / READ ONLY')
assert(c.type(T)=='transposer','Nanite transposer missing')
local methods=c.methods(T)
out('getAllStacks method: '..tostring(methods.getAllStacks)..' (false also means available)')
for _,side in ipairs({0,2,3})do
 out('');out('SIDE '..side..' (0=bank, 2=return IO, 3=load IO)')
 local size
 local ok,value=attempt('inventory size',function()return c.invoke(T,'getInventorySize',side)end)
 if ok then size=value;out('  size='..tostring(size))end
 local rows,count
 if methods.getAllStacks~=nil then
  local got,reader=attempt('getAllStacks',function()return c.invoke(T,'getAllStacks',side)end)
  if got and reader~=nil then
   out('reader type='..type(reader)..'; keys: '..keys(reader))
   out('reader.count type='..type(field(reader,'count'))..'; reader.getAll type='..type(field(reader,'getAll')))
   local counted,n=attempt('reader.count()',function()return reader.count()end)
   if counted then count=n;out('  count='..tostring(n)..'; matches size='..tostring(n==size))end
   local all,result=attempt('reader.getAll()',function()return reader.getAll()end)
   if all then
    out('  result type='..type(result))
    if type(result)=='table'then rows=result end
   end
  end
 end
 local samples,seen={},{}
 local function add(slot)
  if type(slot)=='number' and slot%1==0 and slot>=1 and type(size)=='number' and slot<=size and not seen[slot]then
   seen[slot]=true;samples[#samples+1]=slot
  end
 end
 add(1);add(size)
 if rows then
  local entries,min,max,occupied,missing=0,nil,nil,0,0
  local inRange=true;local other=0;local positions={}
  for key,item in pairs(rows)do
   entries=entries+1
   if type(key)=='number'then
    min=min and math.min(min,key)or key;max=max and math.max(max,key)or key
    if key%1~=0 or key<1 or type(size)~='number' or key>size then inRange=false end
   else other=other+1;inRange=false end
   if type(item)=='table' and item.name then
    occupied=occupied+1
    if item.storedItemCount==nil or type(item.getAvailableItems)~='table'then missing=missing+1 end
    if type(key)=='number'then positions[#positions+1]=key end
   end
  end
  table.sort(positions)
  out(string.format('rows: entries=%d numericMin=%s numericMax=%s otherKeys=%d',entries,tostring(min),tostring(max),other))
  out(string.format('occupied=%d missing-cell-metadata=%d',occupied,missing))
  out('CURRENT GUARD: count-match='..tostring(count==size)..'; all-keys-in-1..size='..tostring(inRange))
  out('rows[0]: '..summary(rows[0]))
  for i=1,math.min(3,#positions)do add(positions[i]);add(positions[i]+1)end
 end
 for _,slot in ipairs(samples)do
  out('slot '..slot..' bulk[same]: '..summary(rows and rows[slot]))
  out('slot '..slot..' bulk[slot-1]: '..summary(rows and rows[slot-1]))
  local got,item=attempt('getStackInSlot('..side..','..slot..')',function()return c.invoke(T,'getStackInSlot',side,slot)end)
  if got then out('  physical: '..summary(item))end
 end
end
out('');out('No items moved; no outputs, configurations or production journals changed.')
local text=table.concat(lines,'\n')..'\n'
local f=assert(io.open(PATH,'w'));assert(f:write(text));assert(f:flush());f:close()
local r=assert(io.open(PATH,'r'));local verified=r:read('*a');r:close();assert(verified==text,'Report read-back failed')
print('REPORT: '..PATH)
