#!/usr/bin/env python3
"""Run the LAN-only Friends Lab server and create private, single-use phone invites."""
import argparse
import csv
import getpass
import html
import ipaddress
import json
import os
import socket
import subprocess
import time
import webbrowser
from pathlib import Path

from bootstrap_godot import ROOT, ensure_engine, validate_engine


def private_directory(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name == 'nt':
        identity = subprocess.run(['whoami', '/user', '/fo', 'csv', '/nh'], capture_output=True, text=True, check=True)
        sid = next(csv.reader(identity.stdout.strip().splitlines()))[1]
        subprocess.run(['icacls', str(path), '/inheritance:r', '/grant:r',
                        '*' + sid + ':(OI)(CI)F', '*S-1-5-18:(OI)(CI)F'], check=True, capture_output=True)
    else:
        path.chmod(0o700)


def local_address():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        # Select a local interface through the route table; no datagram is sent.
        sock.connect(('192.0.2.1', 9))
        return sock.getsockname()[0]


def lan_address(value):
    address = ipaddress.ip_address(value)
    if address.version != 4 or not address.is_private or address.is_loopback or address.is_link_local or address.is_unspecified or address.is_multicast:
        raise ValueError('Use the PC Wi-Fi/Ethernet private IPv4 address, such as 192.168.1.20. See ipconfig.')
    return str(address)


def default_state():
    if os.name == 'nt':
        return Path(os.environ.get('LOCALAPPDATA', Path.home() / 'AppData' / 'Local')) / 'Maldiven' / 'FriendsLab'
    return Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local' / 'state')) / 'maldiven-friends'


def write_invites(path, host, port, certificate, credentials):
    import base64
    cards = []
    for item in credentials:
        payload = dict(host=host, port=port, certificate=certificate, credential=item)
        invite = 'MDV1.' + base64.b64encode(json.dumps(payload, separators=(',', ':')).encode('ascii')).decode('ascii')
        slot = item['player_id'].replace('player-', '')
        suffix = 'A' if item['issuance'] == 0 else 'B (retry)'
        cards.append('<section><h2>Crew ' + slot + ' · Invite ' + suffix + '</h2><textarea readonly onclick="this.select()">' + html.escape(invite) + '</textarea></section>')
    path.write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<title>Maldiven private invites</title><style>body{background:#091722;color:#dfefed;font:18px system-ui;max-width:900px;margin:40px auto;padding:20px}h1{color:#8fe0df}section{background:#112b39;padding:20px;margin:16px 0;border-radius:16px}textarea{box-sizing:border-box;width:100%;height:90px;font:14px monospace}strong{color:#a8e4d0}</style>
<h1>Maldiven / Friends Lab</h1><p><strong>Private invites — do not publish this page.</strong></p>
<p>Copy a complete MDV1. invite to your phone, open Maldiven Friends Lab, choose Paste invite, then Connect to PC. Give each person a different crew slot. A and B belong to the same person; B is for retrying after a leave. Both expire 10 minutes after the server starts. Connected sessions stay connected.</p>
<p>PC address: ''' + html.escape(host) + ' · UDP ' + str(port) + '''. Keep the server terminal open and use the same Wi-Fi. Headphones first. No internet relay or echo cancellation in this experiment.</p>''' + ''.join(cards) + '</html>', encoding='utf-8')
    if os.name != 'nt':
        path.chmod(0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', help='Godot 4.7.2 Standard executable; on Windows choose the _console.exe')
    parser.add_argument('--host', help='PC LAN IPv4 address to bind and include in invites (auto-detected otherwise)')
    parser.add_argument('--local-only', action='store_true', help='Desktop development only: bind 127.0.0.1; phones cannot reach this room')
    parser.add_argument('--port', type=int, default=24567)
    parser.add_argument('--state-dir', type=Path, default=default_state())
    parser.add_argument('--no-browser', action='store_true')
    args = parser.parse_args()
    server = None
    try:
        if not 1024 <= args.port <= 65535:
            raise ValueError('--port must be between 1024 and 65535')
        if args.local_only and args.host:
            raise ValueError('Choose --local-only or --host, not both')
        host = '127.0.0.1' if args.local_only else lan_address(args.host or local_address())
        engine, _ = validate_engine(args.godot or ensure_engine())
        state = args.state_dir.expanduser().resolve()
        if state == ROOT or ROOT in state.parents:
            raise ValueError('Keep --state-dir outside the repository; it contains private credentials.')
        private_directory(state)
        # One launcher per state directory. A lock is removed only on a clean exit.
        lock = state / 'server.lock'
        try:
            descriptor = os.open(lock, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            raise ValueError('Server state is locked. Close the other server. After a crash, remove server.lock from ' + str(state))
        os.close(descriptor)
        try:
            key, certificate = state / 'server.key', state / 'server.crt'
            if key.exists() != certificate.exists():
                raise ValueError('Incomplete certificate pair. Move server.key and server.crt aside together, then restart.')
            project = ROOT / 'experiments' / 'net-lab'
            if not key.exists():
                subprocess.run([str(engine), '--headless', '--path', str(project), '--script', 'res://create_certificate.gd', '--', str(key), str(certificate)], check=True)
            log_path = state / 'server.log'
            (state / 'ready.json').unlink(missing_ok=True)
            with log_path.open('w') as log:
                server = subprocess.Popen([str(engine), '--headless', '--path', str(project), '--script', 'res://phone_server.gd', '--',
                    '--state-dir', str(state), '--bind', host, '--port', str(args.port), '--ticket-ttl', '600',
                    '--certificate', str(certificate), '--private-key', str(key)], stdout=log, stderr=subprocess.STDOUT)
                deadline = time.monotonic() + 20
                while not (state / 'ready.json').exists():
                    if server.poll() is not None or time.monotonic() > deadline:
                        raise RuntimeError('Server did not start. Read ' + str(log_path) + ' (check the IP, port and Godot version).')
                    time.sleep(0.05)
                admissions = json.loads((state / 'admissions.json').read_text())
                page = state / 'invites.html'
                write_invites(page, host, args.port, certificate.read_text(), admissions['credentials'])
                print(f'Friends Lab listening on {host}:{args.port} UDP. Keep this window open.', flush=True)
                if args.local_only:
                    print('Local-only development room: a phone cannot connect to this address.', flush=True)
                print('Private invite page: ' + str(page), flush=True)
                print('Use a different crew slot per phone. Invites expire in 10 minutes. Ctrl+C stops the room.', flush=True)
                if not args.no_browser:
                    webbrowser.open(page.as_uri())
                try:
                    while server.poll() is None:
                        time.sleep(0.25)
                except KeyboardInterrupt:
                    pass
                finally:
                    if server.poll() is None:
                        (state / 'stop').touch()
                        try:
                            server.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            server.terminate()
                            server.wait(timeout=5)
                if server.returncode not in (0, None):
                    raise RuntimeError('Server exited with an error. Read ' + str(log_path))
        finally:
            if server is not None and server.poll() is None:
                server.terminate()
                server.wait(timeout=5)
            lock.unlink(missing_ok=True)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        parser.exit(1, str(exc) + '\n')


if __name__ == '__main__':
    main()
