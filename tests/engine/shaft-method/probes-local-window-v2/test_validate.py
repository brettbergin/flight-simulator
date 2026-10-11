"""Prospective offline validator tamper tests, not numerical reference generation."""
import copy,json,tempfile,unittest
from pathlib import Path
import validate as v
class ValidatorTamperTests(unittest.TestCase):
    def accepted(self):
        case={'request_id':'K01_demo','group_id':'K01','kind':'K','expected':{'status':'advance','fields':{'w_bits':'3ff0000000000000','hold':False,'stop':False,'source_event':False}}}
        row={'id':'K01_demo','kind':'K','rejected':False,'w_bits':'3ff0000000000000','hold':False,'stop':False,'source_event':False,'remaining':{'n':{'sign':1,'exponent':0,'limbs_le':[1]},'d':{'sign':1,'exponent':0,'limbs_le':[1]}}}
        return case,row
    def test_exact_row_then_wrong_id_rejected(self):
        c,r=self.accepted();v.compare_native([c],[r]);r['id']='K02_wrong'
        with self.assertRaises(ValueError):v.compare_native([c],[r])
    def test_bool_integer_substitution_rejected(self):
        c,r=self.accepted();r['hold']=0
        with self.assertRaises(ValueError):v.compare_native([c],[r])
    def test_generic_exception_never_expected_rejection(self):
        c={'request_id':'R05_demo','group_id':'R05','kind':'G','expected':{'status':'reject','reason':'coupled shaft: exact dyadic capacity'}}
        r={'id':'R05_demo','kind':'G','rejected':True,'reason':'Malformed request'}
        with self.assertRaises(ValueError):v.compare_native([c],[r])
    def test_missing_independent_field_rejected(self):
        c,r=self.accepted();del c['expected']['fields']['stop']
        with self.assertRaises(ValueError):v.compare_native([c],[r])
    def test_wrong_exact_stop_remainder_rejected(self):
        c,r=self.accepted();c['expected']['status']='stop';c['expected']['fields'].update(w_bits='0000000000000000',stop=True)
        c['expected']['remaining']={'lo':'1/4','hi':'1/4'};r.update(w_bits='0000000000000000',stop=True)
        r['remaining']['n']['exponent']=-2;v.compare_native([c],[r]);r['remaining']['n']['exponent']=-1
        with self.assertRaises(ValueError):v.compare_native([c],[r])
    def test_interval_cannot_cover_nonfinite_or_outside_value(self):
        names=['c0_bits','c1_bits','c2_bits','c3_bits']
        c={'request_id':'C05_demo','group_id':'C05','kind':'L','expected':{'status':'coefficients','intervals':{k:{'lo':'1/1','hi':'1/1'} for k in names}}}
        r={'id':'C05_demo','kind':'L','rejected':False,**{k:'3ff0000000000000' for k in names}}
        v.compare_native([c],[r]);r['c0_bits']='3ff0000000000001'
        with self.assertRaises(ValueError):v.compare_native([c],[r])
        r['c0_bits']='7ff0000000000000'
        with self.assertRaises(ValueError):v.compare_native([c],[r])
    def test_interval_cannot_replace_exact_kernel_floor(self):
        c,r=self.accepted();del c['expected']['fields']['w_bits'];c['expected']['intervals']={'w_bits':{'lo':'1','hi':'2'}}
        with self.assertRaises(ValueError):v.compare_native([c],[r])
    def test_widened_remainder_rejected(self):
        c,r=self.accepted();c['expected']['status']='stop';c['expected']['remaining']={'lo':'0','hi':'2'}
        with self.assertRaises(ValueError):v.compare_native([c],[r])
    def test_request_bytes_are_canonical(self):
        c={'request_id':'K01_demo','kind':'K','request_tokens':['0','1']}
        self.assertEqual(v.request_bytes([c]),b'K01_demo K 0 1\n')
    def test_duplicate_json_keys_rejected(self):
        with self.assertRaises(ValueError):json.loads('{"id":"a","id":"b"}',object_pairs_hook=v.unique)
    def test_extra_output_field_rejected(self):
        c,r=self.accepted();r['invented_assist']=True
        with self.assertRaises(ValueError):v.compare_native([c],[r])
if __name__=='__main__':unittest.main()
