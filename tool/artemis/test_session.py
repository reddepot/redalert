"""Lease boundary checks: no Artemis import or Android access occurs here."""
from datetime import datetime, timezone
import unittest
from session import validate_lease, find_text_target, parse_preview_dump, stable_text_target
import json

class LeaseTest(unittest.TestCase):
    now = datetime(2026, 11, 12, 12, tzinfo=timezone.utc)

    def test_expired_or_missing_access_refused(self):
        for serial, deadline in [(None, None), ('test-device', None),
                ('test-device', '2026-11-12T11:59:59Z'),
                ('test-device', '2026-11-12T12:00:00Z')]:
            with self.assertRaises(ValueError):
                validate_lease(serial, deadline, self.now)

    def test_unbounded_or_ambiguous_access_refused(self):
        for deadline in ['2026-11-12T12:30:01Z', '2026-11-12T12:10:00']:
            with self.assertRaises(ValueError):
                validate_lease('test-device', deadline, self.now)

    def test_bounded_access_allowed(self):
        validate_lease('test-device', '2026-11-12T12:10:00Z', self.now)

class UiTargetTest(unittest.TestCase):
    def test_large_merged_card_cannot_impersonate_one_control(self):
        card = '<node content-desc="Intro&#10;Choisir une annonce&#10;Radar fixe&#10;Explication" bounds="[30,120][690,738]"/>'
        with self.assertRaises(ValueError):
            find_text_target('<hierarchy>'+card+'</hierarchy>', 'Radar fixe', 720, 1280)
        control = '<node content-desc="Choisir une annonce&#10;Radar fixe" bounds="[54,313][666,399]"/>'
        self.assertEqual(find_text_target('<hierarchy>'+card+control+'</hierarchy>', 'Radar fixe', 720, 1280), (500, 278))
    def test_moving_target_is_refused_until_two_reads_agree(self):
        first = '<hierarchy><node text="A" bounds="[0,100][100,150]"/></hierarchy>'
        moved = first.replace('[0,100][100,150]', '[0,200][100,250]')
        with self.assertRaises(ValueError):
            stable_text_target(first, moved, 'A', 1000, 1000)
        self.assertEqual(stable_text_target(moved, moved, 'A', 1000, 1000), (50, 225))
    def test_exact_visible_label_relocates_without_reusing_old_coordinates(self):
        xml = '<hierarchy><node text="Écouter : Ralentisseur" bounds="[100,600][900,700]"/></hierarchy>'
        self.assertEqual(find_text_target(xml, 'Écouter : Ralentisseur', 1000, 1000), (500, 650))
        moved = xml.replace('[100,600][900,700]', '[100,300][900,400]')
        self.assertEqual(find_text_target(moved, 'Écouter : Ralentisseur', 1000, 1000), (500, 350))
    def test_wrong_or_ambiguous_category_refuses_action(self):
        for xml in ['<hierarchy><node text="Écouter : Radar fixe" bounds="[0,0][100,50]"/></hierarchy>',
                    '<hierarchy><node text="Écouter : Ralentisseur" bounds="[0,0][100,50]"/><node text="Écouter : Ralentisseur" bounds="[0,100][100,150]"/></hierarchy>']:
            with self.assertRaises(ValueError):
                find_text_target(xml, 'Écouter : Ralentisseur', 1000, 1000)
    def test_offscreen_or_disabled_node_refuses_action(self):
        for node in ['text="A" bounds="[0,0][0,0]"', 'text="A" bounds="[0,0][10,10]" enabled="false"']:
            with self.assertRaises(ValueError):
                find_text_target('<hierarchy><node '+node+'/></hierarchy>', 'A', 1000, 1000)

class VoiceDumpTest(unittest.TestCase):
    def dump(self, **values):
        return 'Unrelated service data\nRedAlertVoicePreview=' + json.dumps({
            'schemaVersion': 1, 'state': 'completed', 'asset': 'highSpeedBump_300',
            'startedAtMillis': 1000, 'finishedAtMillis': 3500,
            'startedWhileScreenOff': True, 'finishedWhileScreenOff': True, **values})

    def test_exports_only_bounded_test_metadata(self):
        result = parse_preview_dump(self.dump(label='do-not-export', latitude=0, speed=12))
        self.assertTrue(result['startedWhileScreenOff'])
        self.assertTrue(result['finishedWhileScreenOff'])
        self.assertEqual(result['asset'], 'highSpeedBump_300')
        for field in ['label', 'latitude', 'speed']:
            self.assertNotIn(field, result)

    def test_missing_or_duplicate_probe_refuses_to_claim_success(self):
        for raw in ['no probe', self.dump() + '\n' + self.dump(), 'RedAlertVoicePreview=[]']:
            with self.assertRaises(ValueError): parse_preview_dump(raw)

    def test_invalid_fields_or_versions_are_not_exported(self):
        for values in [{'schemaVersion': 2}, {'asset': '../unknown'}, {'state': 'invented'},
                       {'finishedAtMillis': True}, {'startedWhileScreenOff': 'true'},
                       {'failureCode': 'unexpected private text'}]:
            with self.assertRaises(ValueError): parse_preview_dump(self.dump(**values))

    def test_idle_and_known_failure_remain_distinct_from_completion(self):
        idle = parse_preview_dump('RedAlertVoicePreview={"schemaVersion":1,"state":"idle"}')
        self.assertEqual(idle['state'], 'idle'); self.assertIsNone(idle['asset'])
        failure = parse_preview_dump(self.dump(state='error', failureCode='audio_focus_lost:-2',
                                               finishedWhileScreenOff=None))
        self.assertEqual(failure['failureCode'], 'audio_focus_lost:-2')
        self.assertIsNone(failure['finishedWhileScreenOff'])

if __name__ == '__main__':
    unittest.main()
