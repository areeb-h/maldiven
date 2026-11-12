#!/usr/bin/env python3
"""Open the real 3D client with a local server and one headless companion."""
import argparse
import os
import secrets
import shutil
import struct
import subprocess
import tempfile
import time
from pathlib import Path

from bootstrap_godot import ROOT, ensure_engine, validate_engine
from test_network_lab import Lab, wait_for
from test_movement_lab import MovementLab


def virtual_display(directory, output):
    """Private authenticated Xorg dummy display for render-only Linux captures."""
    executable = shutil.which('Xorg')
    if not executable:
        raise RuntimeError('Xorg with the dummy driver is required for --virtual-display')
    number = secrets.randbelow(200) + 90
    config = directory / 'xorg.conf'
    config.write_text('''Section "ServerFlags"
 Option "AutoAddDevices" "false"
 Option "AutoAddGPU" "false"
 Option "DontVTSwitch" "true"
EndSection
Section "Device"
 Identifier "Dummy"
 Driver "dummy"
 VideoRam 256000
EndSection
Section "Monitor"
 Identifier "Monitor"
 HorizSync 5.0-1000.0
 VertRefresh 5.0-200.0
 Modeline "1280x720" 74.50 1280 1344 1472 1664 720 723 728 748
EndSection
Section "Screen"
 Identifier "Screen"
 Device "Dummy"
 Monitor "Monitor"
 DefaultDepth 24
 SubSection "Display"
  Depth 24
  Modes "1280x720"
 EndSubSection
EndSection
''')
    authority = directory / 'Xauthority'
    def field(value):
        return struct.pack('!H', len(value)) + value
    authority.write_bytes(struct.pack('!H', 65535) + field(b'') + field(str(number).encode()) + field(b'MIT-MAGIC-COOKIE-1') + field(secrets.token_bytes(16)))
    authority.chmod(0o600)
    log = (output / 'display.log').open('w')
    process = subprocess.Popen([executable, ':' + str(number), '-config', str(config), '-logfile', str(output / 'display-details.log'),
                                '-nolisten', 'local', '-nolisten', 'unix', '-listen', 'tcp', '-auth', str(authority), '-noreset'], stdout=log, stderr=subprocess.STDOUT)
    time.sleep(1)
    if process.poll() is not None:
        log.close()
        raise RuntimeError('Virtual display did not start; see display.log')
    os.environ.update(DISPLAY='127.0.0.1:' + str(number), XAUTHORITY=str(authority), LIBGL_ALWAYS_SOFTWARE='1', LP_NUM_THREADS='2')
    return process, log


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--seconds', type=float, default=30)
    parser.add_argument('--capture', type=Path)
    parser.add_argument('--virtual-display', action='store_true')
    args = parser.parse_args()
    if not 3 <= args.seconds <= 300:
        parser.error('--seconds must be between 3 and 300')
    output = ROOT / 'builds' / 'movement-preview'
    output.mkdir(parents=True, exist_ok=True)
    engine, _ = validate_engine(args.godot or ensure_engine())
    display = None
    display_log = None
    with tempfile.TemporaryDirectory(prefix='maldiven-preview-') as name:
        directory = Path(name)
        project = directory / 'project'
        shutil.copytree(ROOT / 'experiments' / 'net-lab', project, ignore=shutil.ignore_patterns('.godot'))
        lab = MovementLab(engine, project, directory, output)
        try:
            if args.virtual_display:
                display, display_log = virtual_display(directory, output)
            server = lab.server('preview-server')
            companion = lab.driven(server, 'player-2')
            extra = []
            if args.capture:
                capture = args.capture.resolve()
                capture.parent.mkdir(parents=True, exist_ok=True)
                capture.unlink(missing_ok=True)
                extra += ['--capture-file', str(capture)]
            viewer = Lab.client(lab, server, lab.credential(server, 'player-1'), hold=args.seconds, script='movement_client.gd', extra=extra, headless=False,
                                engine_options=('--audio-driver', 'Dummy', '--max-fps', '30') if args.virtual_display else ())
            wait_for(lambda: viewer.event('view_sample'), timeout=30)
            print('Two clients connected. WASD/arrows move; Shift runs; Escape leaves.', flush=True)
            if args.capture:
                wait_for(lambda: viewer.event('frame_saved'), timeout=25)
                assert capture.is_file()
                print('Saved actual client frame: ' + str(capture), flush=True)
            deadline = time.monotonic() + args.seconds
            while viewer.process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.05)
            if viewer.process.poll() is None:
                lab.leave(server, viewer)
            else:
                viewer.finish(0)
            lab.leave(server, companion)
            lab.stop(server)
        finally:
            lab.close()
            if display is not None:
                display.terminate()
                display.wait(timeout=5)
                display_log.close()


if __name__ == '__main__':
    main()
