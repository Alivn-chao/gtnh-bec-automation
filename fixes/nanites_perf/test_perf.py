import sys
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'fixes/nanites_io'))
from test_module import LuaRuntime, SETUP, EXT, SOURCE

SCRIPT = Path(__file__).with_name('run.lua').read_text(encoding='utf-8')


def fixture():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(SETUP + EXT)
    lua.globals().files['/home/bec_nanites.lua'] = SOURCE
    lua.execute(r'''
      local oldOpen=io.open
      io.open=function(path,mode)
        if mode=='w' and path=='/home/bec_nanites_perf.txt' then
          return {write=function(_,s) files[path]=s;return true end,
            flush=function()return true end,close=function()end}
        end
        local f=oldOpen(path,mode)
        if f then
          for _,key in ipairs({'read','write','flush','close'}) do
            local original=f[key]
            if original then f[key]=function(...)now=now+0.01;return original(...)end end
          end
        end
        return f
      end
      local c=require('component');local oldCall=c.invoke
      c.invoke=function(...)now=now+0.02;return oldCall(...)end
      loadfile=function(path,mode,env)
        assert(path=='/home/bec_ui.lua')
        return function(mode)
          assert(mode=='resume');uiStarts=(uiStarts or 0)+1
          local worker=assert(loadfile('/home/bec_nanites.lua','t',env))()
          return worker.ensure({passive=true,stage=true})
        end
      end
      savedLoadfile=loadfile
      seedHive(37604,'Silver',101);inv[0][9]=disk(0)
      inv[0][10]=disk(19612);need=4
    ''')
    return lua


class ProfilerTests(unittest.TestCase):
    def run_script(self, lua):
        return lua.execute("return assert(load(...))('resume')", SCRIPT)

    def test_real_module_exchange_records_phases_preserves_sources(self):
        lua = fixture()
        self.assertTrue(self.run_script(lua))
        g = lua.globals()
        self.assertEqual(g.moves, 4)
        self.assertEqual(g.heldCount, 19612)
        self.assertEqual(g.files['/home/bec_nanites.lua'], SOURCE)
        self.assertEqual(g.files['/home/bec_auto.journal'], 'production-record')
        self.assertTrue(lua.eval('loadfile==savedLoadfile'))
        report = g.files['/home/bec_nanites_perf.txt']
        for label in ['扫描硬盘盒', 'ME IO处理和确认', '保存换蜂日志', 'transferItem: 4 次', '日志写入含回读']:
            self.assertIn(label, report)
        self.assertEqual(lua.eval("require('serialization').unserialize(files[PATH]).stage"), 'done')
        total = float(re.search(r'总耗时 ([0-9.]+)', report)[1])
        own = sum(float(v) for v in re.findall(r': \d+ / [0-9.]+ / ([0-9.]+)', report))
        rest = float(re.search(r'决策及其他: ([0-9.]+)', report)[1])
        self.assertAlmostEqual(total, own + rest, places=2)

    def test_callback_wait_is_separate_from_io_scans(self):
        lua = fixture()
        lua.execute('lag=true')
        self.run_script(lua)
        report = lua.globals().files['/home/bec_nanites_perf.txt']
        self.assertIn('轮询等待及界面回调', report)
        self.assertIn('节点与控制器检查', report)

    def test_unknown_transfer_report_and_no_retry_or_masking(self):
        lua = fixture()
        lua.execute('broken=true')
        with self.assertRaisesRegex(Exception, 'lost response'):
            self.run_script(lua)
        self.assertEqual(lua.globals().moves, 1)
        self.assertIn('结果 失败', lua.globals().files['/home/bec_nanites_perf.txt'])
        self.assertTrue(lua.eval('loadfile==savedLoadfile'))
        self.assertEqual(lua.eval("require('serialization').unserialize(files[PATH]).stage"), 'moving-cell')

    def test_no_switch_does_not_write_report(self):
        lua = fixture()
        lua.execute("seedHive(128);need=4;inv[0][10]=disk(0)")
        self.assertFalse(self.run_script(lua))
        self.assertEqual(lua.globals().moves, 0)
        self.assertIsNone(lua.globals().files['/home/bec_nanites_perf.txt'])

    def test_report_failure_does_not_fail_successful_exchange(self):
        lua = fixture()
        lua.execute("local original=io.open;io.open=function(p,m)if p=='/home/bec_nanites_perf.txt' and m=='w'then return nil end;return original(p,m)end")
        self.assertTrue(self.run_script(lua))
        self.assertEqual(lua.globals().heldCount, 19612)

    def test_old_module_rejected_before_starting_ui(self):
        lua = fixture()
        lua.globals().files['/home/bec_nanites.lua'] = SOURCE.replace('M.fastStages=true', '')
        with self.assertRaisesRegex(Exception, '当前快速换蜂模块'):
            self.run_script(lua)
        self.assertIsNone(lua.globals().uiStarts)
        self.assertEqual(lua.globals().moves, 0)


if __name__ == '__main__':
    unittest.main()
