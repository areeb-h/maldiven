#!/usr/bin/env python3
"""Real DTLS Godot processes: admission, PCM routing, playback and lifecycle evidence."""
import argparse
import datetime
import base64
import html
import json
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from bootstrap_godot import ROOT, ensure_engine, validate_engine
from test_network_lab import Lab, wait_for
from validate_project import source_id


class FriendsLab(Lab):
    def server(self, name, **kwargs):
        key, certificate = self.temporary / (name + '.key'), self.temporary / (name + '.crt')
        result = subprocess.run([str(self.engine), '--headless', '--path', str(self.project), '--script', 'res://create_certificate.gd', '--', str(key), str(certificate)], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0 and 'ERROR:' not in result.stdout + result.stderr, result.stdout + result.stderr
        server = super().server(name, capacity=6, script='phone_server.gd', extra=['--certificate', str(certificate), '--private-key', str(key), '--diagnostics', 'true'], **kwargs)
        server['certificate'] = certificate
        return server

    def driven(self, server, player, certificate=None, **kwargs):
        control = self.temporary / (player + '-' + str(self.counter) + '.control.json')
        control.write_text('{}')
        process = self.client(server, self.credential(server, player), hold=120, script='phone_probe.gd',
                              extra=['--certificate', str(certificate or server['certificate']), '--control-file', str(control)], **kwargs)
        process.control_path = control
        wait_for(lambda: process.event('view_sample'), timeout=25)
        return process


def exercise(lab, report):
    def record(name, operation):
        print(name + '...', flush=True)
        operation()
        report['checks'].append({'name': name, 'passed': True})

    def local_checks(script, marker):
        result = subprocess.run([str(lab.engine), '--headless', '--audio-driver', 'Dummy', '--path', str(lab.project), '--script', 'res://' + script], capture_output=True, text=True, timeout=20)
        assert result.returncode == 0 and 'ERROR:' not in result.stdout + result.stderr and marker in result.stdout, result.stdout + result.stderr

    record('Independent touch pointers, bounded PCM queue and native capture start/stop', lambda: local_checks('phone_local_checks.gd', 'FRIENDS_LOCAL_CHECKS_OK'))
    record('Invite menu rejects malformed input and recovers for retry without a microphone', lambda: local_checks('phone_menu_checks.gd', 'FRIENDS_MENU_CHECKS_OK'))

    server = lab.server('friends-dtls')
    first, second = lab.driven(server, 'player-1'), lab.driven(server, 'player-2')
    report['players'] = 2
    record('DTLS admission plus shared authoritative motion', lambda: (
        assert_true(first.event('client_admitted') and second.event('client_admitted')),
        assert_true(any(len(x.get('players', [])) == 2 for x in first.events()))))
    command_index = 0

    def command(process, action, **fields):
        nonlocal command_index
        command_index += 1
        identifier = str(command_index)
        process.control_path.write_text(json.dumps({'voice_command': dict(id=identifier, action=action, **fields)}))
        wait_for(lambda: process.event('voice_command_done', id=identifier))

    def counts(process):
        entries = [x for x in process.events() if x.get('event') == 'voice_playback']
        return entries[-1] if entries else {'received': 0, 'played': 0}

    def deny(reason, **fields):
        before = len([x for x in server['process'].events() if x.get('event') == 'voice_rejected' and x.get('reason') == reason])
        command(first, 'frames', reliable=True, **fields)
        if before == 0:
            wait_for(lambda: server['process'].event('voice_rejected', reason=reason))

    record('Microphone permission denied does not request a grant', lambda: (
        command(first, 'start', permission=False),
        assert_true(not first.event('voice_grant_received'))))
    record('Audio before a PTT grant is rejected', lambda: deny('no_current_grant', burst=1))

    def start(channel=0):
        command(first, 'start', channel=channel)
        wait_for(lambda: first.event('voice_grant_received', burst=1 if channel == 0 else 2))

    record('Reliable hold-to-talk grant is acknowledged', start)

    def nearby():
        before = counts(second)['received']
        command(first, 'frames', count=4)
        wait_for(lambda: counts(second)['received'] >= before + 2)
        wait_for(lambda: counts(second)['played'] >= 2)
        assert not counts(second).get('capturing')

    record('Nearby PCM reaches the native playback generator', nearby)
    record('Client cannot forge a speaker identity', lambda: deny('frame_shape_or_identity', speaker=1))
    # The same rejection category is already logged once; assert counters through separate scenarios below.
    record('Old room epoch and oversized frames do not reach playback', lambda: no_receive(first, second, command, counts,
        [('frames', {'epoch': 'old.epoch'}), ('frames', {'size': 1000})]))
    record('Repeated sequence is rejected', lambda: deny('frame_sequence', seq=1))

    def far_apart():
        # Control files feed directional intents, never positions, into the real server.
        first.control_path.write_text(json.dumps({'axis': [-1, 0], 'sprint': True}))
        second.control_path.write_text(json.dumps({'axis': [1, 0], 'sprint': True}))
        def separated():
            samples = [x for x in server['process'].events() if x.get('event') == 'motion_sample' and len(x.get('players', [])) == 2]
            if not samples:
                return False
            a, b = samples[-1]['players']
            return sum((a['p'][i] - b['p'][i]) ** 2 for i in range(3)) > 12 ** 2
        wait_for(separated, timeout=10)
        first.control_path.write_text('{}')
        second.control_path.write_text('{}')
        time.sleep(0.35)
        no_receive(first, second, command, counts, [('frames', {'count': 4})])

    record('Nearby voice is withheld beyond authoritative 8 m range', far_apart)

    def radio():
        command(first, 'stop')
        start(1)
        before = counts(second)['received']
        command(first, 'frames', count=4)
        wait_for(lambda: counts(second)['received'] >= before + 2)

    record('Radio reaches an admitted listener beyond nearby range', radio)
    record('Receiver mute discards audio locally', lambda: (
        command(second, 'mute'),
        no_receive(first, second, command, counts, [('frames', {'count': 4})])))

    def stopped():
        command(first, 'stop')
        command(first, 'frames')
        time.sleep(0.15)
        assert not counts(first)['held'] and not counts(first)['capturing']

    record('Release stops capture and fences further audio', stopped)

    def background():
        command(first, 'start', channel=1)
        wait_for(lambda: first.event('voice_grant_received', burst=3))
        command(first, 'focus_out')
        wait_for(lambda: not counts(first).get('held', True) and not counts(first).get('granted', True))
        command(first, 'focus_in')
        assert not counts(first)['capturing']

    record('Background stops PTT; foreground requires a fresh press', background)

    def flood():
        command(first, 'start', channel=1)
        wait_for(lambda: first.event('voice_grant_received', burst=4))
        command(first, 'frames', count=120)
        wait_for(lambda: server['process'].event('voice_rejected', reason='frame_rate'))

    record('Audio flood is bounded by server frame-rate limit', flood)
    lab.leave(server, first)
    lab.leave(server, second)
    record('Leave tears down both admitted sessions', lambda: assert_true(server['process'].event('disconnected', active=0, reserved=0)))
    lab.stop(server)

    def bad_certificate():
        other = lab.server('other-certificate')
        credential = lab.credential(other, 'player-1')
        process = lab.client(other, credential, hold=0.1, script='phone_probe.gd', timeout=3,
                             extra=['--certificate', str(server['certificate'])])
        result = process.process.wait(timeout=10)
        assert result != 0 and not process.event('client_admitted')
        assert not other['process'].event('admitted')
        # TLS verification failures may be printed by the engine; they are expected in this negative test.
        assert 'SCRIPT ERROR:' not in process.path.read_text()
        (other['state'] / 'stop').touch()
        assert other['process'].process.wait(timeout=8) == 0
        assert other['process'].event('server_stopped', active=0, reserved=0)
        errors = [line for line in other['process'].path.read_text().splitlines() if 'ERROR:' in line]
        assert errors and all(line == 'ERROR: TLS handshake error: -30592' for line in errors), errors

    record('A different server certificate fails closed', bad_certificate)

    def launcher_check(remote=False):
        host = '127.0.0.1' # The build sandbox has no LAN interface/route.
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as reservation:
            reservation.bind((host, 0))
            port = reservation.getsockname()[1]
        state = lab.temporary / ('pc-public-launcher' if remote else 'pc-launcher')
        mode = ['--public-address', '8.8.8.8:32100'] if remote else ['--local-only']
        with (lab.output / ('public-launcher.log' if remote else 'launcher.log')).open('w') as log:
            process = subprocess.Popen([sys.executable, str(ROOT / 'tools' / 'run_friends_server.py'), '--godot', str(lab.engine),
                *mode, '--port', str(port), '--state-dir', str(state), '--no-browser'], stdout=log, stderr=subprocess.STDOUT)
            try:
                wait_for(lambda: (state / 'invites.html').exists(), timeout=25)
                private = json.loads((state / 'admissions.json').read_text())
                lab.tokens.extend(x['join']['ticket'] for x in private['credentials'])
                server_info = {'ready': private['ready'], 'credentials': private['credentials'], 'certificate': state / 'server.crt'}
                assert private['ready']['host'] == host
                page = (state / 'invites.html').read_text(encoding='utf-8')
                encoded = html.unescape(re.search(r'<textarea[^>]*>([^<]+)</textarea>', page).group(1))
                payload = json.loads(base64.b64decode(encoded.removeprefix('MDV1.')))
                assert payload['host'] == ('8.8.8.8' if remote else host)
                assert payload['port'] == (32100 if remote else port)
                assert payload['credential'] == private['credentials'][0]
                assert payload['certificate'] == (state / 'server.crt').read_text()
                client = lab.driven(server_info, 'player-1')
                client.leave_path.touch()
                client.finish(0)
                assert 'PRIVATE KEY' not in (state / 'invites.html').read_text()
                (state / 'stop').touch()
                assert process.wait(timeout=8) == 0
                assert not (state / 'server.lock').exists()
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=5)

    record('PC launcher creates private invites, accepts a loopback client and stops cleanly', launcher_check)
    record('Tunnel invite advertises a public endpoint while the real DTLS server binds loopback', lambda: launcher_check(remote=True))
    tokens = lab.tokens
    logs = '\n'.join(process.path.read_text() for process in lab.processes)
    assert not any(token in logs for token in tokens)
    record('Logs contain no invitation tickets or raw PCM payloads', lambda: assert_true('DV01' not in logs))


def assert_true(value):
    assert value


def no_receive(sender, receiver, command, counts, actions):
    time.sleep(0.25)
    before = counts(receiver)['received']
    for action, fields in actions:
        command(sender, action, **fields)
    time.sleep(0.35)
    assert counts(receiver)['received'] == before


def main():
    if not __debug__:
        raise RuntimeError('Do not run evidence checks with Python -O')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    args = parser.parse_args()
    engine, identity = validate_engine(args.godot or ensure_engine())
    output = ROOT / 'builds' / 'friends-validation'
    output.mkdir(parents=True, exist_ok=True)
    report = {'timestamp_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'engine': identity,
              'build_id': source_id(ROOT), 'checks': [], 'scope': 'Linux desktop synthetic PCM over real ENet DTLS. No physical microphone/Android/Windows validation.'}
    with tempfile.TemporaryDirectory(prefix='maldiven-friends-test-') as name:
        directory = Path(name)
        project = directory / 'project'
        shutil.copytree(ROOT / 'experiments' / 'net-lab', project, ignore=shutil.ignore_patterns('.godot'))
        lab = FriendsLab(engine, project, directory, output)
        try:
            exercise(lab, report)
            report['passed'] = True
        except Exception as exc:
            report['passed'] = False
            report['failure'] = repr(exc)
            raise
        finally:
            lab.close()
            (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f"Passed {len(report['checks'])} friends checks. Report: {output / 'report.json'}")


if __name__ == '__main__':
    main()
