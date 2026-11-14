"""Inspect public catalogue proximity without merging distinct kinds of places."""
import hashlib
import json
import math
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def distance(a, b):
    lat1, lat2 = (math.radians(p['latitude']) for p in (a, b))
    dy = lat2 - lat1
    dx = math.radians(b['longitude'] - a['longitude'])
    h = math.sin(dy / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dx / 2) ** 2
    return 6371008.8 * 2 * math.asin(min(1, math.sqrt(h)))


def main():
    reference = ROOT / 'assets/catalogue/catalogue_reference.json'
    index_file = ROOT / 'assets/catalogue/road_sources.json'
    reference_points = json.loads(reference.read_text())['items']
    railway = []
    index = json.loads(index_file.read_text())
    for entry in index['departments']:
        path = ROOT / entry['asset']
        assert hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
        railway.extend(json.loads(path.read_text())['items'])
    radar_crossings = [p for p in reference_points if p['category_code'] == 'ETPN']
    matches, buckets = [], Counter()
    for radar in radar_crossings:
        closest = min(railway, key=lambda p: distance(radar, p))
        metres = distance(radar, closest)
        bucket = next((f'within_{n}m' for n in (10, 25, 50, 100) if metres <= n), 'beyond_100m')
        buckets[bucket] += 1
        matches.append({'radar_id': radar['id'], 'crossing_id': closest['id'],
                        'metres': round(metres, 2), 'bucket': bucket})
    report = {'reference_sha256': hashlib.sha256(reference.read_bytes()).hexdigest(),
              'railway_index_sha256': hashlib.sha256(index_file.read_bytes()).hexdigest(),
              'method': 'nearest_public_SNCF_reference_haversine',
              'buckets_are_disjoint': True, 'radar_crossings': len(radar_crossings),
              'railway_points': len(railway), 'nearest_distance_buckets': dict(sorted(buckets.items())),
              'automatic_merge': False,
              'interpretation': 'A railway crossing and a camera monitoring it remain different alerts. Proximity alone does not establish identity.',
              'pairs': matches}
    output = ROOT / 'data/catalogue/road-overlap.json'
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k:v for k,v in report.items() if k != 'pairs'}))


if __name__ == '__main__':
    main()
