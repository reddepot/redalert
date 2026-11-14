"""Build inactive departmental SNCF catalogues from a pinned public export."""
import argparse
from collections import Counter
from datetime import datetime
import gzip
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlencode

ROOT = Path(__file__).resolve().parents[2]
PAGE = 'https://ressources.data.sncf.com/explore/dataset/liste-des-passages-a-niveau/'
PUBLIC_MOTOR_CLASSES = set(range(10, 22))
EXPORT_URL = 'https://ressources.data.sncf.com/api/explore/v2.1/catalog/datasets/liste-des-passages-a-niveau/exports/json?' + urlencode({'select': 'id_if,libelle,mnemo,obstacle,code_ligne,pk,x_wgs84,y_wgs84,diffr,saco_code_commune,saco_libelle_commune', 'order_by': 'id_if'})

def normalize(row, snapshot):
    match = re.fullmatch(r'CLASSE (\d{1,2})', str(row.get('mnemo', '')).strip())
    if not match or int(match[1]) not in PUBLIC_MOTOR_CLASSES:
        return None, 'not_primary_public_motor_crossing'
    code = str(row.get('saco_code_commune') or '').strip()
    if not re.fullmatch(r'\d{5}', code) or not 1 <= int(code[:2]) <= 95 or code[:2] == '20':
        return None, 'missing_or_noncontinental_commune'
    x, y = row.get('x_wgs84'), row.get('y_wgs84')
    if isinstance(x, bool) or isinstance(y, bool) or not isinstance(x, (int, float)) or not isinstance(y, (int, float)) or not (-5.6 <= x <= 8.4 and 42.2 <= y <= 51.2):
        return None, 'invalid_continental_coordinates'
    ident = str(row.get('id_if', ''))
    if not re.fullmatch(r'\d{1,30}', ident):
        raise ValueError('Invalid SNCF identifier')
    commune = re.sub(r'\s*\(\d{5}\)$', '', str(row.get('saco_libelle_commune') or '')).strip()
    name = ' '.join(str(row.get('libelle') or 'Passage à niveau').split())
    label = f'{code[:2]} · {name}' + (f' · {commune}' if commune else '')
    flag = str(row.get('diffr') or '').strip().upper()
    difficult = True if flag == 'OUI' else False if flag == 'NON' else None
    source = {'name': 'SNCF Réseau', 'record_id': ident,
              'url': PAGE + 'table/?refine.id_if=' + ident,
              'snapshot_at': snapshot, 'classification': f'Classe {int(match[1])}'}
    # Blank does not mean the crossing is suitable for a low-clearance vehicle.
    if difficult is not None:
        source['low_clearance_difficult'] = difficult
    return {'id': 'sncf:pn/' + ident, 'department': code[:2], 'label': label[:140],
            'latitude': y, 'longitude': x, 'category_code': 'SNCF_PN_LOW' if difficult else 'SNCF_PN',
            'armed': False, 'department_assignment': 'source_insee_commune', 'source': source}, None

def build(rows, metadata):
    meta = metadata['metas']['default']
    if len(rows) != meta['records_count']:
        raise ValueError('Export count differs from dataset metadata; acquire a coherent snapshot')
    snapshot = meta['data_processed']
    datetime.fromisoformat(snapshot)
    groups, excluded, candidates = {}, Counter(), {}
    for row in rows:
        item, reason = normalize(row, snapshot)
        if item is None:
            excluded[reason] += 1
            continue
        candidates.setdefault(item['id'], []).append(item)
    for ident, versions in candidates.items():
        if any(item != versions[0] for item in versions[1:]):
            excluded['ambiguous_identifier_rows'] += len(versions)
            continue
        excluded['duplicate_identical_rows'] += len(versions) - 1
        item = versions[0]
        groups.setdefault(item['department'], []).append(item)
    return groups, excluded, snapshot

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, default=ROOT/'data/catalogue/sncf-pn-20260218.json.gz')
    parser.add_argument('--metadata', type=Path, default=ROOT/'data/catalogue/sncf-pn-20260218-metadata.json')
    args = parser.parse_args()
    raw = gzip.decompress(args.input.read_bytes())
    metadata = json.loads(args.metadata.read_text())
    groups, excluded, snapshot = build(json.loads(raw), metadata)
    directory = ROOT/'assets/catalogue/railway'; directory.mkdir(parents=True, exist_ok=True)
    index = {'format': 'redalert-road-catalogues', 'version': 1,
        'source': {'name': 'SNCF Réseau', 'url': PAGE, 'snapshot_at': snapshot}, 'departments': []}
    for code, items in sorted(groups.items()):
        items.sort(key=lambda p: p['id'])
        if len(items) > 5000:
            raise ValueError('Department exceeds application import bound')
        catalogue = {'format': 'location-catalogue-preparation', 'version': 1,
                     'activation': 'disabled', 'items': items}
        path = directory/f'{code}.json'
        path.write_text(json.dumps(catalogue, ensure_ascii=False, indent=2)+'\n')
        index['departments'].append({'code': code, 'count': len(items),
            'low_clearance': sum(p['category_code'] == 'SNCF_PN_LOW' for p in items),
            'asset': f'assets/catalogue/railway/{code}.json',
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    (ROOT/'assets/catalogue/road_sources.json').write_text(json.dumps(index, ensure_ascii=False, indent=2)+'\n')
    report = {'data_processed': snapshot, 'source_page': PAGE, 'export_url': EXPORT_URL,
              'export_sha256': hashlib.sha256(raw).hexdigest(),
              'archive_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'metadata_sha256': hashlib.sha256(args.metadata.read_bytes()).hexdigest(),
              'input_rows': sum(len(v) for v in groups.values())+sum(excluded.values()),
              'output_rows': sum(len(v) for v in groups.values()),
              'departments': len(groups), 'low_clearance_rows': sum(d['low_clearance'] for d in index['departments']),
              'excluded': dict(excluded), 'department_assignment': 'source_insee_commune',
              'position_accuracy_per_point': None}
    (ROOT/'data/catalogue/sncf-provenance.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False))

if __name__ == '__main__':
    main()
