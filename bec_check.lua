-- Minimal read-only check. ASCII output avoids Unicode rendering issues.
local component = require("component")
local targets = {
  bec_io_node=true, bec_storage=true, bec_diode=true,
  gt_machine=true, me_interface=true, fluid_interface=true,
  me_controller=true, transposer=true, database=true
}
local rows = {"BEC component check"}
local ok, err = xpcall(function()
  for address, kind in component.list() do
    if targets[kind] then
      rows[#rows+1] = kind
      rows[#rows+1] = address
      rows[#rows+1] = ""
    end
  end
end, debug.traceback)
if not ok then rows[#rows+1] = tostring(err) end
local f = io.open("/home/bec_check_report.txt", "w")
if f then f:write(table.concat(rows,"\n")); f:close() end
for i, line in ipairs(rows) do
  print(line)
  if i % 12 == 0 and i < #rows then
    io.write("Press Enter to continue...")
    io.read()
  end
end
print("Report: /home/bec_check_report.txt")
