#!/usr/bin/env python3
"""Play real bot rounds and save gameplay screenshots from a rendered client.

One rendered host (under xvfb-run when no display is present) plus headless
client bots. Uses the GL Compatibility renderer unless --renderer is given,
because cloud machines rarely have Vulkan.

Usage: python tools/capture_screenshots.py --out builds/screenshots [--plan crew|infiltrator]
"""
import argparse
import os
import shutil
import subprocess
import time
from pathlib import Path

from bootstrap_godot import ROOT, ensure_engine, validate_engine


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot')
    parser.add_argument('--out', type=Path, default=ROOT / 'builds' / 'screenshots')
    parser.add_argument('--plan', choices=['crew', 'infiltrator'], default='crew')
    parser.add_argument('--seed', type=int, default=11)
    parser.add_argument('--players', type=int, default=3)
    parser.add_argument('--renderer', default='gl_compatibility')
    parser.add_argument('--size', default='1600x900')
    args = parser.parse_args()
    engine, _ = validate_engine(args.godot or ensure_engine())
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    width, height = args.size.split('x')
    common = [f'--bot-plan={args.plan}', '--bot-timeout=170']
    rendered = [str(engine), '--path', str(ROOT), '--rendering-method', args.renderer,
                '--resolution', args.size, '--']
    if not os.environ.get('DISPLAY') and shutil.which('xvfb-run'):
        rendered = ['xvfb-run', '-a', '-s', f'-screen 0 {width}x{height}x24'] + rendered
    host = subprocess.Popen(rendered + ['--bot=host', '--bot-name=Areeb', f'--bot-players={args.players}',
                                        f'--bot-seed={args.seed}', f'--bot-shots={out}', '--touch-ui'] + common,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    time.sleep(4)
    names = ['Maya', 'Jon', 'Zara', 'Ilyas', 'Noor', 'Sam', 'Lee']
    clients = [subprocess.Popen([str(engine), '--headless', '--path', str(ROOT), '--', '--bot=client',
                                 f'--bot-name={names[i]}', f'--bot-join-delay={0.4 * i}'] + common,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
               for i in range(args.players - 1)]
    host_log, _ = host.communicate(timeout=200)
    for client in clients:
        client.communicate(timeout=30)
    shots = [l.split(' ', 1)[1] for l in host_log.splitlines() if l.startswith('BOT_SHOT')]
    for line in host_log.splitlines():
        if line.startswith(('BOT_RESULT', 'BOT_ROLE', 'BOT_TIMEOUT', 'SCRIPT ERROR')):
            print(line)
    print(f'{len(shots)} screenshots in {out}')
    return 0 if shots else 1


if __name__ == '__main__':
    raise SystemExit(main())
