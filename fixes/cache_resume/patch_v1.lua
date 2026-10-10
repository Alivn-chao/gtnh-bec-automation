-- V1 only: patch the installed controller; never edit or delete journals.
local fs = require("filesystem")
local path = "/home/bec_auto.lua"
local function read(p)
  local f = assert(io.open(p, "r"), "无法读取: " .. p)
  local text = f:read("*a"); f:close(); return text
end
local function write(p, text)
  local f = assert(io.open(p, "w"))
  assert(f:write(text)); assert(f:flush()); f:close()
  assert(read(p) == text, "文件回读不符: " .. p)
end
local patch = [=[
-- BEC_V1_CACHE_RESUME_V1
if old.stage == "cache-working" then
  assert(old.lastState == "idle" and old.plan == nil,
    "缓存恢复：旧生产状态不是空闲，保留日志核对")
  assert(type(old.expected) == "table" and next(old.expected) == nil
    and type(old.secured) == "table" and next(old.secured) == nil,
    "缓存恢复：旧生产还有原液记录，保留日志核对")
  local cf = assert(io.open("/home/bec_cache.journal", "r"), "缓存恢复：缺少缓存日志")
  local cache = ser.unserialize(cf:read("*a")); cf:close()
  assert(type(cache) == "table" and cache.version == 1 and cache.kind == "cache"
    and cache.background == true and cache.stage == "stopped"
    and cache.incomplete == false and cache.pending == nil and cache.configOwned == false,
    "缓存恢复：缓存尚未确认完成，保留日志核对")
  assert(type(cache.requests) == "table" and type(cache.transfers) == "table",
    "缓存恢复：缓存操作记录缺失")
  for _, job in pairs(cache.requests) do
    assert(type(job) == "table" and job.state == "done", "缓存恢复：申请尚未完成")
  end
  for _, move in pairs(cache.transfers) do
    assert(type(move) == "table" and move.ok == true and type(move.amount) == "number"
      and move.amount > 0 and move.amount == math.floor(move.amount)
      and move.requested == move.amount, "缓存恢复：搬液未完整确认")
  end
  assert(call(NODE, "getState") == "idle" and call(RS, "getOutput", sides.top) == 15
    and call(GEN, "isWorkAllowed") == false and call(GEN, "isMachineActive") == false,
    "缓存恢复：节点须空闲暂停且纠缠装置已停机")
  assert(next(network(SUB)) == nil, "缓存恢复：子网仍有原液，保留日志核对")
  assert(type(cache.target) == "table" and next(cache.target) ~= nil,
    "缓存恢复：缺少本轮目标")
  local stock = field()
  for name, amount in pairs(cache.target) do
    integer(amount)
    assert((stock[name] or 0) >= amount, "缓存恢复：实际库存未达本轮目标: " .. name)
  end
  -- Normalize only in memory. The existing archive keeps the original journal.
  old.stage = "waiting"
  print("后台缓存完成核对通过；归档旧生产日志后按实际库存继续，不重放旧搬液或申请。")
end
]=]
local original = read(path)
if original:find("BEC_V1_CACHE_RESUME_V1", 1, true) then
  print("补丁已安装，无需重复替换。"); return
end
assert(original:find('"cache-working"', 1, true)
  and original:find("该阶段存在未确认操作，不能自动恢复", 1, true),
  "不是支持的 V1 控制器，未修改文件")
local pattern = 'local%s+stopped%s*=%s*old%.stage%s*==%s*"stopped"'
local count = 0
local modified = original:gsub(pattern, function(anchor)
  count = count + 1; return patch .. "\n" .. anchor
end)
assert(count == 1, "恢复入口不唯一，未修改文件")
assert(load(modified, "@" .. path, "t", _ENV), "补丁后语法检查失败，未修改文件")
local i = 1
while fs.exists(path .. ".before-cache-resume-" .. i) do i = i + 1 end
local backup = path .. ".before-cache-resume-" .. i
local temporary = path .. ".cache-resume-new"
assert(not fs.exists(temporary), "已有补丁临时文件，请先核对")
write(temporary, modified)
assert(fs.rename(path, backup), "备份失败，原文件保留")
assert(read(backup) == original, "备份回读失败: " .. backup)
if not fs.rename(temporary, path) then
  assert(fs.rename(backup, path), "替换与还原失败；原文件在: " .. backup)
  error("替换失败，已还原原文件")
end
assert(read(path) == modified, "替换后回读失败；备份: " .. backup)
print("V1 恢复补丁已安装；备份: " .. backup)
print("两个 journal 均未修改。现在执行: lua /home/bec_ui.lua resume")
