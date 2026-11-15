#!/usr/bin/env python3
"""Record the current look of the game into the looks log (docs/looks/).

Plays two real bot rounds on a rendered client (crew view, then infiltrator
view), keeps a curated set of frames as compact JPGs in
docs/looks/<date>-<label>/, and prepends an entry to docs/looks/README.md so the
visual history of the project stays browsable in the repo.

Usage: python tools/record_looks.py --label art-pass-1 --note "What changed"
Requires Pillow for JPG conversion (pip install pillow); falls back to PNG.
"""
import argparse
import datetime
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from bootstrap_godot import ROOT

LOOKS = ROOT / 'docs' / 'looks'
# (run, frame-name suffix) in gallery order; missing frames are skipped.
CURATED = [
    ('crew', 'home'), ('crew', 'lobby'), ('crew', 'briefing'), ('crew', 'spawn_commons'),
    ('crew', 'near_cell_1'), ('crew', 'carrying_cell_1'), ('crew', 'after_reactor_1'),
    ('crew', 'power_restored'), ('crew', 'at_vault'), ('crew', 'before_shuttle'),
    ('crew', 'after_shuttle'), ('crew', 'result'),
    ('infiltrator', 'briefing'), ('infiltrator', 'blackout'), ('infiltrator', 'before_pod'),
    ('infiltrator', 'after_pod'), ('infiltrator', 'result'),
]


def capture(run, out, godot, renderer):
    command = [sys.executable, str(ROOT / 'tools' / 'capture_screenshots.py'), '--out', str(out),
               '--plan', 'crew' if run == 'crew' else 'infiltrator', '--renderer', renderer]
    if run == 'infiltrator':
        command.append('--host-infiltrator')
    if godot:
        command += ['--godot', godot]
    print(f'capturing {run} view...', flush=True)
    result = subprocess.run(command, capture_output=True, text=True, timeout=1200)
    print(result.stdout[-600:], flush=True)
    return sorted(out.glob('*.png'))


def convert(source, target_stem, width=1280):
    try:
        from PIL import Image
    except ImportError:
        target = target_stem.with_suffix('.png')
        shutil.copy(source, target)
        return target
    image = Image.open(source).convert('RGB')
    if image.width > width:
        image = image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)
    target = target_stem.with_suffix('.jpg')
    image.save(target, 'JPEG', quality=84, optimize=True, progressive=True)
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', required=True, help='Short slug, e.g. art-pass-1')
    parser.add_argument('--note', default='', help='One or two lines about what changed')
    parser.add_argument('--godot')
    parser.add_argument('--renderer', default='mobile')
    parser.add_argument('--from-dir', type=Path, help='Archive existing PNG renders (sorted) instead of capturing')
    parser.add_argument('--max', type=int, default=20)
    args = parser.parse_args()
    date = datetime.date.today().isoformat()
    slug = f'{date}-{args.label}'
    folder = LOOKS / slug
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    commit = subprocess.run(['git', '-C', str(ROOT), 'rev-parse', '--short', 'HEAD'],
                            capture_output=True, text=True).stdout.strip()
    frames = {}
    if args.from_dir:
        kept = []
        for index, png in enumerate(sorted(args.from_dir.glob('*.png'))[:args.max]):
            kept.append(convert(png, folder / f'{index:02d}_{png.stem.split("_", 1)[-1]}'))
        return _write_entry(args, date, slug, commit, kept, 'studio/station renders')
    with tempfile.TemporaryDirectory(prefix='looks-') as temp:
        for run in ('crew', 'infiltrator'):
            out = Path(temp) / run
            out.mkdir()
            for png in capture(run, out, args.godot, args.renderer):
                name = png.stem.split('_', 1)[1] if '_' in png.stem else png.stem
                frames[(run, name)] = png
        kept = []
        for index, key in enumerate(k for k in CURATED if k in frames):
            target = convert(frames[key], folder / f'{index:02d}_{key[0]}_{key[1]}')
            kept.append(target)
    return _write_entry(args, date, slug, commit, kept, None)


def _write_entry(args, date, slug, commit, kept, source):
    folder = LOOKS / slug
    if not kept:
        print('No frames captured; nothing recorded.')
        return 1
    renderer = source or ('GL Compatibility (software, cloud capture)' if args.renderer == 'gl_compatibility' else f'{args.renderer} renderer (software Vulkan in the cloud)')
    lines = [f'## {date} · {args.label}', '',
             f'Commit `{commit}` · {renderer} · {len(kept)} frames · [folder]({slug}/)', '']
    if args.note:
        lines += [args.note, '']
    lines += ['| | |', '| --- | --- |']
    for left, right in zip(kept[0::2], kept[1::2] + [None]):
        def cell(path):
            if path is None:
                return ' '
            caption = path.stem.split('_', 1)[1].replace('_', ' ')
            return f'![{caption}]({slug}/{path.name})<br>{caption}'
        lines.append(f'| {cell(left)} | {cell(right)} |')
    lines.append('')
    readme = LOOKS / 'README.md'
    header = ('# Looks log\n\nHow Drift Station looks over time, newest first. Gameplay entries come from '
              '`python tools/record_looks.py --label <slug> --note "..."`, which plays real bot rounds on a '
              'rendered client with the Mobile renderer; `--from-dir` archives studio renders.\n\n')
    previous = readme.read_text().split('\n', 1)[1] if readme.exists() else ''
    body = previous[previous.find('## '):] if '## ' in previous else ''
    readme.write_text(header + '\n'.join(lines) + '\n' + body)
    print(f'Recorded {len(kept)} frames in {folder}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
