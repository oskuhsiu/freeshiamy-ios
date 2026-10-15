#!/usr/bin/env python3
"""Correlate the one live PID probe with the AX request and installed bundle."""
import datetime as dt
import importlib.util
import json
import pathlib
import re
import sys

spec = importlib.util.spec_from_file_location('activation_observer', pathlib.Path(__file__).with_name('observe-ipad-keyboard-activation.py'))
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)
BUNDLE = 'osku.me.freeshiamyios.keyboard'
UUID = r'([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12})'
REGISTER = re.compile(r'\[u ' + UUID + r'\].*?\[' + re.escape(BUNDLE) + r'\(.*?\)\] plugin INSTALLED; bundleID: \[' + re.escape(BUNDLE) + r'\], path: \[([^]]+)\]')
ALLOW = re.compile(r'\[u ' + UUID + r'\].*?\[' + re.escape(BUNDLE) + r'\(.*?\)\] Allowing host pid (\d+) to use plugin \[([^]]+)\]')
REQUEST = re.compile(r'Launching extension ' + re.escape(BUNDLE) + r'\(' + UUID + r'\) for host (\d+)')
STAMP = re.compile(r'^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)')


def correlation(log, summary, ax_path, udid):
    event = summary.get('launch_event', {}).get('parsed')
    if not event or summary.get('diagnostic') != 'xpcproxy-overlap-observed':
        return 'no-validated-live-overlap'
    launches, registrations, allows, requests = [], [], [], []
    for line in log.splitlines():
        stamp = STAMP.match(line)
        if not stamp:
            continue
        moment = dt.datetime.strptime(stamp.group(1), '%Y-%m-%d %H:%M:%S.%f')
        found = observer.parse_event(line, event['uid'])
        if found and found == event:
            launches.append(moment)
        for pattern, bucket in ((REGISTER, registrations), (ALLOW, allows), (REQUEST, requests)):
            match = pattern.search(line)
            if match:
                bucket.append((moment, *match.groups()))
    if len(launches) != 1:
        return 'missing-or-ambiguous-archived-launch'
    if udid not in ax_path or not ax_path.endswith('/FreeShiamyKeyboard.appex'):
        return 'wrong-installed-bundle-path'
    spawned = launches[0]
    current_registration = [record for record in registrations if record[0] <= spawned]
    current_allow = [record for record in allows if record[0] <= spawned]
    current_request = [record for record in requests if record[0] <= spawned]
    if not current_registration or not current_allow or not current_request:
        return 'missing-current-launch-request'
    reg, allow, request = current_registration[-1], current_allow[-1], current_request[-1]
    # A registration alone is insufficient: require the immediately current
    # host permission and actual UUID-bound launch request to this exact path.
    if not (reg[0] <= allow[0] <= request[0] <= spawned):
        return 'launch-request-order-mismatch'
    if not (reg[1] == allow[1] == request[1] and
            reg[2] == allow[3] == ax_path and allow[2] == request[2]):
        return 'current-launch-request-path-or-uuid-mismatch'
    return 'exact-udid-job-pid-request-and-installed-path-correlated'


def main(directory):
    root = pathlib.Path(directory)
    summary = json.loads((root/'observer'/'observer-summary.json').read_text())
    installed = dict(line.split('=', 1) for line in (root/'ax-after'/'paths.txt').read_text().splitlines())
    udid = dict(line.split('=', 1) for line in (root/'owned-device.txt').read_text().splitlines())['owned_udid']
    reason = correlation((root/'installed-adaptive-ax-simulator-all-processes.log').read_text(errors='replace'),
                         summary, installed['installed_extension'], udid)
    result = {'correlation': reason, 'owned_udid': udid, 'installed_extension': installed['installed_extension'],
              'observer_diagnostic': summary.get('diagnostic'), 'sample_attempts': summary.get('sample_attempts')}
    (root/'correlation.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))
    return reason == 'exact-udid-job-pid-request-and-installed-path-correlated'


if __name__ == '__main__':
    sys.exit(0 if main(sys.argv[1]) else 1)
