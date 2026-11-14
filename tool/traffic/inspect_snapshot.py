"""Inspect a local public DATEX II snapshot; never labels records as live alerts."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

NS = 'http://datex2.eu/schema/2/2_0'
XSI = 'http://www.w3.org/2001/XMLSchema-instance'


def stamp(text):
    if not text:
        return None
    value = datetime.fromisoformat(text.replace('Z', '+00:00'))
    if value.tzinfo is None:
        raise ValueError('A source timestamp without timezone is not usable')
    return value.astimezone(timezone.utc)


def value(node, name):
    found = node.find('.//{' + NS + '}' + name)
    return None if found is None else found.text


def inspect(data, now):
    if len(data) > 8 * 1024 * 1024:
        raise ValueError('Snapshot exceeds 8 MiB')
    text = data.decode('utf8')
    if '<!DOCTYPE' in text.upper() or '<!ENTITY' in text.upper():
        raise ValueError('DTD and entities are not accepted')
    if now.tzinfo is None:
        raise ValueError('Inspection time requires timezone')
    root = ET.fromstring(text)
    payloads = list(root.iter('{' + NS + '}payloadPublication'))
    if len(payloads) != 1:
        raise ValueError('One DATEX II payload is required')
    payload = payloads[0]
    published = stamp(value(payload, 'publicationTime'))
    if published is None:
        raise ValueError('Publication time is required')
    age = (now - published).total_seconds()
    if age < -120:
        raise ValueError('Future publication; source clock must be verified')
    records = list(payload.iter('{' + NS + '}situationRecord'))
    if len(records) > 5000:
        raise ValueError('Record inspection bound exceeded')
    types, windows, updates = Counter(), Counter(), []
    for record in records:
        kind = record.get('{' + XSI + '}type', 'unknown').split(':')[-1]
        types[kind] += 1
        start = stamp(value(record, 'overallStartTime'))
        end = stamp(value(record, 'overallEndTime'))
        updated = stamp(value(record, 'situationRecordVersionTime'))
        if updated is not None:
            updates.append(updated)
        if value(record, 'validityStatus') == 'suspended':
            windows['suspended'] += 1
        elif start is not None and end is not None and end < start:
            windows['invalid_interval'] += 1
        elif end is not None and end <= now:
            windows['past_overall_end'] += 1
        elif start is not None and start > now:
            windows['future_overall_start'] += 1
        elif any(n.tag.split('}')[-1] in {
                'validPeriod', 'recurringTimePeriodOfDay', 'recurringDayWeekMonthPeriod',
                'exceptionPeriod'} for n in record.iter()):
            windows['schedule_not_interpreted'] += 1
        elif start is None:
            windows['missing_overall_start'] += 1
        else:
            windows['within_overall_window_only'] += 1
    return {
        'sha256': hashlib.sha256(data).hexdigest(),
        'inspected_at': now.astimezone(timezone.utc).isoformat(),
        'publication_time': published.isoformat(),
        'publication_age_seconds': round(age),
        'update_method': value(root, 'updateMethod'),
        'snapshot_sequence': value(payload, 'feedType'),
        'records': len(records), 'types': dict(sorted(types.items())),
        'validity_windows': dict(sorted(windows.items())),
        'oldest_record_version': min(updates).isoformat() if updates else None,
        'newest_record_version': max(updates).isoformat() if updates else None,
        'operational_alerts_validated': False,
        'note': 'Outer validity windows do not establish current road conditions or resolve schedules, direction, geometry, updates and cancellations.'
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('--at', help='ISO 8601 inspection time; defaults to current UTC')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    now = stamp(args.at) if args.at else datetime.now(timezone.utc)
    with args.snapshot.open('rb') as source:
        data = source.read(8 * 1024 * 1024 + 1)
    report = json.dumps(inspect(data, now), ensure_ascii=False, indent=2) + '\n'
    if args.output:
        args.output.write_text(report)
    else:
        print(report, end='')


if __name__ == '__main__':
    main()
