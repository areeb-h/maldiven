#!/usr/bin/env python3
"""Drift Station checks: import, rules unit tests, art/physics smoke tests and three
real networked bot rounds (1 host + 2 clients over loopback ENet).

Usage: python tools/test_station.py [--godot PATH] [--skip-net]
"""
import argparse
import subprocess
import sys
import time

from bootstrap_godot import ROOT, ensure_engine, validate_engine

ERROR_MARKERS = ('SCRIPT ERROR', 'Parse Error', 'Compile Error')


def run_host_station_test(engine):
    print('dedicated server + control panel (tools/test_host_station.py)...', flush=True)
    result = subprocess.run([sys.executable, str(ROOT / 'tools' / 'test_host_station.py'), '--godot', str(engine)],
                            capture_output=True, text=True, timeout=420)
    if result.returncode != 0:
        print((result.stdout + result.stderr)[-4000:])
        raise SystemExit('FAILED: dedicated server + control panel')
    print('  ' + (result.stdout.strip().splitlines() or ['ok'])[-1])


def run(engine, label, args, marker, timeout=180):
    print(f'{label}...', flush=True)
    result = subprocess.run([str(engine), '--headless', '--path', str(ROOT)] + args,
                            capture_output=True, text=True, timeout=timeout)
    log = result.stdout + result.stderr
    bad = [line for line in log.splitlines() if any(m in line for m in ERROR_MARKERS)]
    if result.returncode != 0 or bad or (marker and marker not in log):
        print(log[-4000:])
        raise SystemExit(f'FAILED: {label}')
    print(f'  ok')


def net_round(engine, plan, players=3, seed=11, timeout=150, host_infiltrator=False):
    label = f'network round ({plan} plan, {players} players)'
    print(f'{label}...', flush=True)
    base = [str(engine), '--headless', '--path', str(ROOT), '--']
    common = [f'--bot-plan={plan}', f'--bot-timeout={timeout - 10}']
    procs = [subprocess.Popen(base + ['--bot=host', '--bot-name=Host', f'--bot-players={players}',
                                      f'--bot-seed={seed}'] + common
                              + (['--bot-host-infiltrator'] if host_infiltrator else []),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)]
    time.sleep(1.5)
    for index in range(1, players):
        procs.append(subprocess.Popen(base + ['--bot=client', f'--bot-name=C{index}',
                                              f'--bot-join-delay={0.3 * index}'] + common,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True))
    logs = []
    for proc in procs:
        try:
            out, _ = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            for other in procs:
                other.kill()
            raise SystemExit(f'FAILED: {label}: timeout')
        logs.append((proc.returncode, out))
    results, roles, problems = [], [], []
    for index, (code, out) in enumerate(logs):
        lines = out.splitlines()
        results += [l for l in lines if l.startswith('BOT_RESULT')]
        roles += [l.split()[1] for l in lines if l.startswith('BOT_ROLE')]
        errors = [l for l in lines if any(m in l for m in ERROR_MARKERS)]
        if code != 0 or errors:
            problems.append(f'process {index} exit={code}\n' + '\n'.join(lines[-40:]))
    expected = 'infiltrator' if plan == 'infiltrator' else 'crew'
    if len(results) != players or any(f'winner={expected}' not in r for r in results):
        problems.append('results: ' + repr(results))
    if sorted(roles).count('infiltrator') != 1 or len(roles) != players:
        problems.append('roles: ' + repr(roles))
    if plan == 'infiltrator' and not any('BOT_SHOVE ok' in out for _, out in logs):
        problems.append('expected a successful shove of the core carrier')
    if plan == 'crew':
        rests = []
        for _, out in logs:
            rests += [l.split() for l in out.splitlines() if l.startswith('BOT_THROW_REST')]
        if len(rests) != players or any(r[5].lower() != 'true' for r in rests):
            problems.append('throw replication: expected every peer to see the thrown cell at rest: ' + repr(rests))
        else:
            points = [tuple(float(v) for v in r[2:5]) for r in rests]
            spread = max(sum((a - b) ** 2 for a, b in zip(p, q)) ** 0.5 for p in points for q in points)
            if spread > 0.1:
                problems.append(f'throw replication: peers disagree by {spread:.3f} m: {points}')
            else:
                print(f'  thrown cell agrees on {players} peers within {spread * 100:.1f} cm')
    if plan == 'eject':
        if not any('reason=The infiltrator was spaced.' in r for r in results):
            problems.append('expected the infiltrator to be spaced')
        if not any('BOT_SHOT_HIT true' in out for _, out in logs) or not any('BOT_DRAG true' in out for _, out in logs):
            problems.append('expected a hit and a drag')
    if problems:
        print('\n\n'.join(problems))
        raise SystemExit(f'FAILED: {label}')
    print(f'  ok: {results[0]}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--skip-net', action='store_true')
    args = parser.parse_args()
    engine, _ = validate_engine(args.godot or ensure_engine())
    run(engine, 'import', ['--editor', '--import', '--quit'], None, timeout=300)
    run(engine, 'rules unit tests', ['--script', 'res://tests/rules_test.gd'], 'PASS: rules')
    for script, marker in [('art_smoke', 'PASS: art smoke'), ('audio_smoke', 'PASS: audio smoke'),
                           ('crew_model_smoke', 'PASS: crew model'), ('vfx_smoke', 'PASS: vfx smoke'),
                           ('icons_smoke', 'PASS: icons')]:
        if (ROOT / 'tests' / f'{script}.gd').exists():
            run(engine, script.replace('_', ' '), ['--script', f'res://tests/{script}.gd'], marker)
    # Fixed 60 Hz steps, as fast as the machine runs: many simulated seconds.
    run(engine, 'physics smoke', ['--fixed-fps', '60', '--script', 'res://tests/physics_smoke.gd'], 'PASS: physics smoke',
        timeout=300)
    if not args.skip_net:
        net_round(engine, 'crew')
        net_round(engine, 'infiltrator')
        net_round(engine, 'eject', host_infiltrator=True)
        if (ROOT / 'tools' / 'test_host_station.py').exists():
            run_host_station_test(engine)
    print('ALL STATION CHECKS PASSED')


if __name__ == '__main__':
    sys.exit(main())
