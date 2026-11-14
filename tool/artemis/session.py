"""One reviewed Artemis action at a time. Defaults to an offline mock device."""
import argparse
import asyncio
import base64
from datetime import datetime, timezone
import ipaddress
import json
import os
import re
import xml.etree.ElementTree as ET
from pathlib import Path
import socket
import subprocess
import sys

PIN = '351ca8422f7b5b54e80a9c1ce03a222e02415b6b'
ROOT = Path(__file__).resolve().parents[2]


def validate_lease(serial, lease_until, now=None):
    # Validate before imports, ADB enumeration or any Android interaction.
    now = now or datetime.now(timezone.utc)
    if not serial or not lease_until:
        raise ValueError('Explicit device serial and a renewed access deadline are required.')
    deadline = datetime.fromisoformat(lease_until.replace('Z', '+00:00'))
    if deadline.tzinfo is None:
        raise ValueError('Access deadline must include its timezone.')
    remaining = (deadline - now).total_seconds()
    if not 0 < remaining <= 1800:
        raise ValueError('Access deadline expired or exceeds 30 minutes.')
    return deadline


def find_text_target(xml, expected, width, height):
    if len(xml) > 4 * 1024 * 1024:
        raise ValueError('UI hierarchy exceeds the inspection bound; no action performed.')
    start, end = xml.find('<hierarchy'), xml.rfind('</hierarchy>')
    if start < 0 or end < start:
        raise ValueError('Android UI hierarchy is unavailable; no action performed.')
    expected = ' '.join(expected.split())
    if not expected: raise ValueError('An explicit UI label is required.')
    matches = set()
    for node in ET.fromstring(xml[start:end + len('</hierarchy>')]).iter('node'):
        if node.get('enabled', 'true') == 'false':
            continue
        labels = []
        for key in ('text', 'content-desc'):
            parts = node.get(key, '').splitlines()
            # A merged card is not a precise physical tap target for one line.
            if len(parts) <= 2:
                labels.extend(parts)
        if not any(' '.join(label.split()) == expected for label in labels):
            continue
        box = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
        if not box:
            continue
        x1, y1, x2, y2 = map(int, box.groups())
        if 0 <= x1 < x2 <= width and 0 <= y1 < y2 <= height:
            matches.add((x1, y1, x2, y2))
    if len(matches) != 1:
        raise ValueError('Expected UI text is missing or ambiguous; no action performed.')
    x1, y1, x2, y2 = matches.pop()
    return round((x1 + x2) * 500 / width), round((y1 + y2) * 500 / height)


def parse_preview_dump(raw):
    # Ignore all unrelated dumpsys output, which can contain private app data.
    if len(raw) > 128 * 1024:
        raise ValueError('Voice diagnostic exceeds the inspection bound.')
    lines = [line.strip().removeprefix('RedAlertVoicePreview=')
             for line in raw.splitlines() if line.strip().startswith('RedAlertVoicePreview=')]
    if len(lines) != 1:
        raise ValueError('Voice diagnostic unavailable in this app/service state.')
    try:
        record = json.loads(lines[0])
    except (ValueError, TypeError):
        raise ValueError('Voice diagnostic is not valid JSON.') from None
    if not isinstance(record, dict) or type(record.get('schemaVersion')) is not int or record['schemaVersion'] != 1:
        raise ValueError('Unsupported voice diagnostic version.')
    if not isinstance(record.get('state'), str) or record.get('state') not in {
            'idle', 'scheduled', 'preparing', 'playing', 'completed', 'error', 'cancelled'}:
        raise ValueError('Invalid voice diagnostic state.')
    types = {'fixedCamera', 'redLightCamera', 'averageSpeedCamera', 'levelCrossing',
             'levelCrossingLowClearance', 'highSpeedBump', 'dangerZone', 'sharpTurn',
             'rumbleStrip', 'roadDip', 'roadNarrowing', 'steepDescent', 'roadWorks',
             'trafficJam', 'other'}
    asset = record.get('asset')
    if asset is not None and (not isinstance(asset, str) or asset not in {kind + '_300' for kind in types}):
        raise ValueError('Unexpected test asset; diagnostic not exported.')
    safe = {'schemaVersion': 1, 'state': record['state'], 'asset': asset}
    for key in ('scheduledForMillis', 'startedAtMillis', 'finishedAtMillis'):
        number = record.get(key)
        if number is not None and (type(number) is not int or not 0 <= number < 2 ** 63):
            raise ValueError('Invalid voice diagnostic timestamp.')
        safe[key] = number
    for key in ('startedWhileScreenOff', 'finishedWhileScreenOff'):
        flag = record.get(key)
        if flag is not None and type(flag) is not bool:
            raise ValueError('Invalid voice diagnostic screen flag.')
        safe[key] = flag
    reason = record.get('failureCode')
    if reason is not None and (not isinstance(reason, str) or not re.fullmatch(
            r'(?:unavailable|cancelled|user_cancelled|view_disposed|activity_finished|'
            r'countdown_expired|not_available|focus_refused|preparation_expired|start_failure|'
            r'asset_unavailable|timeout|audio_focus_lost:-[123]|media_error:-?\d{1,12}:-?\d{1,12})', reason)):
        raise ValueError('Unexpected diagnostic reason; not exported.')
    safe['failureCode'] = reason
    return safe


def stable_text_target(first, second, expected, width, height):
    initial = find_text_target(first, expected, width, height)
    final = find_text_target(second, expected, width, height)
    if initial != final:
        raise ValueError('UI target moved between inspections; no action performed.')
    return final


def prepare(checkout, physical, adb_port=5037):
    head = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    if head != PIN:
        raise ValueError('Artemis pin differs; inspect the upgrade first.')
    for name in list(os.environ):
        if any(part in name for part in ['API_KEY', 'AUTH_TOKEN', 'REDAPI', 'OPENROUTER', 'LANGSMITH', 'LANGCHAIN']):
            os.environ.pop(name, None)
    os.environ.update({
        'ARTEMIS_APP_DIR': str(ROOT / 'build/artemis-validation/runtime'),
        'ARTEMIS_KEEP_DEVICE_AWAKE': 'false',
        'ARTEMIS_CLOUD_MODE': '0',
        'ARTEMIS_MOCK_DRIVER': '0' if physical else '1',
        'ADB_HOST': '127.0.0.1', 'ADB_PORT': str(adb_port),
        'ADB_SERVER_SOCKET': f'tcp:127.0.0.1:{adb_port}',
        'DO_NOT_TRACK': '1', 'ANONYMIZED_TELEMETRY': 'false',
        'LANGSMITH_TRACING': 'false', 'LANGCHAIN_TRACING_V2': 'false',
    })
    original_connect = socket.socket.connect

    def guarded_connect(sock, address):
        # Only the already running local ADB server may be reached. No OCR,
        # model, telemetry or remote ADB endpoint is used by this process.
        if physical and isinstance(address, tuple) and address[1] == adb_port:
            try:
                if ipaddress.ip_address(address[0]).is_loopback:
                    return original_connect(sock, address)
            except ValueError:
                pass
        raise RuntimeError('External network is disabled in the RedAlert Artemis adapter.')
    socket.socket.connect = guarded_connect
    sys.path.insert(0, str(checkout.resolve()))


async def run(args):
    if not 1024 <= args.adb_port <= 65535:
        raise ValueError('ADB port must be in 1024..65535.')
    if args.action in ('tap', 'swipe') and (args.x is None or args.y is None or
            not 0 <= args.x <= 1000 or not 0 <= args.y <= 1000):
        raise ValueError('Tap requires normalized x/y coordinates in 0..1000.')
    if args.action == 'swipe' and (args.end_x is None or args.end_y is None or
            not 0 <= args.end_x <= 1000 or not 0 <= args.end_y <= 1000):
        raise ValueError('Swipe requires normalized end coordinates in 0..1000.')
    if args.action == 'tap-text' and (not args.execute or not args.text or len(args.text) > 160):
        raise ValueError('tap-text requires an executing device and a bounded exact UI label.')
    if args.action == 'voice-status' and not args.execute:
        raise ValueError('voice-status requires an explicitly selected executing device.')
    if args.execute:
        deadline = validate_lease(args.serial, args.lease_until)
        minimum = 20 if args.action == 'tap-text' else 12
        if args.action in ('tap-text', 'voice-status') and (deadline - datetime.now(timezone.utc)).total_seconds() < minimum:
            raise ValueError('Not enough access time for a bounded UI inspection.')
    prepare(args.checkout, args.execute, args.adb_port)
    from artemis.mcp.actuators.adb import AdbActuator
    from artemis.mcp.actuators.mock import MockActuator
    from artemis.mcp.action_manifest import validate_actuator
    if args.execute:
        from adbutils import AdbClient
        from artemis.context import ArtemisContext, DeviceContext, DevicePlatform
        from artemis.platform import platform
        client = AdbClient(host='127.0.0.1', port=args.adb_port)
        device = client.device(serial=args.serial)
        if device.get_state() != 'device':
            raise RuntimeError('Requested device is unavailable.')
        if args.action == 'voice-status':
            raw = await asyncio.to_thread(device.shell,
                'dumpsys activity service com.zaifears.locreminder.catalogue/com.zaifears.locreminder.LocationWatchService', timeout=8)
            validate_lease(args.serial, args.lease_until)
            print(json.dumps({'preview': parse_preview_dump(raw), 'device_execution': True,
                              'model_calls': 0, 'screen_capture': False}))
            return
        image = device.screenshot()
        width, height = image.size
        ctx = ArtemisContext(
            trace_id='redalert-local-validation', adb_client=client,
            # No UI helper, OCR, recordings or automatic device preparation.
            device=DeviceContext(host_platform=platform.os_type.name,
                mobile_platform=DevicePlatform.ANDROID, device_id=args.serial,
                device_width=width, device_height=height))
        actuator = AdbActuator(ctx)
        validate_lease(args.serial, args.lease_until)
    else:
        actuator = MockActuator()
    validate_actuator(actuator)
    if args.action == 'observe':
        encoded = await actuator.take_screenshot()
        from PIL import Image
        from io import BytesIO
        image = Image.open(BytesIO(base64.b64decode(encoded)))
        # Artemis can silently return a 1x1 fallback on capture failure.
        if image.width < 100 or image.height < 100:
            raise RuntimeError('Capture unavailable; fallback image is not evidence.')
        output = ROOT / 'build/artemis-validation/private/observation.png'
        output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        image.save(output)
        output.chmod(0o600)
        print(json.dumps({'capture': str(output), 'device_execution': args.execute,
                          'model_calls': 0, 'ui_hierarchy': False}))
        return
    if args.action == 'tap-text':
        # Built-in Android tool only: no APK, accessibility helper, OCR or saved XML.
        xml = await asyncio.to_thread(device.shell, 'uiautomator dump /dev/tty', timeout=8)
        await asyncio.sleep(0.2)
        latest = await asyncio.to_thread(device.shell, 'uiautomator dump /dev/tty', timeout=8)
        x, y = stable_text_target(xml, latest, args.text, width, height)
        validate_lease(args.serial, args.lease_until)
        result = await actuator.click(x, y)
    elif args.action == 'tap':
        result = await actuator.click(args.x, args.y)
    elif args.action == 'swipe':
        result = await actuator.swipe((args.x, args.y), (args.end_x, args.end_y))
    else:
        result = await actuator.press_key('back')
    if not result.ok:
        raise RuntimeError('Android action was not completed; no success is inferred.')
    print(json.dumps({'result': result.model_dump(mode='json'),
        'device_execution': args.execute, 'model_calls': 0, 'host_keep_awake': False}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', type=Path, required=True)
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--serial')
    parser.add_argument('--text', help='Exact visible UI label for tap-text')
    parser.add_argument('--adb-port', type=int, default=5037)
    parser.add_argument('--lease-until', help='New user-authorized deadline, ISO 8601 with timezone')
    parser.add_argument('action', choices=['observe', 'tap', 'tap-text', 'swipe', 'back', 'voice-status'])
    parser.add_argument('--x', type=int)
    parser.add_argument('--y', type=int)
    parser.add_argument('--end-x', type=int)
    parser.add_argument('--end-y', type=int)
    args = parser.parse_args()
    try:
        asyncio.run(run(args))
    except (ValueError, RuntimeError) as error:
        raise SystemExit(str(error)) from None
    except Exception:
        raise SystemExit('Android action failed; no success is inferred. Inspect the local transport.') from None

if __name__ == '__main__':
    main()
