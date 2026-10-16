"""Only verified completed histories may be pruned; live evidence is retained."""
import unittest
from test_read_optimization import fixture

class StorageTests(unittest.TestCase):
 def test_retention_preserves_pending_current_and_unknown_files(self):
  l=fixture();l.execute(r'''
local fs=require('filesystem');fs.lastModified=function()return 0 end
fs.remove=function(path)s.files[path]=nil;return true end
local exists=fs.exists
fs.exists=function(p)if exists(p)then return true end;for path in pairs(s.files)do if path:sub(1,#p+1)==p..'/'then return true end end;return false end
fs.list=function(dir)
 local names={};for path in pairs(s.files)do
  local prefix=dir..'/';if path:sub(1,#prefix)==prefix and not path:sub(#prefix+1):find('/',1,true)then names[#names+1]=path:sub(#prefix+1)end
 end
 local i=0;return function()i=i+1;return names[i]end
end
for i=1,20 do C.write(C.path('state/node-1/production.journal.stopped-'..i),{stage='stopped',transfers={{ok=true}},requests={{state='done'}}})end
C.write(C.path('state/node-1/production.journal.stopped-99'),{stage='stopped',pending={count=1}})
C.write(C.path('state/node-1/production.journal'),{stage='moving'})
C.write(C.path('state/node-1/production.journal.previous'),{stage='moving'})
for i=1,10 do C.write(C.path('config.dat.hd.bak.'..i),cfg)end
s.files[C.path('unknown.log')]='keep'
local S=loadfile(C.path('lib/storage.lua'))()(C)
assert(S.prune(cfg)==25)
assert(s.files[C.path('state/node-1/production.journal.stopped-99')])
assert(s.files[C.path('state/node-1/production.journal')])
assert(s.files[C.path('state/node-1/production.journal.previous')])
assert(s.files[C.path('unknown.log')]=='keep')
assert(S.prune(cfg)==0)
''')
 def test_unreadable_capacity_fails_closed(self):
  l=fixture();l.execute("local S=loadfile(C.path('lib/storage.lua'))()(C);assert(not S.status().known and not S.status().ok)")

if __name__=='__main__':unittest.main()
