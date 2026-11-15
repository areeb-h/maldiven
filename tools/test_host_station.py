#!/usr/bin/env python3
"""End-to-end check of the dedicated server, its control channel and the panel.

Starts tools/host_station.py in test mode (no browser), checks the panel files
and the status/command API, then connects real headless bot clients
(scripts/dev/bot_driver.gd, --bot=client) to the PC server:

  A. three bots play a full crew round with the server as host (not a player):
     status shows the round with no roles, then the reveal after the result;
     the server returns to the lobby when everyone has left.
  B. two bots join; rename the station, kick one, start a round with a third,
     back to the lobby, then stop: the remaining phones are told the server
     is closing and the launcher exits cleanly.

Usage: python tools/test_host_station.py [--godot PATH] [--project PATH]
"""
import argparse
import http.client
import json
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

from bootstrap_godot import ROOT, ensure_engine, validate_engine

ERROR_MARKERS = ('SCRIPT ERROR', 'Parse Error', 'Compile Error')


class Failure(Exception):
    pass


def check(condition, message):
    if not condition:
        raise Failure(message)


class Proc:
    """A child process whose output is collected on a thread."""

    def __init__(self, args, label):
        self.label = label
        self.lines = []
        self.proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                     text=True, encoding='utf-8', errors='replace', bufsize=1)
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.proc.stdout:
            self.lines.append(line.rstrip('\n'))

    def has(self, prefix):
        return any(line.startswith(prefix) for line in self.lines)

    def wait_for(self, prefix, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            for line in self.lines:
                if line.startswith(prefix):
                    return line
            if self.proc.poll() is not None and not any(l.startswith(prefix) for l in self.lines):
                break
            time.sleep(0.1)
        raise Failure(f'{self.label}: no "{prefix}" within {timeout} s\n' + '\n'.join(self.lines[-40:]))

    def kill(self):
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait(timeout=10)


class Panel:
    def __init__(self, port):
        self.port = port

    def request(self, method, path, body=None, headers=None, host=None):
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=10)
        all_headers = {'Host': host or f'127.0.0.1:{self.port}'}
        if body is not None:
            all_headers.update({'Content-Type': 'application/json', 'X-Drift-Panel': '1'})
        all_headers.update(headers or {})
        conn.request(method, path, body=json.dumps(body) if body is not None else None, headers=all_headers)
        response = conn.getresponse()
        data = response.read()
        conn.close()
        return response.status, response.getheader('Content-Type', ''), data

    def status(self):
        code, _, data = self.request('GET', '/api/status')
        check(code == 200, f'/api/status answered {code}')
        return json.loads(data)

    def command(self, cmd, **args):
        code, _, data = self.request('POST', '/api/command', {'cmd': cmd, 'args': args})
        check(code == 200, f'{cmd}: HTTP {code}')
        return json.loads(data)

    def wait(self, condition, timeout, what):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            last = self.status()
            server = last.get('server')
            if server and condition(server):
                return server
            time.sleep(0.25)
        raise Failure(f'timed out waiting for {what}; last status: {json.dumps(last)[:1500]}')


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def wait_game_port_free(timeout=180):
    """Other test runs on this machine may be using UDP 24600; wait our turn."""
    deadline = time.time() + timeout
    while True:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            probe.bind(('0.0.0.0', 24600))
            return
        except OSError:
            if time.time() > deadline:
                raise Failure('UDP 24600 stayed busy (another server or test is running)')
            time.sleep(2)
        finally:
            probe.close()


def no_roles(status, phase):
    """During a round nothing in the status may name a role or the infiltrator."""
    text = json.dumps(status).lower()
    check('infiltrator' not in text and '"role' not in text,
          f'status leaks role information during {phase}: {text[:600]}')


def bot(engine, project, name, delay, timeout=170, plan='crew'):
    return Proc([str(engine), '--headless', '--path', str(project), '--', '--bot=client', f'--bot-name={name}',
                 f'--bot-join-delay={delay}', f'--bot-plan={plan}', f'--bot-timeout={timeout}'], name)


def godot_errors(lines):
    return [line for line in lines if any(marker in line for marker in ERROR_MARKERS)]


def run(engine, project):
    wait_game_port_free()
    port = free_port()
    launcher = Proc([sys.executable, str(ROOT / 'tools' / 'host_station.py'), '--test-mode', '--skip-import',
                     '--godot', str(engine), '--project', str(project), '--http-port', str(port),
                     '--room-name', 'Test  Station\u0007', '--auto-lobby', '0'], 'host_station')
    bots = []
    try:
        launcher.wait_for('HOST_STATION_READY', 120)
        panel = Panel(port)

        # Panel files, fonts and the API guards.
        for path, kind in [('/', 'text/html'), ('/style.css', 'text/css'), ('/app.js', 'javascript'), ('/qr.js', 'javascript'),
                           ('/favicon.svg', 'svg'), ('/fonts/orbitron-latin-700-normal.woff2', 'font/woff2'),
                           ('/fonts/rajdhani-latin-600-normal.woff2', 'font/woff2')]:
            code, content_type, data = panel.request('GET', path)
            check(code == 200 and kind in content_type and data, f'GET {path}: {code} {content_type}')
        check(b'Drift Station' in panel.request('GET', '/')[2], 'index.html has no title')
        check(panel.request('GET', '/../README.md')[0] == 404, 'path traversal not refused')
        check(panel.request('GET', '/fonts/../../README.md')[0] == 404, 'font path traversal not refused')
        check(panel.request('GET', '/api/status', host='evil.example:80')[0] == 403, 'foreign Host header not refused')
        check(panel.request('POST', '/api/command', {'cmd': 'stop'}, headers={'X-Drift-Panel': '0'})[0] == 403,
              'command without the panel header not refused')
        check(panel.command('nonsense').get('ok') is False, 'unknown command accepted')

        status = panel.status()
        check(status.get('app') == 'drift-station', 'status has no app id')
        server = status['server']
        check(server and server['state'] == 'lobby', f'expected lobby, got {server}')
        check(server['room_name'] == 'Test Station', f'room name not cleaned: {server["room_name"]!r}')
        check(server['players'] == [], 'the server must not be in the roster')
        check(server['port'] == 24600 and server['version'], 'status lacks port/version')
        reply = panel.command('start_round')
        check(reply['ok'] is False and 'at least 2' in (reply.get('error') or ''), f'start with nobody: {reply}')
        print('  panel, API guards and lobby status ok', flush=True)

        # A. A full round played by three phones (bots) on the PC server.
        bots = [bot(engine, project, f'P{i}', 0.3 * i) for i in range(1, 4)]
        server = panel.wait(lambda s: len(s['players']) == 3, 60, 'three players in the lobby')
        check(all(p['state'] == 'lobby' for p in server['players']), 'lobby players have a round state')
        check(len({p['color'] for p in server['players']}) == 3, 'players share a colour')
        reply = panel.command('start_round')
        check(reply['ok'], f'start_round: {reply}')
        server = panel.wait(lambda s: s['state'] in ('briefing', 'stabilise'), 30, 'the round to start')
        check('round' in server and server['round']['total'] > 0, 'round timer missing')
        no_roles(panel.status(), 'briefing')
        server = panel.wait(lambda s: s['state'] == 'stabilise', 40, 'the briefing to end')
        check(all(p['state'] == 'ok' for p in server['players']), f'player states: {server["players"]}')
        check(any(p['ping_ms'] >= 0 for p in server['players']), 'no ping')
        seen_states = set()

        def watch(s):
            seen_states.add(s['state'])
            if s['state'] != 'result':
                no_roles({'server': s}, s['state'])
            return s['state'] == 'result'

        server = panel.wait(watch, 200, 'the round result')
        check('extraction' in seen_states, f'never saw extraction: {seen_states}')
        result = server['round']['result']
        roles = {}
        for b in bots:
            line = b.wait_for('BOT_ROLE', 5)
            roles[b.label] = line.split()[1]
        infiltrator = [name for name, role in roles.items() if role == 'infiltrator']
        check(len(infiltrator) == 1, f'bot roles: {roles}')
        check(result['winner'] == 'crew', f'expected a crew win: {result}')
        check(result['infiltrator'] == infiltrator[0], f'reveal names {result["infiltrator"]}, bots say {infiltrator[0]}')
        check(len(result['timeline']) > 2, 'no timeline after the round')
        feed = ' | '.join(line['text'] for line in server['feed'])
        for expected in ('Round started with 3 crew aboard', 'Power cell 3/3 online', 'Shuttle launch sequence started',
                         'Crew win', f'The infiltrator was {infiltrator[0]}'):
            check(expected in feed, f'feed lacks "{expected}": {feed}')
        for b in bots:
            b.wait_for('BOT_RESULT winner=crew', 30)
            b.proc.wait(timeout=30)
            check(not godot_errors(b.lines), f'{b.label} errors:\n' + '\n'.join(godot_errors(b.lines)))
        panel.wait(lambda s: s['state'] == 'lobby' and not s['players'], 30, 'the lobby after everyone left')
        print(f'  full round on the PC server ok: crew win, infiltrator {infiltrator[0]} revealed only after the result',
              flush=True)

        # B. Rename, kick, start, back to lobby, stop.
        bots = [bot(engine, project, 'K1', 0.2, timeout=120), bot(engine, project, 'K2', 0.6, timeout=120)]
        server = panel.wait(lambda s: len(s['players']) == 2, 60, 'two players for part B')
        reply = panel.command('set_room_name', name='  Night   Shift ')
        check(reply['ok'], f'set_room_name: {reply}')
        panel.wait(lambda s: s['room_name'] == 'Night Shift', 5, 'the new room name')
        kicked = next(p for p in server['players'] if p['name'] == 'K1')
        check(panel.command('kick', id=kicked['id'])['ok'], 'kick failed')
        bots[0].wait_for('BOT_SESSION_ENDED You were removed', 15)
        panel.wait(lambda s: [p['name'] for p in s['players']] == ['K2'], 15, 'K1 to leave')
        check(panel.command('kick', id=999)['ok'] is False, 'kicking a stranger succeeded')
        bots.append(bot(engine, project, 'K3', 0.2, timeout=120))
        panel.wait(lambda s: len(s['players']) == 2, 60, 'K3 to join')
        check(panel.command('start_round')['ok'], 'second start_round failed')
        panel.wait(lambda s: s['state'] in ('briefing', 'stabilise'), 30, 'the second round')
        check(panel.command('start_round')['ok'] is False, 'start_round accepted mid-round')
        check(panel.command('back_to_lobby')['ok'], 'back_to_lobby failed')
        panel.wait(lambda s: s['state'] == 'lobby' and len(s['players']) == 2, 20, 'the lobby again')
        check(panel.command('back_to_lobby')['ok'] is False, 'back_to_lobby accepted in the lobby')
        print('  rename, kick, start and back to lobby ok', flush=True)

        check(panel.command('stop')['ok'], 'stop failed')
        for b in bots[1:]:
            b.wait_for('BOT_SESSION_ENDED The host shut down the server', 15)
        deadline = time.time() + 20
        while time.time() < deadline and panel.status()['launcher']['state'] != 'stopped':
            time.sleep(0.2)
        check(panel.status()['launcher']['state'] == 'stopped', 'launcher did not report the server stopped')
        print('  stop: phones told the server is closing', flush=True)

        # Restart from the panel, then Ctrl+C-style shutdown of the launcher.
        code, _, _ = panel.request('POST', '/api/restart', {})
        check(code == 200, 'restart refused')
        panel.wait(lambda s: s['state'] == 'lobby', 60, 'the restarted server')
        launcher.proc.terminate()  # SIGTERM: same path as Ctrl+C
        launcher.proc.wait(timeout=30)
        check(launcher.proc.returncode == 0, f'launcher exit code {launcher.proc.returncode}')
        launcher.wait_for('HOST_STATION_STOPPED', 5)
        errors = godot_errors(launcher.lines)
        check(not errors, 'server errors:\n' + '\n'.join(errors))
        print('  restart and clean shutdown ok', flush=True)
    except Failure:
        print('\n'.join(line for line in launcher.lines[-60:]))
        raise
    finally:
        for b in bots:
            b.kill()
        launcher.kill()


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--godot')
    parser.add_argument('--project', type=Path, default=ROOT)
    args = parser.parse_args()
    engine, _ = validate_engine(args.godot or ensure_engine())
    try:
        run(engine, args.project.resolve())
    except Failure as exc:
        print(f'FAILED: {exc}')
        return 1
    print('DEDICATED SERVER CHECKS PASSED')
    return 0


if __name__ == '__main__':
    sys.exit(main())
