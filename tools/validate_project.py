#!/usr/bin/env python3
"""Validate the pinned island foundation from a fresh import and exported pack.

Uses the Python standard library. Desktop/headless evidence is not Android proof.
"""
import argparse
import datetime
import hashlib
import json
import platform
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from bootstrap_godot import ROOT, digest, ensure_engine, validate_engine

IGNORED = {'.git', '.godot', 'builds', '.cache', '__pycache__', 'previews'}


def source_id(root):
    hasher = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root)
        if not path.is_file() or set(rel.parts) & (IGNORED | {'docs'}) or rel.as_posix() == 'README.md':
            continue
        if path.suffix in ('.pyc', '.keystore', '.jks') or path.name == 'export_credentials.cfg':
            continue
        hasher.update(rel.as_posix().encode() + b'\0' + digest(path).encode() + b'\n')
    return hasher.hexdigest()


def run_check(report, output, label, command, timeout=60, marker=None):
    print(label + '...', flush=True)
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        log = result.stdout + result.stderr
        passed = result.returncode == 0 and 'SCRIPT ERROR:' not in log and 'ERROR:' not in log
        if marker and marker not in log:
            passed = False
        entry = {'name': label, 'exit_code': result.returncode, 'passed': passed}
    except subprocess.TimeoutExpired as exc:
        def decoded(value):
            return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
        log = decoded(exc.stdout) + decoded(exc.stderr) + '\nTIMEOUT\n'
        entry = {'name': label, 'exit_code': None, 'passed': False, 'timeout': timeout}
    (output / (label + '.log')).write_text(log)
    report['checks'].append(entry)
    if not entry['passed']:
        raise RuntimeError(label + ' failed; see ' + str(output / (label + '.log')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', help='Exact pinned executable; otherwise bootstrap it')
    parser.add_argument('--output', type=Path, default=ROOT / 'builds' / 'baseline')
    args = parser.parse_args()
    output = args.output.resolve()
    if output == ROOT or (ROOT in output.parents and output.relative_to(ROOT).parts[0] != 'builds'):
        parser.error('Output inside the repository must be under builds/')
    output.mkdir(parents=True, exist_ok=True)
    lock = json.loads((ROOT / 'toolchain.lock.json').read_text())
    report = {'status': 'failed', 'checks': [], 'source_id': source_id(ROOT),
              'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'host': {'system': platform.system(), 'machine': platform.machine()},
              'scope': 'fresh desktop/headless import, existing regression checks, ZIP pack export and packaged startup; no Android/phone/network/voice validation'}
    try:
        engine, report['engine'] = validate_engine(args.godot or ensure_engine())
        with tempfile.TemporaryDirectory(prefix='maldiven-baseline-') as temporary:
            stage = Path(temporary) / 'project'
            shutil.copytree(ROOT, stage, ignore=shutil.ignore_patterns(*IGNORED, '*.pyc', '*.keystore', '*.jks', 'export_credentials.cfg'))
            base = [str(engine), '--headless', '--path', str(stage)]
            run_check(report, output, 'clean-import', base + ['--editor', '--import'], timeout=120)
            run_check(report, output, 'assets', base + ['--script', 'res://tests/assets_smoke.gd'], marker='PASS: all eight GLBs')
            run_check(report, output, 'movement', base + ['--script', 'res://tests/movement_smoke.gd'], marker='PASS: floor, movement')
            package = output / 'maldiven-baseline.zip'
            package.unlink(missing_ok=True)
            run_check(report, output, 'pack-export', base + ['--export-pack', lock['baseline']['export_preset'], str(package)], timeout=120)
            with zipfile.ZipFile(package) as bundle:
                names = bundle.namelist()
                forbidden = ('tests/', 'docs/', 'tools/', 'experiments/', 'README.md', 'toolchain.lock.json')
                if bundle.testzip() or not any(n.endswith('project.binary') for n in names):
                    raise RuntimeError('Exported pack is invalid or missing project.binary')
                if any(name.startswith(forbidden) for name in names):
                    raise RuntimeError('Development/private files leaked into the exported pack')
                report['pack'] = {'sha256': digest(package), 'bytes': package.stat().st_size, 'files': len(names), 'development_files_excluded': True}
            empty = Path(temporary) / 'empty'
            empty.mkdir()
            run_check(report, output, 'pack-startup', [str(engine), '--headless', '--path', str(empty), '--main-pack', str(package), '--quit-after', '120'])
        report['status'] = 'passed'
    except (OSError, RuntimeError, subprocess.SubprocessError, zipfile.BadZipFile) as exc:
        report['error'] = str(exc)
        print(str(exc), flush=True)
    finally:
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Report: ' + str(output / 'report.json'), flush=True)
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
