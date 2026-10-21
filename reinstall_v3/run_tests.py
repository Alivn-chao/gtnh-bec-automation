"""Rebuild V3 updater, run focused runtime/upgrade regressions and core scenarios."""
from pathlib import Path
import runpy
import sys
import unittest

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
sys.path[:0]=[str(ROOT/'work/lua_runtime'),str(HERE/'tests'),str(ROOT/'reinstall_v2/tests')]
runpy.run_path(str(HERE/'build_update.py'),run_name='__main__')
runpy.run_path(str(ROOT/'reinstall_v2/build_web.py'),run_name='__main__')
runpy.run_path(str(HERE/'build_cache_response_update.py'),run_name='__main__')
modules=['test_read_optimization','test_hive_inspection','test_stage_latency',
 'test_cell_io','test_cell_bridge','test_dynamic_nanites','test_completion_pause',
 'test_idle_cohort','test_two_recipe_pipeline','test_batch_stop','test_cache_management',
 'test_cache_partial','test_cache_recover','test_web_session','test_web_latency',
 'test_web_transport','test_performance','test_update','test_cache_response','test_cache_response_update','test_web_single_instance']
result=unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromNames(modules))
if not result.wasSuccessful():sys.exit(1)
runpy.run_path(str(ROOT/'reinstall_v2/tests/test_v2.py'),run_name='__main__')
