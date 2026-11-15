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
        code, _, data = panel.request('POST', '/api/command', {'cmd': 'nonsense', 'args': {}})
        check(code == 400 and json.loads(data)['ok'] is False, 'unknown command accepted')

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
                         'Crew wins', f'The infiltrator was {infiltrator[0]}'):
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


def unit_tests():
    """Address classification (WSL NAT/mirrored, plain LAN) with fake interface lists."""
    import contextlib
    import io
    import host_station as hs
    hs.primary_address = lambda: None  # no real network lookups in unit tests
    cases = [
        # (interfaces, wsl, windows_ip, expected mode, expected lan, expected internal)
        ([('lo', '127.0.0.1'), ('lo', '10.255.255.254'), ('eth0', '172.21.39.63')], True, '192.168.1.42',
         'nat', [], ['172.21.39.63']),
        ([('lo', '127.0.0.1'), ('eth0', '172.21.39.63')], True, None, 'nat', [], ['172.21.39.63']),
        ([('lo', '127.0.0.1'), ('lo', '10.255.255.254'), ('eth0', '172.30.1.2'), ('eth1', '192.168.1.42')], True,
         '192.168.1.42', 'mirrored', ['192.168.1.42'], []),
        ([('eth0', '172.20.0.15'), ('lo', '10.255.255.254')], True, '172.20.0.15', 'mirrored', ['172.20.0.15'], []),
        ([('eth0', '10.0.0.7'), ('lo', '10.255.255.254')], True, None, 'mirrored', ['10.0.0.7'], []),
        ([('lo', '127.0.0.1'), ('eth0', '192.168.0.10'), ('docker0', '172.17.0.1'), ('tun0', '8.8.8.8')], False, None,
         None, ['192.168.0.10', '172.17.0.1'], []),
        (None, False, None, None, ['192.168.0.5'], []),
    ]
    for interfaces, wsl, windows_ip, mode, lan, internal in cases:
        got = hs.classify_network(interfaces, wsl, ['10.255.255.254', '192.168.0.5'], windows_ip)
        check((got['mode'], got['lan'], got['internal']) == (mode, lan, internal),
              f'classify_network({interfaces}, wsl={wsl}, windows={windows_ip}) -> {got}')
    # 10.255.255.254 never shows up, whatever the source.
    for base in [{'source': 'server', 'wsl': False, 'windows_ip': None},
                 dict(hs.classify_network([('lo', '10.255.255.254'), ('eth0', '192.168.3.4')], True), source='interfaces')]:
        got = hs.network_for(base, ['10.255.255.254', '192.168.3.4'])
        check('10.255.255.254' not in got['lan'] and got['lan'][:1] == ['192.168.3.4'], f'network_for: {got}')
    # The owner's WSL: NAT plus Tailscale. Tailscale becomes the primary join address.
    owner = [('lo', '127.0.0.1'), ('lo', '10.255.255.254'), ('eth0', '172.21.39.63'), ('tailscale0', '100.92.33.25')]
    got = hs.classify_network(owner, True, (), None)
    check(got['mode'] == 'nat' and got['lan'] == [] and got['tailscale'] == ['100.92.33.25']
          and got['primary'] == '100.92.33.25', f'NAT + Tailscale: {got}')
    got = hs.classify_network([('eth0', '192.168.0.10'), ('ts', '100.100.1.2')], False)
    check(got['lan'] == ['192.168.0.10'] and got['tailscale'] == ['100.100.1.2'] and got['primary'] == '192.168.0.10',
          f'LAN + Tailscale (CGNAT range, any interface name): {got}')
    check(hs.classify_network([('eth0', '100.128.0.1')], False)['tailscale'] == [], '100.128/10 is not Tailscale')

    def console(network, **extra):
        options = argparse.Namespace(public_address=None, public_label='Internet', playit_detected=False,
                                     firewall={'state': 'unknown', 'notes': []}, network=dict(network, source='interfaces'))
        vars(options).update(extra)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            hs.print_summary(hs.Console(machine=True), status, options, 'http://127.0.0.1:24680')
        return out.getvalue()

    def in_order(text, *needles):
        places = [text.find(needle) for needle in needles]
        check(all(place >= 0 for place in places) and places == sorted(places),
              f'console order {needles} -> {places}:\n{text}')

    status = {'version': '0', 'room_name': 'T', 'addresses': ['172.21.39.63', '10.255.255.254']}
    nat = hs.classify_network([('lo', '10.255.255.254'), ('eth0', '172.21.39.63')], True, (), '192.168.1.42')
    text = console(nat)
    check("WSL is in NAT mode, so phones can't reach this server" in text, 'NAT warning missing:\n' + text)
    for refuse in ('█', 'also ', 'Tailscale:'):
        check(refuse not in text, f'NAT console shows {refuse!r}:\n{text}')
    in_order(text, r'py -3 tools\host_station.py', 'let a phone host', 'Advanced: WSL mirrored networking',
             "Docker Desktop's WSL integration", 'networkingMode=mirrored', 'Set-NetFirewallHyperVVMSetting', 'wsl --shutdown')
    text = console(hs.classify_network(owner, True, (), None))
    check('█' in text, 'Tailscale address not shown big in NAT mode')
    in_order(text, 'Phones with Tailscale', 'Tailscale: 100.92.33.25', "phones on your Wi-Fi can't reach",
             r'py -3 tools\host_station.py', 'let a phone host', 'networkingMode=mirrored')
    text = console(hs.classify_network([('lo', '10.255.255.254'), ('eth1', '192.168.1.42'), ('eth0', '172.30.1.2')],
                                       True, (), '192.168.1.42'))
    for needle in ('Set-NetFirewallHyperVVMSetting', 'mirrored networking'):
        check(needle in text, f'mirrored console lacks {needle!r}:\n{text}')
    for refuse in ('NAT mode', '10.255.255.254', '172.30.1.2'):
        check(refuse not in text, f'mirrored console shows {refuse!r}:\n{text}')

    # --public-address: same rules as NetAddress.parse; shown as a labelled join option.
    for raw, shown in [('abc.playit.gg:12345', 'abc.playit.gg:12345'), (' udp://abc.playit.gg:12345/ ', 'abc.playit.gg:12345'),
                       ('203.0.113.7', '203.0.113.7:24600'), ('[fd7a::1]:24600', '[fd7a::1]:24600'),
                       ('fd7a:115c::1', '[fd7a:115c::1]:24600'), ('my-pc.tail1234.ts.net:24600', 'my-pc.tail1234.ts.net:24600')]:
        check(hs.public_address_arg(raw) == shown, f'public address {raw!r} -> {hs.public_address_arg(raw)!r}')
    for raw, error in [('abc.playit.gg:0', 'bad_port'), ('abc.playit.gg:65536', 'bad_port'), ('abc.playit.gg:x', 'bad_port'),
                       ('192.168.1.300', 'bad_host'), ('nodots', 'bad_host'), ('', 'empty'), ('[fd7a::1', 'bad_ipv6'),
                       ('bad_name.example:1', 'bad_host')]:
        check(hs.parse_address(raw)['error'] == error, f'parse_address({raw!r}) -> {hs.parse_address(raw)}')
    with contextlib.redirect_stderr(io.StringIO()):
        try:
            hs.parse_args(['--public-address', 'abc.playit.gg:99999'])
            check(False, 'a bad --public-address was accepted')
        except SystemExit:
            pass
    parsed = hs.parse_args(['--public-address', 'abc.playit.gg:12345', '--public-label', 'playit'])
    check((parsed.public_address, parsed.public_label) == ('abc.playit.gg:12345', 'playit'), f'args: {parsed}')
    lan = hs.classify_network([('eth0', '192.168.0.10')], False)
    text = console(lan, public_address='abc.playit.gg:12345')
    check('Internet (anyone, no app needed): abc.playit.gg:12345' in text, 'public join option missing:\n' + text)
    check('playit (anyone, no app needed)' in console(lan, public_address='a.playit.gg:1', public_label='playit'),
          '--public-label not used')
    in_order(console(hs.classify_network(owner, True, (), None), public_address='abc.playit.gg:12345'),
             'Tailscale: 100.92.33.25', 'Internet (anyone, no app needed)', "can't reach", 'The internet tunnel')
    check('playit agent detected' in console(lan, playit_detected=True), 'playit hint missing')
    check('playit agent detected' not in console(lan, playit_detected=True, public_address='a.playit.gg:1'),
          'playit hint shown although the address is set')
    # The Round card's empty-lobby line only promises routes that reach the server.
    mirrored = hs.classify_network([('eth1', '192.168.1.42'), ('lo', '10.255.255.254')], True, (), '192.168.1.42')
    nat_only = hs.classify_network([('lo', '10.255.255.254'), ('eth0', '172.21.39.63')], True)
    wifi = 'Waiting for the crew. Phones on this Wi-Fi can see the station now.'
    for network, public, expected in [
            (hs.classify_network(owner, True), None, 'Waiting for the crew. Phones join by IP over Tailscale (100.92.33.25).'),
            (hs.classify_network(owner, True), 'abc.playit.gg:12345',
             'Waiting for the crew. Phones join by IP over Tailscale (100.92.33.25) or at abc.playit.gg:12345.'),
            (nat_only, None, 'Waiting for the crew. Only this PC can reach the station; see the steps in Join from a phone.'),
            (nat_only, 'abc.playit.gg:12345', "Waiting for the crew. Phones join by IP at abc.playit.gg:12345; phones on "
                                              "your Wi-Fi can't reach this PC directly (see Join from a phone)."),
            (lan, None, wifi), (mirrored, None, wifi),
            (lan, 'abc.playit.gg:12345', wifi + ' Friends elsewhere join by IP at abc.playit.gg:12345.')]:
        got = hs.lobby_hint(network, public)
        check(got == expected, f'lobby hint for {network["mode"]}/{network["tailscale"]}/{public}: {got!r}')
        check('Wi-Fi can see' not in got or network['mode'] != 'nat', f'NAT lobby hint promises Wi-Fi: {got!r}')
    print('  address classification (WSL NAT / mirrored / Tailscale / LAN), lobby hint and --public-address ok', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--godot')
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--unit-only', action='store_true', help='Only the fast checks (no Godot)')
    args = parser.parse_args()
    try:
        unit_tests()
        if args.unit_only:
            print('DEDICATED SERVER UNIT CHECKS PASSED')
            return 0
        engine, _ = validate_engine(args.godot or ensure_engine())
        run(engine, args.project.resolve())
    except Failure as exc:
        print(f'FAILED: {exc}')
        return 1
    print('DEDICATED SERVER CHECKS PASSED')
    return 0


if __name__ == '__main__':
    sys.exit(main())
