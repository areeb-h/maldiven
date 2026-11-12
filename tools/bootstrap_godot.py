#!/usr/bin/env python3
"""Install the checksum-pinned Standard editor for the Linux x86-64 build host."""
import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def ensure_engine(archive=None):
    if platform.system() != 'Linux' or platform.machine() not in ('x86_64', 'AMD64'):
        raise RuntimeError('Automatic bootstrap supports Linux x86-64. Install Godot 4.7.2 Standard and pass --godot to validate_project.py on other hosts.')
    config = json.loads((ROOT / 'toolchain.lock.json').read_text())['godot']
    pin = config['linux_x86_64']
    cache = ROOT / 'tools' / '.cache' / ('godot-' + config['version'])
    cache.mkdir(parents=True, exist_ok=True)
    engine = cache / pin['executable']
    if engine.is_file() and digest(engine) == pin['executable_sha256']:
        return engine
    package = Path(archive).resolve() if archive else cache / pin['name']
    if not package.is_file():
        if archive:
            raise RuntimeError('Supplied archive does not exist: ' + str(package))
        print('Downloading pinned Godot editor...', file=sys.stderr, flush=True)
        partial = package.with_suffix('.part')
        try:
            with urllib.request.urlopen(pin['url'], timeout=30) as response, partial.open('wb') as target:
                shutil.copyfileobj(response, target)
            if partial.stat().st_size != pin['size'] or digest(partial) != pin['sha256']:
                raise RuntimeError('Downloaded Godot archive size/checksum differs from the pin')
            partial.replace(package)
        finally:
            partial.unlink(missing_ok=True)
    if package.stat().st_size != pin['size'] or digest(package) != pin['sha256']:
        raise RuntimeError('Godot archive does not match toolchain.lock.json; no executable was installed')
    with zipfile.ZipFile(package) as bundle:
        # Extract only the known member, never arbitrary archive paths.
        data = bundle.read(pin['executable'])
    if hashlib.sha256(data).hexdigest() != pin['executable_sha256']:
        raise RuntimeError('Unpacked engine checksum differs from the pin')
    temporary = engine.with_suffix('.installing')
    temporary.write_bytes(data)
    temporary.chmod(0o755)
    temporary.replace(engine)
    return engine


def validate_engine(executable):
    """Reject a different engine before any import or export can modify a stage."""
    engine = Path(shutil.which(str(executable)) or executable).resolve()
    pin = json.loads((ROOT / 'toolchain.lock.json').read_text())['godot']
    version = subprocess.run([str(engine), '--version'], capture_output=True, text=True, check=True, timeout=10).stdout.strip()
    if not version.startswith(pin['version_prefix']):
        raise RuntimeError('Wrong Godot version: ' + version + '; expected ' + pin['version_prefix'])
    checksum = digest(engine)
    if platform.system() == 'Linux' and platform.machine() in ('x86_64', 'AMD64'):
        if checksum != pin['linux_x86_64']['executable_sha256']:
            raise RuntimeError('Linux engine executable differs from the official pinned binary')
    return engine, {'version': version, 'sha256': checksum}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, help='Reuse an already downloaded official archive')
    args = parser.parse_args()
    try:
        print(ensure_engine(args.archive))
    except (OSError, RuntimeError, zipfile.BadZipFile, KeyError) as exc:
        parser.exit(1, str(exc) + '\n')


if __name__ == '__main__':
    main()
