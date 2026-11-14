import unittest
from build_railway import build, normalize

class RailwayTest(unittest.TestCase):
    def row(self, **changes):
        return {'id_if':'1','mnemo':'CLASSE 17','saco_code_commune':'86194',
                'saco_libelle_commune':'Synthetic (86194)', 'libelle':'PN 1',
                'x_wgs84':.3, 'y_wgs84':46.5, 'diffr':None, **changes}
    def test_only_public_motor_primary_classes(self):
        for code in [0,31,32,41,46,99]:
            self.assertIsNone(normalize(self.row(mnemo=f'CLASSE {code}'),'2026-01-01')[0])
    def test_unknown_difficulty_is_not_a_negative_guarantee(self):
        normal,_=normalize(self.row(),'2026-01-01')
        difficult,_=normalize(self.row(diffr='OUI'),'2026-01-01')
        self.assertNotIn('low_clearance_difficult',normal['source'])
        self.assertTrue(difficult['source']['low_clearance_difficult'])
    def test_ambiguous_ids_excluded_and_identical_duplicates_collapsed(self):
        meta={'metas':{'default':{'records_count':2,'data_processed':'2026-01-01'}}}
        groups,excluded,_=build([self.row(),self.row(x_wgs84=.3002)],meta)
        self.assertFalse(groups);self.assertEqual(excluded['ambiguous_identifier_rows'],2)
        groups,excluded,_=build([self.row(),self.row()],meta)
        self.assertEqual(len(groups['86']),1);self.assertEqual(excluded['duplicate_identical_rows'],1)
    def test_bad_or_noncontinental_communes_and_coordinates(self):
        for row in [self.row(saco_code_commune='2A001'),self.row(saco_code_commune=None),
                    self.row(saco_code_commune='97101'),self.row(x_wgs84=float('nan'))]:
            self.assertIsNone(normalize(row,'2026-01-01')[0])
if __name__=='__main__':unittest.main()
