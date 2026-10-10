import json
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
            list=function() return iterator({{'node','bec_io_node'},{'rs','redstone'},{'tp','transposer'}}) end,
            methods=function(a) return a=='node' and {getState=false} or (a=='rs' and {getOutput=false} or {getFluidInTank=false}) end,
            invoke=function(a,m,...) invokes[#invokes+1]=m; return m=='getState' and 'paused-immediate' or {} end
          } end
          package.preload.computer=function() return {address=function() return 'computer-1' end,
            uptime=function() tick=tick+.01; return tick end} end
          package.preload.serialization=function() return {serialize=function(v,pretty) assert(pretty==false); return 'data' end} end
          package.preload.filesystem=function() return {
            exists=function() return true end, isDirectory=function() return false end, size=function() return 4 end,
            concat=function(a,b) return a..'/'..b end,
            list=function(path) local names=path=='/home' and {{'bec_auto.lua'},{'bec_auto.journal.before-resume-30'},
              {'bec_upload.lua'},{'personal.lua'}} or {{'recipe.dat'}}; return iterator(names) end
          } end
          io.open=function(path) return {read=function() return 'test' end, close=function() end} end
          os.sleep=function() end
          print=function(text) outputs[#outputs+1]=text end
        '''
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(setup)
        lua.execute(source)
        urls = [entry["url"] for entry in lua.globals().requests.values()]
        self.assertEqual(len(urls), 7)  # start, runtime, 3 files, report, finish
        self.assertTrue(any("before-resume-30" in url for url in urls))
        self.assertFalse(any("personal.lua" in url or "bec_upload.lua" in url for url in urls))
        self.assertIn("getState", list(lua.globals().invokes.values()))  # false method flag still callable
        self.assertTrue(all(method.startswith("get") for method in lua.globals().invokes.values()))
        self.assertEqual(lua.globals().closed, len(urls))
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute(setup + "\nfail=true")
        with self.assertRaisesRegex(Exception, "HTTP 403"):
            lua.execute(source)
        self.assertEqual(lua.globals().closed, 1)
        self.assertEqual(len(lua.globals().invokes), 0)


if __name__ == "__main__":
    unittest.main()
