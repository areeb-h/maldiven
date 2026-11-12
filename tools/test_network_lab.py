#!/usr/bin/env python3
"""Exercise actual loopback Godot processes for NET-001. No external service needed."""
import argparse
import copy
import datetime
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

from bootstrap_godot import ROOT, ensure_engine, validate_engine
from validate_project import source_id


def wait_for(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.025)
    raise AssertionError('Timed out waiting for network evidence')


class Process:
    def __init__(self, engine, project, output, name, script, options):
        self.path = output / (name + '.log')
        self.stream = self.path.open('w')
        self.process = subprocess.Popen(
            [str(engine), '--headless', '--path', str(project), '--script', 'res://' + script, '--', *options],
            stdout=self.stream, stderr=subprocess.STDOUT)

    def events(self):
        result = []
        for line in self.path.read_text(errors='replace').splitlines(keepends=True):
            if not line.endswith('\n'):
                continue
            if line.startswith('NETLAB '):
                result.append(json.loads(line[len('NETLAB '):]))
        return result

    def event(self, kind, **fields):
        return next((x for x in self.events() if x.get('event') == kind and all(x.get(k) == v for k, v in fields.items())), None)

    def finish(self, expected):
        code = self.process.wait(timeout=8)
        assert code == expected, (self.path.name, code, expected, self.path.read_text()[-1200:])
        text = self.path.read_text()
        assert 'SCRIPT ERROR:' not in text and 'ERROR:' not in text, self.path.name

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)
        self.stream.close()


class Lab:
    def __init__(self, engine, project, temporary, output):
        self.engine, self.project, self.temporary, self.output = engine, project, temporary, output
        self.processes, self.servers, self.tokens = [], [], []
        self.counter = 0

    def server(self, name, capacity=2, ttl=60, reuse_state=None):
        state = reuse_state or self.temporary / name
        state.mkdir(mode=0o700, exist_ok=reuse_state is not None)
        process = Process(self.engine, self.project, self.output, name, 'server.gd',
                          ['--state-dir', str(state), '--max-clients', str(capacity), '--ticket-ttl', str(ttl), '--auth-timeout', '1'])
        self.processes.append(process)
        self.servers.append((process, state))
        ready = wait_for(lambda: process.event('server_ready'))
        private = json.loads((state / 'admissions.json').read_text())
        self.tokens.extend(x['join']['ticket'] for x in private['credentials'])
        if os.name == 'posix':
            assert state.stat().st_mode & 0o777 == 0o700
            assert (state / 'admissions.json').stat().st_mode & 0o777 == 0o600
        return {'process': process, 'state': state, 'ready': ready, 'credentials': private['credentials']}

    def credential(self, server, player, issuance=0):
        return copy.deepcopy(next(x for x in server['credentials'] if x['player_id'] == player and x['issuance'] == issuance))

    def client(self, server, credential, hold=0.15, behaviour='normal', raw=None, app=None, timeout=6):
        self.counter += 1
        name = 'client-%02d' % self.counter
        path = self.temporary / (name + '.json')
        path.write_text(json.dumps(credential))
        path.chmod(0o600)
        leave = self.temporary / (name + '.leave')
        options = ['--ticket-file', str(path), '--port', str(server['ready']['port']),
                   '--hold-seconds', str(hold), '--behaviour', behaviour, '--leave-file', str(leave), '--timeout', str(timeout)]
        for option, data in (('--raw-file', raw), ('--app-file', app)):
            if data is not None:
                extra = self.temporary / (name + option + '.bin')
                extra.write_bytes(data)
                extra.chmod(0o600)
                options += [option, str(extra)]
        process = Process(self.engine, self.project, self.output, name, 'client.gd', options)
        self.processes.append(process)
        process.leave_path = leave
        return process

    def accepted(self, server, player, issuance=0, hold=0.15, app=None):
        process = self.client(server, self.credential(server, player, issuance), hold=hold, app=app)
        wait_for(lambda: process.event('client_admitted', player_id=player))
        return process

    def leave(self, server, process):
        previous = len([x for x in server['process'].events() if x.get('event') == 'disconnected'])
        process.leave_path.touch()
        process.finish(0)
        assert process.event('client_finished', status='left')
        wait_for(lambda: len([x for x in server['process'].events() if x.get('event') == 'disconnected']) > previous)

    def rejected(self, server, credential, reason, raw=None):
        before = sum(x.get('event') == 'rejected' for x in server['process'].events())
        process = self.client(server, credential, raw=raw)
        process.finish(3)
        assert process.event('client_finished', status='rejected', reason=reason), process.events()
        rejections = [x for x in server['process'].events() if x.get('event') == 'rejected']
        assert len(rejections) == before + 1 and rejections[-1]['reason'] == reason
        assert not process.event('client_admitted')

    def stop(self, server):
        (server['state'] / 'stop').touch()
        server['process'].finish(0)
        assert server['process'].event('server_stopped', active=0, reserved=0)

    def close(self):
        for process, state in self.servers:
            if process.process.poll() is None:
                (state / 'stop').touch()
                try:
                    process.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    pass
        for process in self.processes:
            process.close()


def exercise(lab, report):
    def record(name, operation):
        print(name + '...', flush=True)
        started = time.monotonic()
        try:
            operation()
        except Exception:
            report['checks'].append({'name': name, 'passed': False})
            raise
        report['checks'].append({'name': name, 'passed': True, 'seconds': round(time.monotonic() - started, 3)})

    server = lab.server('server-main')
    record('loopback-ready-and-private-credentials', lambda: assert_true(server['ready']['host'] == '127.0.0.1'))
    first = lab.accepted(server, 'player-1', hold=30)
    record('valid-admission', lambda: assert_true(server['process'].event('admitted', player_id='player-1', active=1)))
    record('duplicate-identity', lambda: lab.rejected(server, lab.credential(server, 'player-1', 1), 'identity_in_use'))
    second = lab.accepted(server, 'player-2', hold=30)
    record('two-distinct-clients', lambda: assert_true(server['process'].event('admitted', player_id='player-2', active=2)))
    record('capacity-bound', lambda: lab.rejected(server, lab.credential(server, 'player-3'), 'room_full'))
    record('clean-disconnect', lambda: (lab.leave(server, first), lab.leave(server, second)))
    record('single-use-ticket-replay', lambda: lab.rejected(server, lab.credential(server, 'player-1'), 'ticket_replay'))
    returning = lab.accepted(server, 'player-1', 1, hold=30)
    record('fresh-ticket-same-identity', lambda: lab.leave(server, returning))

    for name, key, value, reason in [
        ('protocol-major-mismatch', 'protocol_major', 2, 'version_mismatch'),
        ('protocol-minor-mismatch', 'protocol_minor', 1, 'version_mismatch'),
        ('fractional-protocol', 'protocol_major', 1.5, 'version_mismatch'),
        ('content-mismatch', 'content_id', 'wrong', 'content_id_mismatch'),
        ('rules-mismatch', 'rules_id', 'wrong', 'rules_id_mismatch'),
        ('room-mismatch', 'room_id', 'wrong', 'room_id_mismatch'),
        ('epoch-mismatch', 'room_epoch', 'old-room', 'stale_epoch'),
        ('unknown-ticket', 'ticket', '0' * 64, 'invalid_ticket'),
        ('identity-spoof-field', 'player_id', 'player-1', 'malformed'),
    ]:
        credential = lab.credential(server, 'player-3')
        credential['join'][key] = value
        record(name, lambda c=credential, r=reason: lab.rejected(server, c, r))

    for name, raw in [('malformed-json', b'{'), ('oversized-auth', b'X' * 4096), ('non-ascii-auth', b'\xff')]:
        record(name, lambda data=raw: lab.rejected(server, lab.credential(server, 'player-3'), 'malformed', raw=data))
    third = lab.accepted(server, 'player-3', hold=30)
    record('rejections-did-not-consume-valid-ticket', lambda: lab.leave(server, third))

    def silent_case():
        process = lab.client(server, lab.credential(server, 'player-4'), behaviour='silent')
        process.finish(3)
        assert process.event('client_finished', status='auth_failed') and not process.event('client_admitted')
    record('silent-auth-timeout', silent_case)

    def stalled_case():
        previous = len([x for x in server['process'].events() if x.get('event') == 'auth_failed'])
        admitted_before = sum(x.get('event') == 'admitted' for x in server['process'].events())
        process = lab.client(server, lab.credential(server, 'player-4'), behaviour='stall')
        process.finish(3)
        wait_for(lambda: len([x for x in server['process'].events() if x.get('event') == 'auth_failed']) > previous)
        event = [x for x in server['process'].events() if x.get('event') == 'auth_failed'][-1]
        assert event['reserved'] == 0 and event['active'] == 0
        assert sum(x.get('event') == 'admitted' for x in server['process'].events()) == admitted_before
        assert not process.event('client_admitted')
        fresh = lab.accepted(server, 'player-4', 1, hold=30)
        lab.leave(server, fresh)
    record('half-finished-auth-releases-identity', stalled_case)

    def unsupported_message():
        before = sum(x.get('event') == 'message_rejected' for x in server['process'].events())
        process = lab.accepted(server, 'player-5', hold=30, app=b'{"kind":"declare_win"}')
        wait_for(lambda: sum(x.get('event') == 'message_rejected' for x in server['process'].events()) > before)
        lab.leave(server, process)
    record('unsupported-application-message', unsupported_message)

    def simultaneous_identity():
        a = lab.client(server, lab.credential(server, 'player-6'), hold=30)
        b = lab.client(server, lab.credential(server, 'player-6', 1), hold=30)
        wait_for(lambda: (a.event('client_admitted') and b.event('client_finished')) or (b.event('client_admitted') and a.event('client_finished')))
        winner, loser = (a, b) if a.event('client_admitted') else (b, a)
        loser.finish(3)
        assert loser.event('client_finished', status='rejected', reason='identity_in_use')
        lab.leave(server, winner)
    record('simultaneous-identity-reservation', simultaneous_identity)

    old = lab.credential(server, 'player-5', 1)
    lab.stop(server)
    restarted = lab.server('server-restarted', reuse_state=server['state'])
    record('fresh-epoch-on-restart', lambda: assert_true(restarted['ready']['room_epoch'] != server['ready']['room_epoch']))
    record('old-ticket-rejected-after-restart', lambda: lab.rejected(restarted, old, 'stale_epoch'))
    final_client = lab.accepted(restarted, 'player-1', hold=30)
    record('admission-after-restart', lambda: lab.leave(restarted, final_client))

    def accepted_outlives_timeout():
        process = lab.client(restarted, lab.credential(restarted, 'player-2'), hold=1.2, timeout=0.7)
        wait_for(lambda: process.event('client_admitted'))
        process.finish(0)
        assert process.event('client_finished', status='left')
    record('accepted-session-outlives-join-timeout', accepted_outlives_timeout)

    def active_server_stop():
        process = lab.accepted(restarted, 'player-3', hold=30)
        pending = lab.client(restarted, lab.credential(restarted, 'player-4'), behaviour='stall')
        wait_for(lambda: restarted['process'].event('authentication_reserved', player_id='player-4'))
        lab.stop(restarted)
        process.finish(2)
        assert process.event('client_finished', status='disconnected')
        pending.finish(3)
        assert not pending.event('client_admitted')
        events = restarted['process'].events()
        stopping = next(i for i, x in enumerate(events) if x.get('event') == 'server_stopping')
        assert not any(x.get('event') == 'admitted' for x in events[stopping:])
    record('server-stop-cleans-active-and-pending-sessions', active_server_stop)

    expiring = lab.server('server-expiring', ttl=0.25)
    time.sleep(0.35)
    record('server-owned-ticket-expiry', lambda: lab.rejected(expiring, lab.credential(expiring, 'player-1'), 'expired_ticket'))
    lab.stop(expiring)

    def no_credentials_in_logs():
        logs = '\n'.join(p.path.read_text() for p in lab.processes)
        assert all(token not in logs for token in lab.tokens)
        assert 'SCRIPT ERROR:' not in logs and 'ERROR:' not in logs
    record('no-credentials-or-engine-errors-in-logs', no_credentials_in_logs)


def assert_true(value):
    assert value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--output', type=Path, default=ROOT / 'builds' / 'network-lab')
    args = parser.parse_args()
    if not __debug__:
        parser.error('Run without Python -O; the integration checks use assertions')
    output = args.output.resolve()
    if output == ROOT or (ROOT in output.parents and output.relative_to(ROOT).parts[0] != 'builds'):
        parser.error('Output inside the repository must be under builds/')
    output.mkdir(parents=True, exist_ok=True)
    report = {'status': 'failed', 'checks': [], 'source_id': source_id(ROOT),
              'compatibility': json.loads((ROOT / 'experiments' / 'net-lab' / 'compatibility.json').read_text()),
              'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'scope': 'independent Godot server/client processes over IPv4 loopback; local bearer-ticket ledger only; no movement, encryption, internet, phone, voice or match reconnect validation'}
    lab = None
    try:
        engine, report['engine'] = validate_engine(args.godot or ensure_engine())
        with tempfile.TemporaryDirectory(prefix='maldiven-net-') as directory:
            temporary = Path(directory)
            project = temporary / 'project'
            shutil.copytree(ROOT / 'experiments' / 'net-lab', project, ignore=shutil.ignore_patterns('.godot'))
            lab = Lab(engine, project, temporary, output)
            try:
                exercise(lab, report)
                report['status'] = 'passed'
            finally:
                lab.close()
    except (AssertionError, OSError, RuntimeError, ValueError, subprocess.SubprocessError) as exc:
        report['error'] = str(exc)
        print('FAILED: ' + str(exc), flush=True)
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Report: ' + str(output / 'report.json'), flush=True)
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
