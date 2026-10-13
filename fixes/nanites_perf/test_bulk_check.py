import unittest
from pathlib import Path
from test_perf import fixture

SCRIPT=Path(__file__).with_name('check_bulk.lua').read_text(encoding='utf-8')
PATH='/home/bec_nanites_bulk_check.txt'

class BulkCheckTests(unittest.TestCase):
    def setup_probe(self):
        lua=fixture()
        lua.execute(r'''
          local original=io.open
          io.open=function(p,m)
            if p=='/home/bec_nanites_bulk_check.txt' and m=='w' then
              return {write=function(_,s)files[p]=s;return true end,
                flush=function()return true end,close=function()end}
            end
            return original(p,m)
          end
          local c=require('component');local originalInvoke=c.invoke
          c.invoke=function(a,m,...)
            assert(m~='transferItem' and m~='setOutput','read-only probe attempted mutation')
            return originalInvoke(a,m,...)
          end
        ''')
        return lua

    def run_probe(self,lua):
        lua.execute(SCRIPT)
        self.assertEqual(lua.globals().moves,0)
        self.assertEqual(lua.globals().highs,0)
        self.assertEqual(lua.globals().files['/home/bec_auto.journal'],'production-record')
        return lua.globals().files[PATH]

    def test_false_method_is_supported_and_current_guards_are_reported(self):
        report=self.run_probe(self.setup_probe())
        self.assertIn('getAllStacks method: false',report)
        self.assertIn('count-match=true; all-keys-in-1..size=true',report)
        self.assertIn('occupied=2 missing-cell-metadata=0',report)

    def test_zero_based_realistic_snapshot_reports_guard_rejection(self):
        lua=self.setup_probe()
        lua.execute(r'''
          local c=require('component');local original=c.invoke
          c.invoke=function(a,m,...)
            local r=original(a,m,...)
            if m=='getAllStacks' then
              local all=r.getAll;r.getAll=function()
                local result={};for k,v in pairs(all())do result[k-1]=v end;return result
              end
            end
            return r
          end
        ''')
        report=self.run_probe(lua)
        self.assertIn('numericMin=0 numericMax=242',report)
        self.assertIn('count-match=true; all-keys-in-1..size=false',report)
        self.assertIn('slot 1 bulk[slot-1]:',report)

    def test_incomplete_metadata_is_counted(self):
        lua=self.setup_probe();lua.execute('missingMetadata=true')
        self.assertIn('occupied=2 missing-cell-metadata=2',self.run_probe(lua))

    def test_reader_error_still_reports_physical_samples(self):
        lua=self.setup_probe()
        lua.execute(r'''
          local c=require('component');local original=c.invoke
          c.invoke=function(a,m,...)
            local r=original(a,m,...)
            if m=='getAllStacks'then r.getAll=function()error('unsupported reader')end end
            return r
          end
        ''')
        report=self.run_probe(lua)
        self.assertIn('reader.getAll(): ERROR',report)
        self.assertIn('getStackInSlot(0,1): OK',report)
        self.assertIn('SIDE 3',report)

if __name__=='__main__':unittest.main()
