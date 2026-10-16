"""Two distinct registered inputs, actual Lua core, clocked hardware model."""
import unittest
from simulate_two_recipes import run
class PipelineSimulationTests(unittest.TestCase):
 def test_two_outputs_with_v2_recipe_directory(self):
  r=run();self.assertIsNone(r['error']);self.assertAlmostEqual(r['total_seconds'],49.15,places=2)
  self.assertEqual([x['item']for x in r['outputs']],['simulation:product_a','simulation:product_b'])
  self.assertEqual(len([e for e in r['events']if e['kind']=='disk-transfer']),6)
  self.assertEqual(len([e for e in r['events']if e['kind']=='filter-written']),2)
 def test_controlled_inputs_with_assumed_one_ms_component_delay(self):
  r=run(latency_ms=1,controlled_input=True);self.assertIsNone(r['error']);self.assertTrue(r['second_product_output'])
  self.assertGreater(r['total_seconds'],49.15)
 def test_rapid_next_input_waits_for_work_permission(self):
  r=run(latency_ms=1);self.assertIsNone(r['error']);self.assertTrue(r['healthy_completion'])
  self.assertEqual(len(r['outputs']),2)
  self.assertTrue(any(e['kind']=='node-work-allowed'for e in r['events']))
 def test_original_default_directory_failure_is_recorded(self):
  r=run(baseline=True,force_v2_directory=True);self.assertIsNotNone(r['error']);self.assertFalse(r['second_product_output'])
if __name__=='__main__':unittest.main()
