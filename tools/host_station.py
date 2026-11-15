#!/usr/bin/env python3
"""Host a Drift Station server on this computer.

    python tools/host_station.py            (Windows: py tools\\host_station.py)

Downloads the pinned Godot 4.7.2 on first use, starts the game as a headless
dedicated server (the PC hosts, the phones play) and opens the control panel at
http://127.0.0.1:24680 (this computer only). Phones on the same Wi-Fi find the
station under "Nearby stations". Press Ctrl+C to close the station: phones are
told the server is closing, then everything shuts down.

Needs Python 3.11+ and nothing else. See docs/hosting.md.
"""
import argparse
import collections
import getpass
import json
import os
import platform
import re
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

if sys.version_info < (3, 11):
    sys.exit('Drift Station needs Python 3.11 or newer (python.org/downloads).')

from bootstrap_godot import ROOT, ensure_engine, validate_engine  # noqa: E402

GAME_PORT = 24600
DISCOVERY_PORT = 24601
PANEL_PORT = 24680
PANEL_DIR = ROOT / 'tools' / 'server_panel'
FONT_DIR = ROOT / 'assets' / 'fonts'
STATE_DIR = ROOT / 'tools' / '.cache' / 'host_station'
STATIC = {'/': ('index.html', 'text/html; charset=utf-8'),
          '/index.html': ('index.html', 'text/html; charset=utf-8'),
          '/style.css': ('style.css', 'text/css; charset=utf-8'),
          '/app.js': ('app.js', 'text/javascript; charset=utf-8'),
          '/qr.js': ('qr.js', 'text/javascript; charset=utf-8'),
          '/favicon.svg': ('favicon.svg', 'image/svg+xml')}
COMMANDS = {'start_round', 'back_to_lobby', 'kick', 'set_room_name', 'stop'}
FIREWALL_RULE = ('netsh advfirewall firewall add rule name="Drift Station server" dir=in action=allow '
                 f'protocol=UDP localport={GAME_PORT}-{DISCOVERY_PORT} profile=private')
CSP = ("default-src 'none'; script-src 'self'; style-src 'self'; font-src 'self'; img-src 'self' data:; "
       "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")


# --- Console -----------------------------------------------------------------

class Console:
    """Plain, readable console output; colour only on a real terminal."""

    def __init__(self, machine=False):
        self.machine = machine
        self.color = not machine and sys.stdout.isatty() and 'NO_COLOR' not in os.environ and _enable_ansi()
        self.lock = threading.Lock()

    def paint(self, text, *codes):
        return f'\033[{";".join(codes)}m{text}\033[0m' if self.color and codes else text

    def line(self, text=''):
        with self.lock:
            try:
                print(text, flush=True)
            except UnicodeEncodeError:
                print(text.encode('ascii', 'replace').decode(), flush=True)

    def info(self, text):
        self.line('  ' + text)

    def warn(self, text):
        self.line('  ' + self.paint('!', '1', '33') + ' ' + text)

    def error(self, text):
        self.line('  ' + self.paint('x', '1', '31') + ' ' + text)

    def event(self, text):
        self.line('  ' + self.paint(time.strftime('%H:%M:%S'), '2') + '  ' + text)


def _enable_ansi():
    if os.name != 'nt':
        return True
    try:  # Windows 10+: turn on VT sequences for this console
        import ctypes
        kernel = ctypes.windll.kernel32
        handle = kernel.GetStdHandle(-11)
        mode = ctypes.c_uint32()
        if not kernel.GetConsoleMode(handle, ctypes.byref(mode)):
            return False
        return bool(kernel.SetConsoleMode(handle, mode.value | 0x0004))
    except (AttributeError, OSError):
        return False


# 5-row block font for the join address: digits, dot and colon.
_GLYPHS = {
    '0': ['███', '█ █', '█ █', '█ █', '███'], '1': [' █ ', '██ ', ' █ ', ' █ ', '███'],
    '2': ['███', '  █', '███', '█  ', '███'], '3': ['███', '  █', '███', '  █', '███'],
    '4': ['█ █', '█ █', '███', '  █', '  █'], '5': ['███', '█  ', '███', '  █', '███'],
    '6': ['███', '█  ', '███', '█ █', '███'], '7': ['███', '  █', '  █', '  █', '  █'],
    '8': ['███', '█ █', '███', '█ █', '███'], '9': ['███', '█ █', '███', '  █', '███'],
    '.': [' ', ' ', ' ', ' ', '█'], ':': [' ', '█', ' ', '█', ' '],
}


def big_text(text):
    """The address in 5-row block digits, or None if it can't be drawn here."""
    if not text or any(ch not in _GLYPHS for ch in text):
        return None
    rows = [' '.join(_GLYPHS[ch][row] for ch in text) for row in range(5)]
    width = shutil.get_terminal_size((100, 24)).columns
    if len(rows[0]) + 4 > width:
        return None
    try:
        '█'.encode(sys.stdout.encoding or 'utf-8')
    except (UnicodeEncodeError, LookupError):
        rows = [row.replace('█', '#') for row in rows]
    return rows


# --- Network helpers ---------------------------------------------------------

def primary_address():
    """The LAN address of the interface with the default route (no traffic is sent)."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(('10.255.255.255', 1))
        address = probe.getsockname()[0]
    except OSError:
        return None
    finally:
        probe.close()
    return address if is_private(address) else None


def is_private(address):
    parts = address.split('.')
    if len(parts) != 4 or not all(p.isdigit() for p in parts):
        return False
    a, b = int(parts[0]), int(parts[1])
    return a == 10 or (a == 192 and b == 168) or (a == 172 and 16 <= b <= 31)


def udp_port_free(port):
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.bind(('0.0.0.0', port))
        return True
    except OSError:
        return False
    finally:
        probe.close()


def free_local_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


def existing_panel(port):
    """True if a Drift Station panel already answers on this port."""
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=1.0) as conn:
            conn.sendall(f'GET /api/status HTTP/1.0\r\nHost: 127.0.0.1:{port}\r\n\r\n'.encode())
            data = conn.recv(4096)
        return b'"drift-station"' in data
    except OSError:
        return False


# --- Firewall ------------------------------------------------------------------

_WINDOWS_FIREWALL_PS = r'''
$ErrorActionPreference = 'SilentlyContinue'
$on = @(Get-NetFirewallProfile | Where-Object { $_.Enabled } | ForEach-Object { [string]$_.Name })
$category = @(Get-NetConnectionProfile | ForEach-Object { [string]$_.NetworkCategory })
$ports = @{}; Get-NetFirewallPortFilter -All | ForEach-Object { $ports[$_.InstanceID] = $_ }
$apps = @{}; Get-NetFirewallApplicationFilter -All | ForEach-Object { $apps[$_.InstanceID] = $_ }
$allow = 0; $block = 0
foreach ($rule in Get-NetFirewallRule -Direction Inbound -Enabled True) {
  $p = $ports[$rule.InstanceID]; $a = $apps[$rule.InstanceID]
  $program = if ($a) { [string]$a.Program } else { 'Any' }
  $godot = $program -like '*Godot_v4*'
  $udp = $p -and ([string]$p.Protocol -in @('UDP', 'Any'))
  $port = $p -and (@($p.LocalPort) | Where-Object { $_ -eq 'Any' -or $_ -eq '24600' -or $_ -eq '24600-24601' }).Count -gt 0
  if ([string]$rule.Action -eq 'Block' -and $godot) { $block++ }
  elseif ([string]$rule.Action -eq 'Allow' -and $udp -and (($port -and $program -eq 'Any') -or $godot)) { $allow++ }
}
@{ enabled = $on; categories = $category; allow = $allow; block = $block } | ConvertTo-Json -Compress
'''


def firewall_check():
    """Best guess whether phones can reach UDP 24600/24601. Never changes anything."""
    system = platform.system()
    result = {'os': system, 'state': 'unknown', 'command': None, 'notes': []}
    if system == 'Windows':
        result['command'] = FIREWALL_RULE
        try:
            out = subprocess.run(['powershell', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
                                  '-Command', _WINDOWS_FIREWALL_PS], capture_output=True, text=True, timeout=25,
                                 creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)).stdout
            data = json.loads(out.strip().splitlines()[-1])
        except (OSError, subprocess.SubprocessError, ValueError, IndexError):
            result['notes'].append('Could not read the Windows Firewall settings.')
            return result
        enabled = data.get('enabled') or []
        enabled = [enabled] if isinstance(enabled, str) else enabled
        categories = data.get('categories') or []
        categories = [categories] if isinstance(categories, str) else categories
        if 'Public' in categories:
            result['notes'].append('Windows treats this network as Public, which blocks most incoming traffic. '
                                   'On your home Wi-Fi, set it to Private: Settings > Network & internet > Wi-Fi > '
                                   'your network > Network profile type > Private.')
        if not enabled:
            result['state'] = 'off'
        elif data.get('block', 0):
            result['state'] = 'blocked'
        elif data.get('allow', 0):
            result['state'] = 'allowed'
        else:
            result['state'] = 'likely_blocked'
    elif system == 'Darwin':
        try:
            out = subprocess.run(['/usr/libexec/ApplicationFirewall/socketfilterfw', '--getglobalstate'],
                                 capture_output=True, text=True, timeout=5).stdout
            result['state'] = 'prompt' if 'enabled' in out.lower() else 'off'
        except (OSError, subprocess.SubprocessError):
            pass
        if result['state'] == 'prompt':
            result['notes'].append('macOS may ask whether Godot may "accept incoming network connections": click Allow.')
    elif system == 'Linux' and shutil.which('ufw'):
        result['notes'].append(f'If ufw is active: sudo ufw allow {GAME_PORT}:{DISCOVERY_PORT}/udp')
    return result


# --- Project preparation ---------------------------------------------------------

_IMPORT_STAMP = '.godot/host_station_import.json'
_SOURCE_SUFFIXES = {'.gd', '.tscn', '.tres', '.png', '.jpg', '.svg', '.wav', '.ogg', '.mp3', '.woff2', '.ttf',
                    '.glb', '.gltf', '.obj', '.godot', '.import', '.gdshader'}


def _newest_source(project):
    newest = 0.0
    skip = {'.godot', '.git', '.cache', 'builds', 'experiments', '__pycache__', 'node_modules'}
    for folder, dirs, files in os.walk(project):
        dirs[:] = [d for d in dirs if d not in skip]
        for name in files:
            if os.path.splitext(name)[1] in _SOURCE_SUFFIXES:
                try:
                    newest = max(newest, os.stat(os.path.join(folder, name)).st_mtime)
                except OSError:
                    pass
    return newest


def prepare_project(engine, project, console):
    """Run Godot's one-time import (fonts, textures, script classes) when needed."""
    stamp = project / _IMPORT_STAMP
    newest = _newest_source(project)
    try:
        if json.loads(stamp.read_text()).get('newest', 0) >= newest and (project / '.godot' / 'imported').is_dir():
            return
    except (OSError, ValueError):
        pass
    console.info('Preparing the station files (first run or after an update; about a minute)...')
    result = subprocess.run([str(engine), '--headless', '--path', str(project), '--editor', '--import', '--quit'],
                            capture_output=True, text=True, timeout=900, **_child_flags())
    if result.returncode != 0:
        tail = '\n'.join((result.stdout + result.stderr).splitlines()[-15:])
        raise RuntimeError('Godot could not import the project:\n' + tail)
    stamp.write_text(json.dumps({'newest': newest, 'at': time.time()}))


def _kill_tree(process, force):
    """Windows: the console exe starts the real engine as its child, so end the whole tree."""
    if os.name == 'nt':
        subprocess.run(['taskkill', '/T', '/PID', str(process.pid)] + (['/F'] if force else []),
                       capture_output=True, timeout=10, creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
    elif force:
        process.kill()
    else:
        process.terminate()


def _child_flags():
    """Keep Ctrl+C away from Godot: the launcher shuts it down cleanly instead."""
    if os.name == 'nt':
        return {'creationflags': subprocess.CREATE_NEW_PROCESS_GROUP}
    return {'start_new_session': True}


# --- Settings -----------------------------------------------------------------------

def load_settings():
    try:
        return json.loads((STATE_DIR / 'settings.json').read_text())
    except (OSError, ValueError):
        return {}


def save_settings(settings):
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        temporary = STATE_DIR / 'settings.json.tmp'
        temporary.write_text(json.dumps(settings, indent=2))
        temporary.replace(STATE_DIR / 'settings.json')
    except OSError:
        pass


def default_room_name():
    try:
        user = getpass.getuser()
    except (OSError, KeyError, ImportError):
        user = ''
    user = re.split(r'[._\-\s@]', user)[0]
    if user.isalpha() and 2 <= len(user) <= 16 and user.lower() not in {'root', 'admin', 'administrator', 'user', 'owner', 'pc', 'guest'}:
        return f"{user.capitalize()}'s station"
    return 'Drift Station'


def clean_room_name(text):
    text = re.sub(r'\s+', ' ', ''.join(' ' if ord(ch) < 32 or ord(ch) == 127 else ch for ch in str(text))).strip()
    return text[:32].strip() or 'Drift Station'


# --- The Godot process and its control link ---------------------------------------

class Station:
    """Owns the headless Godot server: start, stop, restart, status and commands."""

    def __init__(self, engine, project, options, console):
        self.engine, self.project, self.options, self.console = engine, project, options, console
        self.lock = threading.RLock()
        self.process = None
        self.state = 'stopped'  # starting / running / stopping / stopped / crashed
        self.error = None
        self.exit_code = None
        self.status = None  # latest status document from the server
        self.status_at = 0.0
        self.log = collections.deque(maxlen=300)
        self.started_at = 0.0
        self.ready = threading.Event()
        self.on_ready = None
        self.on_status = None
        self._sock = None
        self._send_lock = threading.Lock()
        self._next_id = 0
        self._pending = {}
        self._generation = 0
        self._stop_requested = False
        self.room_name = options.room_name

    # Lifecycle -----------------------------------------------------------------

    def start(self):
        with self.lock:
            if self.process is not None and self.process.poll() is None:
                return
            if not udp_port_free(GAME_PORT):
                self.state, self.error = 'crashed', (
                    f'UDP port {GAME_PORT} is already in use. Close Drift Station (or another server) on this '
                    'computer, then press Restart.')
                self.console.error(self.error)
                return
            self._generation += 1
            generation = self._generation
            self.control_port = free_local_port()
            self.token = secrets.token_hex(16)
            self.state, self.error, self.exit_code, self.status = 'starting', None, None, None
            self._stop_requested = False
            self.ready.clear()
            self.log.clear()
            args = [str(self.engine), '--headless', '--path', str(self.project), '--', '--dedicated',
                    f'--room-name={self.room_name}', f'--max-players={self.options.max_players}',
                    f'--control-port={self.control_port}', f'--control-token={self.token}',
                    f'--auto-lobby={self.options.auto_lobby}']
            log_path = self._log_path()
            log_file = log_path.open('w', encoding='utf-8', errors='replace') if log_path else None
            self.process = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                            text=True, encoding='utf-8', errors='replace', bufsize=1, **_child_flags())
            self.started_at = time.time()
            threading.Thread(target=self._read_output, args=(self.process, generation, log_file), daemon=True).start()
            threading.Thread(target=self._control_loop, args=(self.process, generation), daemon=True).start()

    def _log_path(self):
        try:
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            logs = sorted(STATE_DIR.glob('server-*.log'))
            for old in logs[:-4]:
                old.unlink(missing_ok=True)
            return STATE_DIR / time.strftime('server-%Y%m%d-%H%M%S.log')
        except OSError:
            return None

    def stop(self, timeout=8.0):
        """Ask the server to close the station (phones get a message), then make sure it exits."""
        with self.lock:
            process = self.process
            if process is None or process.poll() is not None:
                return
            self._stop_requested = True
            self.state = 'stopping'
        reply = self.command('stop', {}, timeout=2.0)
        try:
            process.wait(timeout=timeout if reply.get('ok') else 1.0)
        except subprocess.TimeoutExpired:
            _kill_tree(process, force=False)
            try:
                process.wait(timeout=3.0)
            except subprocess.TimeoutExpired:
                _kill_tree(process, force=True)
                process.wait(timeout=3.0)

    def kill(self):
        with self.lock:
            if self.process is not None and self.process.poll() is None:
                self._stop_requested = True
                _kill_tree(self.process, force=True)

    def restart(self):
        self.stop()
        self.start()

    # Output and control ------------------------------------------------------------

    def _read_output(self, process, generation, log_file):
        for raw in process.stdout:
            line = raw.rstrip('\r\n')
            if log_file:
                log_file.write(line + '\n')
                log_file.flush()
            if not line.strip():
                continue
            self.log.append(line)
            if self.options.test_mode:
                self.console.line('GODOT| ' + line)
            if line.startswith('SERVER_ERROR'):
                self.error = line.removeprefix('SERVER_ERROR').strip().rstrip('.') + '.'
                self.error = self.error[0].upper() + self.error[1:]
            elif line.startswith('[station] '):
                self.console.event(line.removeprefix('[station] '))
            elif ('SCRIPT ERROR' in line or 'Parse Error' in line) and not self.options.test_mode:
                self.console.error(line.strip())
        code = process.wait()
        if log_file:
            log_file.close()
        with self.lock:
            if generation != self._generation:
                return
            self.exit_code = code
            self._close_socket()
            if self._stop_requested:
                self.state = 'stopped'
                self.console.info('Station closed.')
            else:
                self.state = 'crashed'
                self.error = self.error or f'The server stopped unexpectedly (exit code {code}).'
                self.console.error(self.error + ' Open the panel to restart it.')

    def _control_loop(self, process, generation):
        deadline = time.time() + 120.0
        while process.poll() is None and generation == self._generation:
            try:
                sock = socket.create_connection(('127.0.0.1', self.control_port), timeout=1.0)
            except OSError:
                if time.time() > deadline:
                    self.error = 'The server never opened its control port.'
                    _kill_tree(process, force=True)
                    return
                time.sleep(0.25)
                continue
            sock.settimeout(None)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            with self._send_lock:
                self._sock = sock
                sock.sendall((json.dumps({'hello': self.token}) + '\n').encode())
            try:
                for raw in sock.makefile('r', encoding='utf-8', errors='replace'):
                    self._on_message(raw)
            except OSError:
                pass
            self._close_socket()
            time.sleep(0.25)

    def _on_message(self, raw):
        try:
            message = json.loads(raw)
        except ValueError:
            return
        if message.get('type') == 'status':
            with self.lock:
                self.status, self.status_at = message, time.time()
                if self.state == 'starting':
                    self.state = 'running'
                if message.get('room_name') and message['room_name'] != self.room_name:
                    self.room_name = message['room_name']
            if not self.ready.is_set():
                self.ready.set()
                if self.on_ready:
                    self.on_ready(message)
            if self.on_status:
                self.on_status(message)
        elif message.get('type') == 'reply':
            pending = self._pending.pop(message.get('id'), None)
            if pending:
                pending[1].update(message)
                pending[0].set()

    def _close_socket(self):
        with self._send_lock:
            if self._sock is not None:
                try:
                    self._sock.close()
                except OSError:
                    pass
            self._sock = None
        for event, _ in list(self._pending.values()):
            event.set()

    def command(self, cmd, args, timeout=4.0):
        with self._send_lock:
            sock = self._sock
            if sock is None:
                return {'ok': False, 'error': 'The server is not connected.'}
            self._next_id += 1
            ident = self._next_id
            done, reply = threading.Event(), {}
            self._pending[ident] = (done, reply)
            try:
                sock.sendall((json.dumps({'id': ident, 'cmd': cmd, 'args': args}) + '\n').encode())
            except OSError:
                self._pending.pop(ident, None)
                return {'ok': False, 'error': 'The server is not connected.'}
        if not done.wait(timeout) or 'ok' not in reply:
            self._pending.pop(ident, None)
            return {'ok': False, 'error': 'The server did not answer.'}
        return {'ok': bool(reply['ok']), 'error': reply.get('error')}

    def snapshot(self):
        """Everything the panel shows, as one JSON document."""
        with self.lock:
            fresh = self.status is not None and time.time() - self.status_at < 3.0
            return {
                'app': 'drift-station',
                'launcher': {
                    'state': self.state if (fresh or self.state != 'running') else 'unresponsive',
                    'error': self.error,
                    'exit_code': self.exit_code,
                    'log_tail': list(self.log)[-25:] if self.state == 'crashed' else [],
                    'uptime': round(time.time() - self.started_at, 1) if self.state in ('starting', 'running') else 0,
                    'primary_address': primary_address(),
                    'public_address': self.options.public_address,
                    'firewall': self.options.firewall,
                    'os': platform.system(),
                },
                'server': self.status if fresh else None,
            }


# --- The panel's web server -------------------------------------------------------

class PanelHandler(BaseHTTPRequestHandler):
    server_version = 'DriftStation'
    sys_version = ''
    station = None
    port = PANEL_PORT

    def log_message(self, *args):
        pass  # keep the console for things the host needs to read

    def _host_ok(self):
        # DNS-rebinding guard: only answer requests addressed to this computer.
        host = (self.headers.get('Host') or '').lower()
        return host in {f'127.0.0.1:{self.port}', f'localhost:{self.port}', f'[::1]:{self.port}'}

    def _send(self, status, body, content_type='application/json; charset=utf-8'):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('X-Frame-Options', 'DENY')
        if content_type.startswith('text/html'):
            self.send_header('Content-Security-Policy', CSP)
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        if not self._host_ok():
            return self._send(HTTPStatus.FORBIDDEN, {'error': 'forbidden'})
        path = self.path.split('?', 1)[0]
        if path == '/api/status':
            return self._send(HTTPStatus.OK, self.station.snapshot())
        if path in STATIC:
            name, kind = STATIC[path]
            try:
                return self._send(HTTPStatus.OK, (PANEL_DIR / name).read_bytes(), kind)
            except OSError:
                return self._send(HTTPStatus.NOT_FOUND, {'error': 'missing'})
        match = re.fullmatch(r'/fonts/([a-z0-9-]+\.woff2)', path)
        if match and (FONT_DIR / match.group(1)).is_file():
            return self._send(HTTPStatus.OK, (FONT_DIR / match.group(1)).read_bytes(), 'font/woff2')
        self._send(HTTPStatus.NOT_FOUND, {'error': 'not found'})

    def do_POST(self):
        # The custom header forces a CORS preflight, which this server never
        # grants, so other websites open in the browser can't drive the station.
        if not self._host_ok() or self.headers.get('X-Drift-Panel') != '1':
            return self._send(HTTPStatus.FORBIDDEN, {'ok': False, 'error': 'forbidden'})
        try:
            length = min(int(self.headers.get('Content-Length') or 0), 8192)
            body = json.loads(self.rfile.read(length) or b'{}')
        except ValueError:
            return self._send(HTTPStatus.BAD_REQUEST, {'ok': False, 'error': 'Bad request.'})
        path = self.path.split('?', 1)[0]
        if path == '/api/command':
            cmd, args = body.get('cmd'), body.get('args') or {}
            if cmd not in COMMANDS or not isinstance(args, dict):
                return self._send(HTTPStatus.BAD_REQUEST, {'ok': False, 'error': 'Unknown command.'})
            if cmd == 'stop':
                threading.Thread(target=self.station.stop, daemon=True).start()
                return self._send(HTTPStatus.OK, {'ok': True})
            if cmd == 'set_room_name':
                args = {'name': clean_room_name(args.get('name', ''))}
            return self._send(HTTPStatus.OK, self.station.command(cmd, args))
        if path in ('/api/restart', '/api/start'):
            threading.Thread(target=self.station.restart, daemon=True).start()
            return self._send(HTTPStatus.OK, {'ok': True})
        self._send(HTTPStatus.NOT_FOUND, {'ok': False, 'error': 'not found'})


# --- Main ----------------------------------------------------------------------------

def print_summary(console, status, options, panel_url):
    best = primary_address()
    addresses = list(status.get('addresses') or [])
    if best and best in addresses:
        addresses.remove(best)
        addresses.insert(0, best)
    elif best:
        addresses.insert(0, best)
    p = console.paint
    console.line()
    console.line('  ' + p('DRIFT STATION', '1', '96') + p(f'  dedicated server  v{status.get("version", "?")}', '2'))
    console.line('  ' + p('─' * 58, '2'))
    console.line(f'  Station   {p(status.get("room_name", ""), "1")}')
    console.line('  Phones on the same Wi-Fi: open Drift Station, the station is under')
    console.line('  ' + p('Nearby stations', '1') + '. Or type this address:')
    console.line()
    if addresses:
        rows = big_text(addresses[0])
        if rows:
            for row in rows:
                console.line('    ' + p(row, '96'))
        else:
            console.line('    ' + p(addresses[0], '1', '96'))
        if len(addresses) > 1:
            console.line('    ' + p('also ' + ', '.join(addresses[1:]), '2'))
    else:
        console.warn('No Wi-Fi or LAN address found. Connect this computer to the same network as the phones.')
    if options.public_address:
        console.line(f'    Internet (tunnel): {p(options.public_address, "1")}  (forward UDP {GAME_PORT})')
    console.line()
    console.line(f'  Control panel  {p(panel_url, "4", "96")}')
    console.line(f'  Game ports     UDP {GAME_PORT} (play), UDP {DISCOVERY_PORT} (Nearby stations)')
    console.line(f'  Stop           {p("Ctrl+C", "1")} (phones are told the station is closing)')
    console.line('  ' + p('─' * 58, '2'))
    firewall = options.firewall or {}
    if firewall.get('state') in ('likely_blocked', 'blocked'):
        console.warn('Windows Firewall will probably block the phones. Allow the game ports once by running this')
        console.line('    in a terminal opened with "Run as administrator":')
        console.line('    ' + p(firewall['command'], '1'))
        if firewall.get('state') == 'blocked':
            console.line('    A rule blocking Godot also exists (someone pressed Cancel on the Windows prompt):')
            console.line('    remove it under Windows Security > Firewall > Allow an app, or in wf.msc.')
    for note in firewall.get('notes', []):
        console.warn(note)
    console.line()
    console.info(p('Live events:', '2'))


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--room-name', help='Station name phones see (default: remembered, or "<you>\'s station")')
    parser.add_argument('--max-players', type=int, default=8, choices=range(2, 9), metavar='2-8', help='Seats (default 8)')
    parser.add_argument('--auto-lobby', type=float, default=45, metavar='SECONDS',
                        help='Return everyone to the lobby this long after a round ends (0 = only from the panel; default 45)')
    parser.add_argument('--http-port', type=int, default=PANEL_PORT, help=f'Control panel port on 127.0.0.1 (default {PANEL_PORT})')
    parser.add_argument('--public-address', help='Address shown for internet play through a UDP tunnel (display only)')
    parser.add_argument('--no-browser', action='store_true', help="Don't open the control panel in a browser")
    parser.add_argument('--godot', help='Use this Godot 4.7.2 executable instead of the pinned download')
    parser.add_argument('--project', type=Path, default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument('--skip-import', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--test-mode', action='store_true', help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def main(argv=None):
    options = parse_args(argv)
    console = Console(machine=options.test_mode)
    options.no_browser = options.no_browser or options.test_mode
    panel_url = f'http://127.0.0.1:{options.http_port}'
    if existing_panel(options.http_port):
        console.info(f'A Drift Station server is already running on this computer: {panel_url}')
        if not options.no_browser:
            webbrowser.open(panel_url)
        return 0
    settings = load_settings()
    options.room_name = clean_room_name(options.room_name or settings.get('room_name') or default_room_name())
    try:
        engine = Path(options.godot) if options.godot else ensure_engine()
        engine, _ = validate_engine(engine)
        if not options.skip_import:
            prepare_project(engine, options.project.resolve(), console)
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        console.error(str(exc))
        return 1
    options.firewall = {'os': platform.system(), 'state': 'unknown', 'command': None, 'notes': []}
    if not options.test_mode:
        options.firewall = firewall_check()

    station = Station(engine, options.project.resolve(), options, console)
    PanelHandler.station, PanelHandler.port = station, options.http_port
    try:
        httpd = ThreadingHTTPServer(('127.0.0.1', options.http_port), PanelHandler)
    except OSError:
        console.error(f'Port {options.http_port} is busy. Pass --http-port with another number.')
        return 1
    httpd.daemon_threads = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    def on_ready(status):
        if options.test_mode:
            console.line(f'HOST_STATION_READY panel={panel_url} control={station.control_port}')
        else:
            print_summary(console, status, options, panel_url)

    def on_status(status):
        name = status.get('room_name')
        if name and name != settings.get('room_name'):
            settings['room_name'] = name
            save_settings(settings)

    station.on_ready, station.on_status = on_ready, on_status
    if not options.test_mode:
        console.line()
        console.info('Starting the Drift Station server...')
    station.start()
    if not options.no_browser:
        threading.Timer(0.6, webbrowser.open, [panel_url]).start()

    stopping = threading.Event()
    interrupts = []

    def on_signal(signum, _frame):
        interrupts.append(signum)
        if len(interrupts) > 1:
            console.warn('Stopping now.')
            station.kill()
            os._exit(130)
        stopping.set()

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)
    if hasattr(signal, 'SIGBREAK'):
        signal.signal(signal.SIGBREAK, on_signal)
    try:
        while not stopping.wait(0.5):
            pass
    except KeyboardInterrupt:
        pass
    console.line()
    console.info('Closing the station: telling the phones, then shutting down...')
    station.stop()
    httpd.shutdown()
    if options.test_mode:
        console.line('HOST_STATION_STOPPED')
    else:
        console.info('Done. See you next time.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
