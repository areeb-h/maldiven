#!/usr/bin/env python3
"""Install the checksum-pinned Godot Standard editor for this computer.

Linux x86-64, Windows x86-64 and macOS (universal) are pinned in
toolchain.lock.json. The archive and every installed executable are checked
against those pins before anything runs; nothing is installed on a mismatch.
"""
import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    with Path(path).open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def host_key():
    """The toolchain.lock.json key for this computer, or None if unsupported."""
    system, machine = platform.system(), platform.machine().lower()
    if system == 'Linux' and machine in ('x86_64', 'amd64'):
        return 'linux_x86_64'
    if system == 'Windows' and machine in ('amd64', 'x86_64', 'arm64'):  # arm64 runs the x64 build
        return 'windows_x86_64'
    if system == 'Darwin':
        return 'macos_universal'
    return None


def _pins():
    config = json.loads((ROOT / 'toolchain.lock.json').read_text())['godot']
    return config, config.get(host_key() or '', None)


def _download(pin, package):
    print(f'Downloading Godot {pin["name"]} ({pin["size"] / 1e6:.0f} MB, one time only)...', file=sys.stderr, flush=True)
    partial = package.with_suffix('.part')
    try:
        with urllib.request.urlopen(pin['url'], timeout=30) as response, partial.open('wb') as target:
            done, step = 0, max(1, pin['size'] // 20)
            while chunk := response.read(1 << 20):
                target.write(chunk)
                done += len(chunk)
                if sys.stderr.isatty() and done // step != (done - len(chunk)) // step:
                    print(f'\r  {min(100, done * 100 // pin["size"]):3d} %', end='', file=sys.stderr, flush=True)
        if sys.stderr.isatty():
            print(file=sys.stderr)
        if partial.stat().st_size != pin['size'] or digest(partial) != pin['sha256']:
            raise RuntimeError('Downloaded Godot archive size/checksum differs from the pin')
        partial.replace(package)
    finally:
        partial.unlink(missing_ok=True)


def _install_file(data, target, expected, executable):
    if hashlib.sha256(data).hexdigest() != expected:
        raise RuntimeError('Unpacked engine checksum differs from the pin: ' + target.name)
    temporary = target.with_name(target.name + '.installing')
    temporary.write_bytes(data)
    if executable:
        temporary.chmod(0o755)
    temporary.replace(target)


def _install_bundle(bundle, pin, cache):
    """macOS: unpack the whole Godot.app (code signature and resources stay intact)."""
    prefix = pin['bundle'].rstrip('/') + '/'
    staging = cache / (pin['bundle'] + '.installing')
    shutil.rmtree(staging, ignore_errors=True)
    for info in bundle.infolist():
        name = PurePosixPath(info.filename)
        if not info.filename.startswith(prefix) or name.is_absolute() or '..' in name.parts:
            continue  # only the app bundle, never arbitrary archive paths
        target = staging.joinpath(*name.parts[1:])
        mode = info.external_attr >> 16
        if info.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if mode & 0o170000 == 0o120000:
            continue  # the official bundle has no symlinks; never follow one out of the cache
        target.write_bytes(bundle.read(info))
        target.chmod(0o755 if mode & 0o111 else 0o644)
    executable = staging.joinpath(*PurePosixPath(pin['executable']).parts[1:])
    if not executable.is_file() or digest(executable) != pin['executable_sha256']:
        shutil.rmtree(staging, ignore_errors=True)
        raise RuntimeError('Unpacked engine checksum differs from the pin')
    final = cache / pin['bundle']
    shutil.rmtree(final, ignore_errors=True)
    staging.replace(final)


def ensure_engine(archive=None):
    """Return the path of the pinned engine, downloading and verifying it on first use."""
    config, pin = _pins()
    if pin is None:
        raise RuntimeError('Automatic Godot download supports Linux x86-64, Windows x86-64 and macOS. '
                           'Install Godot 4.7.2 Standard yourself and pass --godot PATH.')
    cache = ROOT / 'tools' / '.cache' / ('godot-' + config['version'])
    cache.mkdir(parents=True, exist_ok=True)
    engine = cache / Path(*PurePosixPath(pin['executable']).parts)
    companion = cache / pin['companion'] if 'companion' in pin else None
    if engine.is_file() and digest(engine) == pin['executable_sha256'] and (
            companion is None or (companion.is_file() and digest(companion) == pin['companion_sha256'])):
        return engine
    package = Path(archive).resolve() if archive else cache / pin['name']
    if not package.is_file():
        if archive:
            raise RuntimeError('Supplied archive does not exist: ' + str(package))
        _download(pin, package)
    if package.stat().st_size != pin['size'] or digest(package) != pin['sha256']:
        raise RuntimeError('Godot archive does not match toolchain.lock.json; no executable was installed')
    with zipfile.ZipFile(package) as bundle:
        if 'bundle' in pin:
            _install_bundle(bundle, pin, cache)
            return engine
        # Extract only the known members, never arbitrary archive paths.
        if companion is not None:  # Windows: the console wrapper starts the main exe beside it
            _install_file(bundle.read(pin['companion']), companion, pin['companion_sha256'], True)
        _install_file(bundle.read(pin['executable']), engine, pin['executable_sha256'], True)
    return engine


def validate_engine(executable):
    """Reject a different engine before any import or export can modify a stage."""
    engine = Path(shutil.which(str(executable)) or executable).resolve()
    config, pin = _pins()
    version = subprocess.run([str(engine), '--version'], capture_output=True, text=True, check=True, timeout=30).stdout.strip()
    if not version.startswith(config['version_prefix']):
        raise RuntimeError('Wrong Godot version: ' + version + '; expected ' + config['version_prefix'])
    checksum = digest(engine)
    if host_key() == 'linux_x86_64':
        if checksum != pin['executable_sha256']:
            raise RuntimeError('Linux engine executable differs from the official pinned binary')
    elif pin is not None and engine.name == Path(pin['executable']).name and checksum != pin['executable_sha256']:
        raise RuntimeError('Engine executable differs from the official pinned binary')
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
