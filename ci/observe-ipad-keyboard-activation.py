#!/usr/bin/env python3
"""One-shot, Simulator-scoped xpcproxy PID observer. Diagnostic evidence only."""
import argparse
import datetime as dt
import json
import os
import pathlib
import re
import selectors
import signal
import subprocess
import sys
import time

BUNDLE = 'osku.me.freeshiamyios.keyboard'
EVENT = re.compile(
    r'launchd_sim\[(?P<parent>\d+):[^]]+\].*?\[user/(?P<uid>\d+)/'
    + re.escape(BUNDLE) + r' \[(?P<job_pid>\d+)\]:\]\s*xpcproxy_sim spawned with pid\s*(?P<pid>\d+)')
PS = re.compile(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+'
                r'((?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s+\w+\s+\d+\s+\d\d:\d\d:\d\d\s+\d{4})\s+'
                r'(\S+)\s+(.+?)\s*$')
STOP = False


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def supported_help(help_text):
    return all(flag in help_text for flag in ('--style', '--level', '--predicate'))


def parse_event(line, expected_uid):
    match = EVENT.search(line)
    if not match:
        return None
    data = {key: int(value) for key, value in match.groupdict().items()}
    if data['uid'] != expected_uid or data['job_pid'] != data['pid']:
        return None
    return data


def parse_ps(output, pid, parent, uid, required_name):
    match = PS.match(output.strip())
    if not match:
        return None
    actual_pid, actual_parent, actual_uid = map(int, match.group(1, 2, 3))
    start_text, state, command = match.group(4, 5, 6)
    if (actual_pid, actual_parent, actual_uid) != (pid, parent, uid):
        return None
    if pathlib.PurePath(command).name != required_name or state.upper().startswith('Z'):
        return None
    try:
        started = dt.datetime.strptime(start_text, '%a %b %d %H:%M:%S %Y')
    except ValueError:
        return None
    return {'pid': pid, 'parent': parent, 'uid': uid, 'start_local': start_text,
            'state': state, 'command': command, 'started_epoch': time.mktime(started.timetuple())}


def has_exact_sample_report(report, pid):
    # A process header and a stack-like line elsewhere in the file are not a
    # captured stack. Limit frames to this report's actual Call graph body.
    process_line = re.search(r'^\s*Process:\s*xpcproxy_sim\s*\[\s*' + str(pid) + r'\s*\]', report, re.M)
    analysis_line = re.search(r'Analysis of sampling xpcproxy_sim\s*\(pid\s*' + str(pid) + r'\)', report)
    graph = re.search(r'^\s*Call graph:\s*$', report, re.M)
    if not (process_line or analysis_line) or not graph:
        return False
    body = []
    for line in report[graph.end():].splitlines():
        if re.match(r'^\s*(?:Total number|Sort by|Binary Images:|Process:|Analysis of|Heaviest stack|Summary:)', line):
            break
        body.append(line)
    thread_index = next((n for n, line in enumerate(body)
                         if re.match(r'^\s*(?:[|+`-]\s*)*[1-9]\d*\s+Thread[_ ]\S*', line)), None)
    if thread_index is None:
        return False
    return any(re.match(r'^\s*(?:[|+`-]\s*)*[1-9]\d*\s+[^\n]+\+\s*(?:0x[0-9a-fA-F]+|\d+)(?:\s+\[0x[0-9a-fA-F]+\])?\s*$', line)
               for line in body[thread_index + 1:])


def same_process(before, after):
    return bool(before and after and all(before[k] == after[k] for k in
                ('pid', 'parent', 'uid', 'start_local', 'command')))


def stop(_signum, _frame):
    global STOP
    STOP = True


def record_command(path, argv, timeout=4):
    start = utc()
    try:
        completed = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                                   env={**os.environ, 'LC_ALL': 'C'})
        record = {'argv': argv, 'start_utc': start, 'end_utc': utc(),
                  'status': completed.returncode, 'stdout': completed.stdout,
                  'stderr': completed.stderr}
    except subprocess.TimeoutExpired as error:
        record = {'argv': argv, 'start_utc': start, 'end_utc': utc(), 'status': 'timeout',
                  'stdout': (error.stdout or b'').decode(errors='replace') if isinstance(error.stdout, bytes) else (error.stdout or ''),
                  'stderr': (error.stderr or b'').decode(errors='replace') if isinstance(error.stderr, bytes) else (error.stderr or '')}
    path.write_text(json.dumps(record, indent=2) + '\n')
    return record


def observe(args):
    output = pathlib.Path(args.output)
    output.mkdir(parents=True, exist_ok=True)
    started = time.time()
    summary = {'owned_udid': args.udid, 'expected_uid': os.getuid(), 'started_utc': utc(),
               'diagnostic': 'missing', 'sample_attempts': 0}
    stream = None
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        help_text = pathlib.Path(args.stream_help).read_text(errors='replace')
        sample_help = pathlib.Path(args.sample_help).read_text(errors='replace')
        if not supported_help(help_text) or '-file' not in sample_help:
            summary['diagnostic'] = 'unsupported-help'
            return
        # The job label can be log scope metadata rather than eventMessage.
        # Stream only this Simulator's launchd, then match the exact job locally.
        predicate = 'process == "launchd_sim" OR process == "launchd"'
        command = ['xcrun', 'simctl', 'spawn', args.udid, 'log', 'stream', '--style',
                   'compact', '--level', 'debug', '--predicate', predicate]
        summary['stream_command'] = command
        stream = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  bufsize=0, start_new_session=True)
        selector = selectors.DefaultSelector()
        for name, pipe in (('stdout', stream.stdout), ('stderr', stream.stderr)):
            os.set_blocking(pipe.fileno(), False)
            selector.register(pipe, selectors.EVENT_READ, name)
        with (output / 'stream-stdout.log').open('wb') as stdout, \
             (output / 'stream-stderr.log').open('wb') as stderr:
            buffer = b''
            ready_buffer = b''
            armed = False
            seen = False
            while not STOP and time.time() - started < args.max_seconds:
                if stream.poll() is not None and not selector.get_map():
                    summary['diagnostic'] = 'stream-exited'
                    break
                for key, _ in selector.select(timeout=0.25):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    (stdout if key.data == 'stdout' else stderr).write(data)
                    (stdout if key.data == 'stdout' else stderr).flush()
                    if not armed:
                        ready_buffer = (ready_buffer + data)[-16384:]
                        if re.search(rb'(?m)^(?:Filtering the log data using\b|Timestamp\s+Ty\s+Process\b)', ready_buffer):
                            armed = True
                            (output / 'armed.json').write_text(json.dumps({'utc': utc(), 'pid': os.getpid(), 'stream_pid': stream.pid, 'command': command, 'readiness_receipt': ready_buffer.decode(errors='replace')[-500:]}) + '\n')
                    if key.data != 'stdout' or seen:
                        continue
                    buffer += data
                    while b'\n' in buffer:
                        raw, buffer = buffer.split(b'\n', 1)
                        line = raw.decode(errors='replace')
                        event = parse_event(line, os.getuid())
                        if not event:
                            continue
                        seen = True
                        summary['launch_event'] = {'parsed': event, 'raw': line,
                                                   'receipt_utc': utc()}
                        pid, parent, uid = event['pid'], event['parent'], event['uid']
                        parent_record = record_command(output / 'parent-ps.json',
                                                        ['ps', '-p', str(parent), '-o', 'pid=', '-o', 'ppid=',
                                                         '-o', 'uid=', '-o', 'lstart=', '-o', 'state=', '-o', 'comm='])
                        parent_identity = parse_ps(parent_record['stdout'], parent,
                                                   int(parent_record['stdout'].split()[1]) if len(parent_record['stdout'].split()) > 1 else -1,
                                                   uid, 'launchd_sim') if parent_record['status'] == 0 else None
                        before_record = record_command(output / 'before-ps.json',
                                                       ['ps', '-p', str(pid), '-o', 'pid=', '-o', 'ppid=',
                                                        '-o', 'uid=', '-o', 'lstart=', '-o', 'state=', '-o', 'comm='])
                        before = parse_ps(before_record['stdout'], pid, parent, uid, 'xpcproxy_sim') if before_record['status'] == 0 else None
                        summary['before'] = before
                        summary['parent_valid'] = bool(parent_identity)
                        if not parent_identity or not before or before['started_epoch'] < started - 2:
                            summary['diagnostic'] = 'pid-identity-mismatch-or-late-event'
                            break
                        sample_path = output / 'pid.sample.txt'
                        summary['sample_attempts'] = 1
                        sample = record_command(output / 'sample-command.json',
                                                ['sample', str(pid), '1', '-file', str(sample_path)], timeout=5)
                        after_record = record_command(output / 'after-ps.json',
                                                      ['ps', '-p', str(pid), '-o', 'pid=', '-o', 'ppid=',
                                                       '-o', 'uid=', '-o', 'lstart=', '-o', 'state=', '-o', 'comm='])
                        after = parse_ps(after_record['stdout'], pid, parent, uid, 'xpcproxy_sim') if after_record['status'] == 0 else None
                        summary['after'] = after
                        summary['sample_status'] = sample['status']
                        sample_text = sample_path.read_text(errors='replace') if sample_path.is_file() else ''
                        summary['sample_has_exact_stack'] = has_exact_sample_report(sample_text, pid)
                        if sample['status'] != 0:
                            summary['diagnostic'] = 'sample-denied-or-failed'
                        elif not same_process(before, after):
                            summary['diagnostic'] = 'pid-reused-or-execed-during-sample'
                        elif not summary['sample_has_exact_stack']:
                            summary['diagnostic'] = 'sample-overlap-unproven'
                        else:
                            summary['diagnostic'] = 'xpcproxy-overlap-observed'
                        break
                    if seen:
                        break
                if seen:
                    break
            if STOP and not seen:
                summary['diagnostic'] = 'no-exact-launch-before-stage-end' if armed else 'stream-readiness-unproven'
            elif not seen and summary['diagnostic'] == 'missing':
                summary['diagnostic'] = 'observer-time-bound'
    finally:
        if stream is not None:
            summary['stream_stop_requested_utc'] = utc()
            try:
                os.killpg(stream.pid, signal.SIGTERM)
                summary['stream_group_term_status'] = 'sent'
            except ProcessLookupError:
                summary['stream_group_term_status'] = 'already-gone'
            try:
                stream.wait(timeout=2)
            except subprocess.TimeoutExpired:
                summary['stream_wait_after_term'] = 'timeout'
            # xcrun can exit before its log-stream descendant. This group was
            # created solely for the owned observer and is never name-searched.
            try:
                os.killpg(stream.pid, 0)
                os.killpg(stream.pid, signal.SIGKILL)
                summary['stream_group_kill_status'] = 'remaining-owned-group-killed'
            except ProcessLookupError:
                summary['stream_group_kill_status'] = 'group-exited'
            if stream.poll() is None:
                stream.wait(timeout=2)
            summary['stream_exit_status'] = stream.returncode
        summary['ended_utc'] = utc()
        (output / 'observer-summary.json').write_text(json.dumps(summary, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--udid', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--stream-help', required=True)
    parser.add_argument('--sample-help', required=True)
    parser.add_argument('--max-seconds', type=int, default=420)
    observe(parser.parse_args())
