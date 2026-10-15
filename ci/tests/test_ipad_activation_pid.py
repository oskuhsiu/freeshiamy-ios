import datetime as dt
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
CI = ROOT / 'ci'

def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, CI / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

observer = load('activation_observer_test', 'observe-ipad-keyboard-activation.py')
correlation = load('activation_correlation_test', 'check-ipad-activation-correlation.py')
UID = os.getuid()
UDID = 'FE9ECAF8-445A-4717-9F46-77532985F47A'
PATH = f'/Users/runner/Library/Developer/CoreSimulator/Devices/{UDID}/data/Containers/Bundle/Application/NEW/freeshiamy-ios.app/PlugIns/FreeShiamyKeyboard.appex'
EVENT = f'2026-10-15 02:22:45.215 Df launchd_sim[100:1cd6c] [user/{UID}/osku.me.freeshiamyios.keyboard [222]:] xpcproxy_sim spawned with pid 222'
UUID = '5AE8CC39-CEE6-448A-A25C-75147F253715'
REGISTER = f'2026-10-15 02:22:18.782 Df pkd[7:1] [u {UUID}] [osku.me.freeshiamyios.keyboard(1.0)] plugin INSTALLED; bundleID: [osku.me.freeshiamyios.keyboard], path: [{PATH}]'
ALLOW = f'2026-10-15 02:22:45.207 Df pkd[7:1] [u {UUID}] [osku.me.freeshiamyios.keyboard(1.0)] Allowing host pid 42530 to use plugin [{PATH}]'
REQUEST = f'2026-10-15 02:22:45.207 I pkd[7:1] Sending launch request: Launching extension osku.me.freeshiamyios.keyboard({UUID}) for host 42530'
LOG = '\n'.join((REGISTER, ALLOW, REQUEST, EVENT))

class CorrelationTests(unittest.TestCase):
    def test_exact_event_and_identity(self):
        parsed = observer.parse_event(EVENT, UID)
        self.assertEqual(parsed['pid'], 222)
        summary = {'diagnostic': 'xpcproxy-overlap-observed', 'launch_event': {'parsed': parsed}}
        self.assertEqual(correlation.correlation(LOG, summary, PATH, UDID),
                         'exact-udid-job-pid-request-and-installed-path-correlated')
        self.assertEqual(correlation.correlation(LOG, summary, PATH.replace(UDID, 'WRONG'), UDID),
                         'wrong-installed-bundle-path')
        self.assertEqual(correlation.correlation(LOG, summary, PATH.replace('/NEW/', '/OLD/'), UDID),
                         'current-launch-request-path-or-uuid-mismatch')
        self.assertEqual(correlation.correlation(LOG.replace('pid 222', 'pid 223'), summary, PATH, UDID),
                         'missing-or-ambiguous-archived-launch')
        self.assertEqual(correlation.correlation(LOG+'\n'+EVENT, summary, PATH, UDID),
                         'missing-or-ambiguous-archived-launch')
        self.assertEqual(correlation.correlation('\n'.join((REGISTER, EVENT)), summary, PATH, UDID),
                         'missing-current-launch-request')
        self.assertEqual(correlation.correlation(LOG.replace(REQUEST, REQUEST.replace(UUID, '00000000-0000-0000-0000-000000000000')), summary, PATH, UDID),
                         'current-launch-request-path-or-uuid-mismatch')

    def test_reject_wrong_bundle_job_pid_uid_and_reuse(self):
        self.assertIsNone(observer.parse_event(EVENT.replace('osku.me.freeshiamyios.keyboard', 'other.keyboard'), UID))
        self.assertIsNone(observer.parse_event(EVENT.replace('[222]:]', '[223]:]'), UID))
        self.assertIsNone(observer.parse_event(EVENT, UID+1))
        self.assertTrue(observer.supported_help('usage --style --level --predicate'))
        self.assertFalse(observer.supported_help('usage --style --predicate'))
        start = dt.datetime.now().strftime('%a %b %d %H:%M:%S %Y')
        correct = f'222 100 {UID} {start} S /usr/libexec/xpcproxy_sim'
        record = observer.parse_ps(correct, 222, 100, UID, 'xpcproxy_sim')
        self.assertIsNotNone(record)
        self.assertIsNone(observer.parse_ps(correct, 223, 100, UID, 'xpcproxy_sim'))
        self.assertIsNone(observer.parse_ps(correct, 222, 101, UID, 'xpcproxy_sim'))
        self.assertIsNone(observer.parse_ps(correct.replace('xpcproxy_sim', 'FreeShiamyKeyboard'), 222, 100, UID, 'xpcproxy_sim'))
        reused = dict(record, start_local='Mon Oct 12 00:00:00 2026')
        self.assertFalse(observer.same_process(record, reused))
        self.assertFalse(observer.has_exact_sample_report('Process: xpcproxy_sim [222]\nCall graph:\n', 222))
        self.assertTrue(observer.has_exact_sample_report('Process: xpcproxy_sim [222]\nCall graph:\n  1 Thread_0\n    1 main + 0x10\n', 222))
        self.assertFalse(observer.has_exact_sample_report('Process: xpcproxy_sim [223]\nCall graph:\n  1 Thread_0\n    1 main + 0x10\n', 222))
        self.assertFalse(observer.has_exact_sample_report('Process: xpcproxy_sim [222]\nCall graph:\nBinary Images:\n  1 Thread_0\n    1 main + 0x10\n', 222))
        self.assertFalse(observer.has_exact_sample_report('Process: xpcproxy_sim [222]\n  1 Thread_0\n    1 main + 0x10\nCall graph:\n', 222))
        self.assertFalse(observer.has_exact_sample_report('Process: xpcproxy_sim [222]\nCall graph:\n  1 Thread_0\n    0 main + 0x10\n', 222))
        self.assertTrue(observer.has_exact_sample_report('Process: xpcproxy_sim [222]\nCall graph:\n  +-- 2596 Thread_24457592 DispatchQueue_1\n  | 2596 start (in dyld) + 1903 [0x7ff813c6f41f]\nTotal number in stack:\n', 222))

    def test_one_sample_and_owned_stream_cleanup(self):
        with tempfile.TemporaryDirectory() as temp:
            temp = pathlib.Path(temp)
            bin_dir = temp / 'bin'; bin_dir.mkdir()
            stamp = dt.datetime.now().strftime('%a %b %d %H:%M:%S %Y')
            (bin_dir/'xcrun').write_text('#!/usr/bin/env python3\nimport time\nprint("Filtering the log data using predicate", flush=True)\nprint('+repr(EVENT)+', flush=True)\ntime.sleep(5)\n')
            (bin_dir/'ps').write_text(f'''#!/usr/bin/env python3
import sys
pid = sys.argv[sys.argv.index('-p') + 1]
if pid == '100': print('100 1 {UID} {stamp} S /usr/libexec/launchd_sim')
elif pid == '222': print('222 100 {UID} {stamp} S /usr/libexec/xpcproxy_sim')
else: sys.exit(1)
''')
            (bin_dir/'sample').write_text('''#!/usr/bin/env python3
import os, pathlib, sys
if os.environ.get('SAMPLE_DENY') == '1': sys.exit(64)
pathlib.Path(sys.argv[sys.argv.index('-file')+1]).write_text('Process: xpcproxy_sim [222]\\nCall graph:\\n  1 Thread_0\\n    1 main + 0x10\\n')
''')
            for path in bin_dir.iterdir(): path.chmod(0o755)
            (temp/'stream-help').write_text('--style --level --predicate')
            (temp/'sample-help').write_text('-file')
            env = dict(os.environ, PATH=str(bin_dir)+os.pathsep+os.environ['PATH'], PYTHONDONTWRITEBYTECODE='1')
            command = [sys.executable, str(CI/'observe-ipad-keyboard-activation.py'), '--udid', UDID,
                       '--output', str(temp/'out'), '--stream-help', str(temp/'stream-help'),
                       '--sample-help', str(temp/'sample-help'), '--max-seconds', '3']
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            summary = json.loads((temp/'out'/'observer-summary.json').read_text())
            self.assertEqual(summary['sample_attempts'], 1)
            self.assertEqual(summary['diagnostic'], 'xpcproxy-overlap-observed')
            self.assertEqual(summary['stream_command'][3], UDID)
            self.assertIn('stream_exit_status', summary)
            self.assertTrue((temp/'out'/'sample-command.json').exists())
            # Unsupported help refuses stream and sampling entirely.
            (temp/'stream-help').write_text('--style --predicate')
            result = subprocess.run(command[:command.index('--output')+1] + [str(temp/'bad')] + command[command.index('--stream-help'):],
                                    env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 0)
            bad = json.loads((temp/'bad'/'observer-summary.json').read_text())
            self.assertEqual(bad['diagnostic'], 'unsupported-help')
            self.assertEqual(bad['sample_attempts'], 0)
            (temp/'stream-help').write_text('--style --level --predicate')
            env['SAMPLE_DENY'] = '1'
            denied_command = command[:command.index('--output')+1] + [str(temp/'denied')] + command[command.index('--stream-help'):]
            denied_result = subprocess.run(denied_command, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(denied_result.returncode, 0)
            denied = json.loads((temp/'denied'/'observer-summary.json').read_text())
            self.assertEqual(denied['diagnostic'], 'sample-denied-or-failed')
            self.assertEqual(denied['sample_attempts'], 1)
            (bin_dir/'xcrun').write_text('#!/usr/bin/env python3\nprint("Error: invalid Timestamp parameter")\n')
            error_command = command[:command.index('--output')+1] + [str(temp/'error')] + command[command.index('--stream-help'):]
            error_result = subprocess.run(error_command, env=env, capture_output=True, text=True, timeout=5)
            self.assertEqual(error_result.returncode, 0)
            error = json.loads((temp/'error'/'observer-summary.json').read_text())
            self.assertFalse((temp/'error'/'armed.json').exists())
            self.assertEqual(error['sample_attempts'], 0)

    def test_identity_fails_under_conditional_caller(self):
        # Execute the actual shell function under the same conditional context
        # used by the workflow. This catches Bash local expansion/set -u bugs
        # and a Python hash failure accidentally overwritten by later success.
        script = (CI/'diagnose-ipad-activation-pid.sh').read_text()
        function = script.split('identity() {', 1)[1].split('\n}\n', 1)[0]
        with tempfile.TemporaryDirectory() as temp:
            temp = pathlib.Path(temp)
            bin_dir = temp/'bin'; bin_dir.mkdir()
            built = temp/'built.app'; installed = temp/'installed.app'
            for app in (built, installed):
                (app/'PlugIns'/'FreeShiamyKeyboard.appex').mkdir(parents=True)
                for bundle, bundle_id, exe in ((app, 'osku.me.freeshiamyios', 'freeshiamy-ios'),
                        (app/'PlugIns'/'FreeShiamyKeyboard.appex', 'osku.me.freeshiamyios.keyboard', 'FreeShiamyKeyboard')):
                    import plistlib
                    (bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': bundle_id, 'CFBundleExecutable': exe}))
                    (bundle/exe).write_bytes(b'actual executable')
            proof = temp/'proof'; proof.mkdir()
            (proof/'bundle-identities.json').write_text(json.dumps([
                {'bundleId': 'osku.me.freeshiamyios', 'executableSha256': 'wrong'},
                {'bundleId': 'osku.me.freeshiamyios.keyboard', 'executableSha256': 'wrong'}]))
            (bin_dir/'xcrun').write_text('#!/bin/sh\nprintf "%s\\n" "$MOCK_INSTALLED"\n')
            (bin_dir/'xcrun').chmod(0o755)
            env = dict(os.environ, OUT=str(temp/'out'), PROOF=str(proof), APP=str(built),
                       DEVICE_ID=UDID, MOCK_INSTALLED=str(installed), PATH=str(bin_dir)+os.pathsep+os.environ['PATH'])
            body = 'set -euo pipefail\nidentity() {' + function + '\n}\nif identity check; then exit 7; else exit 0; fi\n'
            result = subprocess.run(['bash', '-c', body], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((temp/'out'/'check'/'installed-container.log').exists())
            self.assertFalse((temp/'out'/'check'/'identity.json').exists())

    def test_exact_one_push_route_and_normal_path(self):
        workflow = (ROOT/'.github/workflows/ios-tests.yml').read_text()
        route = "github.event.before == 'da449c6be22ec00e877ca20f7b0fed556766de71' && github.event.head_commit.message == 'ci: probe ipad keyboard xpcproxy pid only'"
        self.assertEqual(workflow.count(route), 5)
        self.assertIn('needs: [simulator, ipad, input_actions]', workflow)
        self.assertIn('matrix:\n        height_endpoint: [90, 220]', workflow)
        self.assertIn('run: bash ci/test-ios.sh', workflow)
        self.assertIn('run: bash ci/diagnose-ipad-activation-pid.sh', workflow)
        self.assertEqual(workflow.count('ci/diagnose-ipad-activation-pid.sh'), 1)

if __name__ == '__main__': unittest.main()
