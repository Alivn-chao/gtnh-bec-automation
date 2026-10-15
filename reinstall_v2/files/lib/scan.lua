local c=require('component')
return function()
 local rows={}
 for address,kind in c.list()do rows[#rows+1]={address=address,kind=kind}end
 table.sort(rows,function(a,b)return a.kind==b.kind and a.address<b.address or a.kind<b.kind end)
 print('OC组件地址 / 只读扫描')
 print('同类型多台设备：临时断开其他同类设备的OC连接，再扫描定位。')
 for _,row in ipairs(rows)do
  if row.kind=='me_interface'or row.kind=='gt_machine'or row.kind=='bec_io_node'or row.kind=='bec_storage'or row.kind=='bec_diode'or row.kind=='redstone'or row.kind=='transposer'then
   print(row.kind..'  '..row.address)
   if row.kind=='gt_machine'then local ok,name=pcall(c.invoke,row.address,'getName');if ok then print('  机器名称：'..tostring(name))end end
   if row.kind=='transposer'then
    for side=0,5 do local ok,name=pcall(c.invoke,row.address,'getInventoryName',side)
     if ok and name then print('  面 '..side..' 库存：'..name)end
    end
   end
  end
 end
 print('方向：0下 1上 2北 3南 4西 5东；方向以转运器/红石I/O自身为准。')
end
