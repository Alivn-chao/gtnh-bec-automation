local fs=require("filesystem")
local paths={"/home/bec_auto.lua","/home/bec_cache.lua"}
local plans={}
for _,path in ipairs(paths) do
  local f=assert(io.open(path,"r"),"文件不存在: "..path)
  local old=f:read("*a");f:close()
  if old:find('entangled_infinity%s*=') then
    print("已包含无尽映射: "..path)
  else
    local new,n=old:gsub('local mapping = {','local mapping = { entangled_infinity = "molten.infinity",')
    assert(n==1,"脚本版本不匹配，未修改: "..path)
    assert(load(new,"="..path),"修改后语法检查失败")
    plans[#plans+1]={path=path,old=old,new=new}
  end
end
local function write(path,text)
  local f=assert(io.open(path,"w"));assert(f:write(text));f:flush();f:close()
  f=assert(io.open(path,"r"));local saved=f:read("*a");f:close()
  assert(saved==text,"写入回读不一致: "..path)
end
for _,p in ipairs(plans) do
  local n=1;while fs.exists(p.path..".before-infinity-"..n) do n=n+1 end
  write(p.path..".before-infinity-"..n,p.old)
  write(p.path,p.new)
  print("已补齐无尽映射并保存旧脚本: "..p.path)
end
print("完成，可重新执行预缓存 preview 10。")
