import unittest
from datetime import datetime, timezone
from inspect_snapshot import inspect

NOW = datetime(2026, 11, 13, 5, tzinfo=timezone.utc)


def snapshot(records='', published='2026-11-13T05:00:00Z'):
    return f'''<root xmlns:d="http://datex2.eu/schema/2/2_0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <d:updateMethod>snapshot</d:updateMethod><d:payloadPublication>
    <d:publicationTime>{published}</d:publicationTime><d:feedType>100</d:feedType>
    <d:situation>{records}</d:situation></d:payloadPublication></root>'''.encode()


def record(start='2026-11-01T00:00:00Z', end=None, extra=''):
    return '<d:situationRecord xsi:type="d:MaintenanceWorks"><d:validity>' + (
        '<d:validityTimeSpecification><d:overallStartTime>' + start + '</d:overallStartTime>'
        + (f'<d:overallEndTime>{end}</d:overallEndTime>' if end else '')
        + extra + '</d:validityTimeSpecification></d:validity></d:situationRecord>')


class SnapshotTest(unittest.TestCase):
    def test_new_publication_does_not_make_expired_record_current(self):
        r = inspect(snapshot(record(end='2025-11-01T00:00:00Z')), NOW)
        self.assertEqual(r['publication_age_seconds'], 0)
        self.assertEqual(r['validity_windows'], {'invalid_interval': 1})
        r = inspect(snapshot(record(start='2025-10-01T00:00:00Z', end='2025-11-01T00:00:00Z')), NOW)
        self.assertEqual(r['validity_windows'], {'past_overall_end': 1})
        self.assertFalse(r['operational_alerts_validated'])

    def test_overall_window_does_not_resolve_a_recurring_schedule(self):
        r = inspect(snapshot(record(extra='<d:validPeriod><d:recurringTimePeriodOfDay/></d:validPeriod>')), NOW)
        self.assertEqual(r['validity_windows'], {'schedule_not_interpreted': 1})

    def test_future_suspended_and_outer_window_remain_distinct(self):
        records = record(start='2027-01-01T00:00:00Z') + record() + record(extra='<d:validityStatus>suspended</d:validityStatus>')
        r = inspect(snapshot(records), NOW)
        self.assertEqual(r['validity_windows'], {'future_overall_start': 1, 'suspended': 1, 'within_overall_window_only': 1})
        self.assertEqual(r['records'], 3)

    def test_invalid_source_time_or_entities_are_refused(self):
        for data in [snapshot(published='2026-11-14T00:00:00Z'), snapshot(published='2026-11-13T05:00:00'),
                     b'<!DOCTYPE x [<!ENTITY a "x">]><root/>', b'<root/>']:
            with self.assertRaises(ValueError):
                inspect(data, NOW)


if __name__ == '__main__':
    unittest.main()
