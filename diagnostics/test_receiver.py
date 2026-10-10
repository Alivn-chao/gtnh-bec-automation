import json
import hashlib
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import quote

from receiver import Receiver, allowed_name


class ReceiverTests(unittest.TestCase):
    def test_v1_reset_patch_public_fixed_route(self):
        code, body = self.request('/process-reset/patch.lua')
        self.assertEqual(code, 200)
        self.assertIn('BEC_V1_NEXT_RECIPE_V1', body)
        self.assertEqual(self.request('/process-reset/patch.lua?path=runtime.txt')[0], 404)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.url_file = self.root / "url.txt"
        self.url_file.write_text("https://example.test", encoding="utf-8")
        self.token = "ab" * 32
        self.server = Receiver(("127.0.0.1", 0), self.root / "data", self.token,
                               Path(__file__).with_name("upload.lua"), self.url_file)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = "http://127.0.0.1:" + str(self.server.server_port)

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, path, body=None):
        try:
            with urllib.request.urlopen(urllib.request.Request(self.base + path, data=body), timeout=3) as response:
                return response.status, response.read().decode()
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode()

    def start(self):
        status, text = self.request("/" + self.token + "/start", b"computer-1")
        self.assertEqual(status, 201)
        return text.strip().split()[1]

    def test_no_public_data_or_unauthorized_upload(self):
        self.assertEqual(self.request("/health")[0], 200)
        self.assertEqual(self.request("/wrong/start", b"data")[0], 404)
        self.assertEqual(self.request("/" + self.token + "/runtime.txt")[0], 404)

    def test_bootstrap_endpoint_and_guard(self):
        status, script = self.request("/" + self.token + "/bootstrap.lua")
        self.assertEqual(status, 200)
        self.assertIn('local ENDPOINT = "https://example.test/' + self.token + '"', script)
        self.assertIn('assert(ENDPOINT ~= "__BEC_ENDPOINT__"', script)

    def test_fixed_public_sidefix_mirror(self):
        status, script = self.request('/sidefix/install.lua')
        self.assertEqual(status, 200)
        self.assertIn("local url='https://example.test/sidefix/bec_nanites.lua'", script)
        self.assertNotIn(self.token, script)
        status, module = self.request('/sidefix/bec_nanites.lua')
        self.assertEqual(status, 200)
        self.assertEqual(len(module.encode()), 11148)
        self.assertEqual(hashlib.sha256(module.encode()).hexdigest(),
                         '55686269c941015d2c39f394d20ff57fb5a78dca265ff5f015f381ffb389abec')
        for path in ('/sidefix/runtime.txt', '/sidefix/../receiver.py', '/sidefix/install.lua?file=runtime.txt'):
            self.assertEqual(self.request(path)[0], 404)

    def test_fixed_public_io_test_mirror(self):
        status, script = self.request('/nanites-io/test.lua')
        self.assertEqual(status, 200)
        self.assertEqual(script, (Path(__file__).parent.parent / 'fixes' / 'nanites_io' /
                                 'bec_nanites_io_test.lua').read_text(encoding='utf-8'))
        self.assertNotIn(self.token, script)
        for path in ('/nanites-io/runtime.txt', '/nanites-io/test.lua?file=runtime.txt',
                     '/nanites-io/../receiver.py'):
            self.assertEqual(self.request(path)[0], 404)

    def test_fixed_public_io_module_and_installer(self):
        status, module = self.request('/nanites-io/bec_nanites.lua')
        self.assertEqual(status, 200)
        self.assertEqual(hashlib.sha256(module.encode()).hexdigest(),
                         'ad53c28bb3a4bd6b6eff7a784c9a7d0950d67e6b11d56ddf4168ef9c200eb942')
        status, installer = self.request('/nanites-io/install.lua')
        self.assertEqual(status, 200)
        self.assertIn("local url='https://example.test/nanites-io/bec_nanites.lua'", installer)
        self.assertNotIn(self.token, installer)
        self.assertEqual(self.request('/nanites-io/install.lua?file=runtime.txt')[0], 404)

    def test_snapshot_receipt_hash_and_idempotent_upload(self):
        session = self.start()
        path = "/" + self.token + "/upload/" + session + "?name=" + quote("home/bec_auto.journal.before-resume-30")
        self.assertEqual(self.request(path, b"test")[0], 200)
        self.assertEqual(self.request(path, b"test")[0], 200)
        self.assertEqual(self.request(path, b"changed")[0], 409)
        self.assertEqual(self.request("/" + self.token + "/finish/" + session, b"")[0], 200)
        manifest = json.loads((self.root / "data" / session / "manifest.json").read_text())
        self.assertTrue(manifest["complete"])
        self.assertEqual(manifest["bytes"], 4)
        self.assertEqual(len(manifest["files"]), 1)
        self.assertEqual(manifest["files"]["home/bec_auto.journal.before-resume-30"]["sha256"],
                         "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")

    def test_path_traversal_and_unrelated_files_rejected(self):
        session = self.start()
        for name in ("../secrets", "home/bec_../../secret", "C:/secret", "home/personal.lua", "manifest.json"):
            path = "/" + self.token + "/upload/" + session + "?name=" + quote(name)
            self.assertEqual(self.request(path, b"test")[0], 400)
        self.assertTrue(allowed_name("home/bec/recipes/gregtech_gt_1.dat"))

    def test_size_limit(self):
        session = self.start()
        path = "/" + self.token + "/upload/" + session + "?name=runtime.txt"
        self.assertEqual(self.request(path, b"x" * (512 * 1024 + 1))[0], 413)

    def test_lua_readonly_snapshot_and_http_errors(self):
        # Use the existing optional Lua 5.2 test runtime, not a game connection.
        sys.path.insert(0, str(Path(__file__).parent.parent / "work" / "lua_runtime"))
        try:
            from lupa.lua52 import LuaRuntime
        except ImportError:
            self.skipTest("Optional lupa.lua52 test runtime is unavailable")
        source = Path(__file__).with_name("upload.lua").read_text(encoding="utf-8")
        source = source.replace('"__BEC_ENDPOINT__"', '"https://example.test/token"', 1)
        setup = r'''
          requests, invokes, outputs = {}, {}, {}
          tick, fail, closed = 0, false, 0
          local function iterator(t)
            local i=0; return function() i=i+1; if t[i] then return t[i][1],t[i][2] end end
          end
          package.preload.component = function() return {
            isAvailable=function() return true end,
            internet={isHttpEnabled=function() return true end, request=function(url,body)
              requests[#requests+1]={url=url,body=body}
              local data=url:match('/start$') and ('SESSION '..string.rep('a',32)) or 'OK'
              if url:match('/finish/') then data='OK '..string.rep('a',32)..' files' end
              local first=true
              return {finishConnect=function() return true end, response=function() return fail and 403 or 200 end,
                read=function() if first then first=false; return data else return nil end end,
                close=function() closed=closed+1 end}
            end},
            list=function() return iterator({{'node','bec_io_node'},{'rs','redstone'},{'tp','transposer'},
              {'3afdc4cf-04e3-4ae9-8be6-e753c23a249d','fluid_interface'}}) end,
            methods=function(a) return a=='node' and {getState=false} or (a=='rs' and {getOutput=false}
              or (a=='tp' and {getFluidInTank=false} or {getFluidsInNetwork=false,getCpus=false})) end,
            invoke=function(a,m,...)
              invokes[#invokes+1]=m
              if m=='getCpus' then
                local callback=setmetatable({}, {__call=function() cpuReads=cpuReads+1;return {item='test'} end})
                return {{name='busy',busy=true,cpu={activeItems=callback,pendingItems=callback,finalOutput=callback}}}
              end
              return m=='getState' and 'paused-immediate' or {}
            end
          } end
          package.preload.computer=function() return {address=function() return 'computer-1' end,
            uptime=function() tick=tick+.01; return tick end} end
          package.preload.serialization=function() return {serialize=function(v,pretty) assert(pretty==false); return 'data' end} end
          package.preload.filesystem=function() return {
            exists=function() return true end, isDirectory=function() return false end, size=function() return 4 end,
            concat=function(a,b) return a..'/'..b end,
            list=function(path) local names=path=='/home' and {{'bec_auto.lua'},{'bec_auto.journal.before-resume-30'},
              {'bec_cache.config'},{'bec_upload.lua'},{'personal.lua'}} or {{'recipe.dat'}}; return iterator(names) end
          } end
          io.open=function(path) return {read=function() return 'test' end, close=function() end} end
          cpuReads=0
          os.sleep=function() end
          print=function(text) outputs[#outputs+1]=text end
        '''
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(setup)
        lua.execute('assert(load(...))("full")', source)
        urls = [entry["url"] for entry in lua.globals().requests.values()]
        self.assertEqual(len(urls), 8)  # start, runtime, 4 files, report, finish
        self.assertTrue(any("before-resume-30" in url for url in urls))
        self.assertFalse(any("personal.lua" in url or "bec_upload.lua" in url for url in urls))
        self.assertIn("getState", list(lua.globals().invokes.values()))  # false method flag still callable
        self.assertIn("getFluidsInNetwork", list(lua.globals().invokes.values()))
        self.assertIn("getCpus", list(lua.globals().invokes.values()))
        self.assertEqual(lua.globals().cpuReads, 3)
        self.assertTrue(any("bec_cache.config" in url for url in urls))
        self.assertTrue(all(method.startswith("get") for method in lua.globals().invokes.values()))

        # Default recent mode keeps two newest backups across reset/resume families,
        # current programs and journals; it never opens old programs or recipes.
        recent = LuaRuntime(unpack_returned_tuples=True)
        recent.execute(setup + r'''
          require('filesystem').list=function(path)
            assert(path=='/home','recent mode must not scan recipes')
            local names={'bec_auto.lua','bec_ui.lua','bec_auto.lua.before-next-1',
              'bec_auto.journal','bec_auto.journal.previous','bec_cache.config',
              'bec_auto.journal.reset-1','bec_upload.lua','personal.lua'}
            for i=1,90 do names[#names+1]='bec_auto.journal.before-resume-'..i end
            local i=0;return function()i=i+1;return names[i]end
          end
          require('filesystem').lastModified=function(path)
            if path:match('reset%-1$')then return 1000 end
            return tonumber(path:match('(%d+)$')) or 0
          end
        ''')
        recent.execute(source)
        recent_urls = [entry['url'] for entry in recent.globals().requests.values()]
        self.assertEqual(len(recent_urls), 11)  # start, runtime, seven files, report, finish
        self.assertTrue(any('reset-1' in url for url in recent_urls))
        self.assertTrue(any('before-resume-90' in url for url in recent_urls))
        self.assertFalse(any('before-resume-89' in url or 'before-next-1' in url for url in recent_urls))
        self.assertFalse(any('recipe.dat' in url or 'personal.lua' in url for url in recent_urls))
        self.assertEqual(lua.globals().closed, len(urls))
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(setup)
        lua.execute('assert(load(...))("status")', source)
        urls = [entry["url"] for entry in lua.globals().requests.values()]
        self.assertEqual(len(urls), 5)  # start, runtime, config, report, finish
        self.assertTrue(any("bec_cache.config" in url for url in urls))
        self.assertFalse(any("before-resume-30" in url or "recipe.dat" in url for url in urls))
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(setup)
        lua.execute(r'''
          local c = require('component')
          local cellTp = '13070035-3a3f-4468-b896-1c084288fdc9'
          c.list=function()
            local entries={{cellTp,'transposer'},{'old-tp','transposer'},
              {'south-rs','redstone'},{'north-rs','redstone'},{'cw','me_cellworkbench'},
              {'3afdc4cf-04e3-4ae9-8be6-e753c23a249d','fluid_interface'}}
            local i=0;return function() i=i+1;if entries[i] then return table.unpack(entries[i]) end end
          end
          c.methods=function(a)
            if a==cellTp or a=='old-tp' then
              return {getInventoryName=false,getInventorySize=false,getStackInSlot=false,
                getFluidInTank=false,transferItem=false}
            elseif a=='cw' then return {hasCell=false,getRestriction=false,setRestriction=false}
            elseif a:match('rs$') then return {getOutput=false,setOutput=false}
            else return {getFluidsInNetwork=false,getCpus=false,getItemsInNetwork=false} end
          end
          slotReads, rsReads = 0, 0
          c.invoke=function(a,m,side,slot)
            invokes[#invokes+1]=m
            if m=='getInventoryName' then assert(a==cellTp);return 'test' end
            if m=='getInventorySize' then assert(a==cellTp);return side==0 and 3 or 12 end
            if m=='getStackInSlot' then
              assert(a==cellTp and (side==0 or side==2 or side==3))
              assert(slot>=1 and slot<=(side==0 and 3 or 12))
              slotReads=slotReads+1;return slot==1 and {name='digital_cell',size=1,hasTag=true} or nil
            end
            if m=='getOutput' then rsReads=rsReads+1;return 0 end
            if m=='hasCell' then return true end
            if m=='getRestriction' then return 1,30720 end
            error('Unexpected call: '..m)
          end
          require('filesystem').list=function(path)
            assert(path=='/home')
            local names={'bec_nanites.lua','bec_nanites.journal','bec_nanites.journal.previous',
              'bec_nanites_io.cfg','bec_nanites_io_test.lua','bec_nanites_io_test.journal',
              'bec_auto.lua','bec_auto.journal','bec_upload.lua'}
            local i=0;return function() i=i+1;return names[i] end
          end
        ''')
        lua.execute('assert(load(...))("ioport")', source)
        urls = [entry["url"] for entry in lua.globals().requests.values()]
        self.assertEqual(lua.globals().slotReads, 27)
        self.assertEqual(lua.globals().rsReads, 12)
        self.assertEqual(len(urls), 10)  # start, runtime, 6 bee files, report, finish
        self.assertTrue(any("bec_nanites.journal.previous" in url for url in urls))
        self.assertTrue(any("bec_nanites_io_test.journal" in url for url in urls))
        self.assertFalse(any("bec_auto" in url or "recipe.dat" in url for url in urls))
        self.assertNotIn("getCpus", list(lua.globals().invokes.values()))
        self.assertNotIn("getFluidsInNetwork", list(lua.globals().invokes.values()))
        self.assertTrue(all(method.startswith("get") or method == "hasCell"
                            for method in lua.globals().invokes.values()))
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(setup + "\nfail=true")
        with self.assertRaisesRegex(Exception, "HTTP 403"):
            lua.execute(source)
        self.assertEqual(lua.globals().closed, 1)
        self.assertEqual(len(lua.globals().invokes), 0)


if __name__ == "__main__":
    unittest.main()
