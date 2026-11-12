#!/usr/bin/env python3
"""Export the isolated Friends Lab, without changing the island APK/project."""
import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path
from bootstrap_godot import ROOT, ensure_engine, validate_engine


def checked(command):
    result = subprocess.run(command, capture_output=True, text=True)
    log = result.stdout + result.stderr
    print(log, end='', flush=True)
    if result.returncode or 'ERROR:' in log:
        raise RuntimeError('Godot import/export reported an error; inspect the output above')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--pack-only', action='store_true', help='Export/start the desktop pack to verify the real app entry point')
    args = parser.parse_args()
    engine, _ = validate_engine(args.godot or ensure_engine())
    output = ROOT / 'builds' / ('maldiven-friends.zip' if args.pack_only else 'maldiven-friends-0.3.1-arm64.apk')
    output.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='maldiven-friends-export-') as name:
        stage = Path(name) / 'project'
        shutil.copytree(ROOT / 'experiments' / 'net-lab', stage, ignore=shutil.ignore_patterns('.godot'))
        checked([str(engine), '--headless', '--path', str(stage), '--editor', '--import'])
        preset = 'Friends Pack' if args.pack_only else 'Friends Android'
        checked([str(engine), '--headless', '--path', str(stage), '--export-pack' if args.pack_only else '--export-debug', preset, str(output)])
        if args.pack_only:
            result = subprocess.run([str(engine), '--headless', '--path', name, '--main-pack', str(output), '--quit-after', '5'], capture_output=True, text=True, timeout=20)
            if result.returncode or 'ERROR:' in result.stdout + result.stderr:
                raise RuntimeError(result.stdout + result.stderr)
    print(output)


if __name__ == '__main__':
    main()
