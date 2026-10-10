-- One-shot, read-only diagnostics. The receiver fills in this endpoint.
local ENDPOINT = "__BEC_ENDPOINT__"
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local serialization = require("serialization")
local MAX_FILE, MAX_FILES = 512 * 1024, 298
assert(ENDPOINT ~= "__BEC_ENDPOINT__", "请下载接收端提供的 bootstrap.lua")
assert(component.isAvailable("internet"), "需要互联网卡")
local card = component.internet
assert(card.isHttpEnabled(), "服务器禁用了互联网卡 HTTP 请求")

local function post(path, body)
  local handle, err = card.request(ENDPOINT .. path, body, {["Content-Type"]="application/octet-stream"})
  assert(handle, tostring(err))
  local ok, result = pcall(function()
    local deadline = computer.uptime() + 45
    while not handle.finishConnect() do
      assert(computer.uptime() < deadline, "连接超时")
      os.sleep(0.05)
    end
    local code = handle.response()
    local chunks, length = {}, 0
    while true do
      assert(computer.uptime() < deadline, "读取响应超时")
      local chunk = handle.read(2048)
      if chunk == nil then break end
      if chunk == "" then os.sleep(0.05) else
        length = length + #chunk
        assert(length <= 8192, "接收端响应过长")
        chunks[#chunks+1] = chunk
      end
    end
    local reply = table.concat(chunks)
    assert(code and code >= 200 and code < 300, "HTTP " .. tostring(code) .. ": " .. reply)
    return reply
  end)
  pcall(handle.close)
  assert(ok, tostring(result))
  return result
end

local session = post("/start", computer.address()):match("^SESSION ([0-9a-f]+)")
assert(session and #session == 32, "接收端没有返回有效会话")
local sent, report = 0, {}
local function note(text)
  report[#report+1] = text
  print(text)
end
local function escape(text)
  return (text:gsub("[^A-Za-z0-9_.%-]", function(c) return string.format("%%%02X", c:byte()) end))
end
local function upload(name, data)
  assert(#data <= MAX_FILE, name .. " 超过512 KiB")
  assert(post("/upload/" .. session .. "?name=" .. escape(name), data):match("^OK"), "接收确认异常")
  sent = sent + 1
end

local function safe(value)
  local ok, text = pcall(serialization.serialize, value, false)
  if not ok then return tostring(value) end
  return text
end
local lines, bytes, omitted = {}, 0, 0
local function line(text)
  if bytes + #text + 1 > MAX_FILE - 256 then omitted=omitted+1; return end
  lines[#lines+1] = text
  bytes = bytes + #text + 1
end
local function query(address, method, ...)
  local methods = component.methods(address)
  if methods[method] == nil then return end
  local values = {pcall(component.invoke, address, method, ...)}
  local ok = table.remove(values, 1)
  line(address .. " " .. method .. " " .. (ok and safe(values) or ("ERROR " .. tostring(values[1]))))
end

note("BEC 只读上传：" .. session)
line("Snapshot uptime=" .. tostring(computer.uptime()) .. " computer=" .. computer.address())
line("Reads are sequential; running machines can change between readings.")
local addresses = {}
for address, kind in component.list() do addresses[#addresses+1] = {address=address,kind=kind} end
table.sort(addresses, function(a,b) return a.address < b.address end)
for _, entry in ipairs(addresses) do
  local a, kind = entry.address, entry.kind
  line("COMPONENT " .. a .. " " .. kind .. " methods=" .. safe(component.methods(a)))
  if kind:match("^bec_") or kind == "gt_machine" then
    for _, method in ipairs({"getName", "getState", "isWorkAllowed", "isMachineActive",
      "getParallelRecipesInProgress", "getRequiredCondensate", "getConsumedCondensate",
      "getSlowdowns", "getRequiredTier", "getProvidedTier", "getAvailableNanites",
      "getStoredCondensate", "getFieldStrength", "getCondensateFilters", "getMinParallel", "getMaxParallel"}) do
      query(a, method)
    end
  elseif kind == "transposer" then
    for side=0,5 do
      line("SIDE " .. tostring(side))
      query(a, "getFluidInTank", side)
      query(a, "getTankCount", side)
      query(a, "getInventoryName", side)
      query(a, "getInventorySize", side)
    end
  elseif kind == "redstone" then
    for side=0,5 do query(a, "getOutput", side) end
  elseif kind == "me_interface" then
    query(a, "getFluidsInNetwork")
    local methods = component.methods(a)
    if methods.getCpus ~= nil then
      local ok, cpus = pcall(component.invoke, a, "getCpus")
      if ok and type(cpus) == "table" then
        for i, cpu in ipairs(cpus) do
          line("CPU " .. a .. " " .. tostring(i) .. " name=" .. tostring(cpu.name) .. " busy=" .. tostring(cpu.busy))
          local control = cpu.cpu
          if control then
            for _, method in ipairs({"activeItems", "pendingItems", "finalOutput"}) do
              if type(control[method]) == "function" then
                local success, value = pcall(control[method])
                line("CPU " .. tostring(i) .. " " .. method .. " " .. (success and safe(value) or tostring(value)))
              end
            end
          end
        end
      elseif not ok then line("CPU ERROR " .. tostring(cpus)) end
    end
    -- Only the two existing bee subnets: avoid reading all main-network items.
    if a == "41c9711c-cb6c-4fb5-8690-9a4ff709d18b" or a == "5009c70f-9607-48b1-8831-488b599942cd" then
      query(a, "getItemsInNetwork")
    end
  end
  os.sleep(0)
end
line("Snapshot end uptime=" .. tostring(computer.uptime()))
lines[#lines+1] = "Oversized readout lines omitted=" .. tostring(omitted)
upload("runtime.txt", table.concat(lines, "\n") .. "\n")
note("已上传组件和状态读数")

local files = {}
local function scan(directory, predicate)
  if not fs.exists(directory) then return end
  for name in fs.list(directory) do
    local path = fs.concat(directory, name)
    if predicate(name) and not fs.isDirectory(path) then files[#files+1] = path end
  end
end
scan("/home", function(name)
  if name:match("^bec_upload") then return false end
  return name:match("^bec_[A-Za-z0-9_.%-]+$") and
    (name:find(".lua",1,true) or name:find(".journal",1,true) or name:match("%.cfg$") or name:match("%.dat$"))
end)
scan("/home/bec/recipes", function(name) return name:match("^[A-Za-z0-9_.%-]+%.dat$") end)
table.sort(files)
for _, path in ipairs(files) do
  if sent >= MAX_FILES then note("SKIP 文件数量上限：" .. path) else
    local size = fs.size(path)
    if size > MAX_FILE then note("SKIP 文件超过512 KiB：" .. path) else
      local stream, err = io.open(path, "rb")
      if not stream then note("SKIP 无法读取：" .. path .. " " .. tostring(err)) else
        local data = stream:read(MAX_FILE + 1) or ""
        stream:close()
        if #data > MAX_FILE then note("SKIP 文件增长超过上限：" .. path) else
          upload(path:gsub("^/", ""), data)
          note("已上传 " .. path .. " " .. tostring(#data) .. " bytes")
        end
      end
    end
  end
  os.sleep(0)
end
upload("upload_report.txt", table.concat(report, "\n") .. "\n")
local receipt = post("/finish/" .. session, "done")
assert(receipt:match("^OK " .. session), "完成确认异常")
print("上传完成：" .. tostring(sent) .. " 个文件")
print("会话：" .. session)
print("未启停机器、未搬料、未改原文件。")
