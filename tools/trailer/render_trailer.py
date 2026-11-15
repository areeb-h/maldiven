#!/usr/bin/env python3
"""Render the Drift Station trailer and encode it, in one command.

  python3 tools/trailer/render_trailer.py                 # master: 2560x1440 4x MSAA, downscaled to 1080p
  python3 tools/trailer/render_trailer.py --size 1920x1080   # cheaper, no supersampling
  python3 tools/trailer/render_trailer.py --preview       # 640x360 15 fps draft (much faster)
  python3 tools/trailer/render_trailer.py --from 38.5 --to 48.5 --preview   # one stretch

Steps: find the engine (the pinned Godot from tools/.cache, downloaded on first
use, or --godot PATH), refresh the project's class cache (`--editor --import`,
needed on a fresh checkout or after new class_name scripts), render
tools/trailer/trailer.gd to <out>/render (PNG frames + cues.json), stop the
engine if it stalls on exit after "trailer: done", then run make_video.py and
print the MP4 path(s).

Display and renderer: with no display (Linux servers, CI) it wraps Godot in
xvfb-run and uses the Mobile renderer (software Vulkan works). With a display
it runs Godot directly; --renderer auto picks Mobile when Vulkan is available
and GL Compatibility otherwise (e.g. WSLg without a Vulkan driver).
Compatibility has no depth of field, so the picture is a little flatter there.
"""
import argparse
import os
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from bootstrap_godot import ROOT, ensure_engine, validate_engine  # noqa: E402

DONE = 'trailer: done'


def find_engine(path):
    if path:
        return Path(path)
    engine = ensure_engine()
    validate_engine(engine)
    return engine


def has_display():
    if os.name == 'nt' or sys.platform == 'darwin':
        return True
    return bool(os.environ.get('DISPLAY') or os.environ.get('WAYLAND_DISPLAY'))


def has_vulkan():
    if os.name == 'nt' or sys.platform == 'darwin':
        return True
    if shutil.which('vulkaninfo'):
        probe = subprocess.run(['vulkaninfo', '--summary'], capture_output=True, text=True, timeout=60)
        return probe.returncode == 0 and 'deviceName' in probe.stdout
    icd_dirs = ['/usr/share/vulkan/icd.d', '/etc/vulkan/icd.d', '/usr/local/share/vulkan/icd.d']
    return any(Path(d).is_dir() and any(Path(d).glob('*.json')) for d in icd_dirs)


def import_project(engine):
    print('Refreshing the class cache (godot --editor --import)...', flush=True)
    result = subprocess.run([str(engine), '--headless', '--path', str(ROOT), '--editor', '--import', '--quit'],
                            capture_output=True, text=True, timeout=1200)
    if result.returncode != 0:
        sys.stderr.write(result.stdout[-2000:] + result.stderr[-2000:])
        raise SystemExit('Project import failed; see the output above.')


def render(engine, args, render_dir):
    width, height = args.size.split('x')
    cmd = [str(engine), '--path', str(ROOT), '--rendering-method', args.renderer, '--resolution', args.size,
           '--fixed-fps', str(args.fps), '--script', 'res://tools/trailer/trailer.gd', '--',
           '--out', str(render_dir), '--fps', str(args.fps), '--msaa', str(args.msaa)]
    if args.preview:
        cmd.append('--preview')
    if args.start is not None:
        cmd += ['--from', str(args.start)]
    if args.end is not None:
        cmd += ['--to', str(args.end)]
    if not has_display():
        if not shutil.which('xvfb-run'):
            raise SystemExit('No display and no xvfb-run: install xvfb (apt install xvfb) or run with a display.')
        cmd = ['xvfb-run', '-a', '-s', f'-screen 0 {width}x{height}x24'] + cmd
    print(f'Rendering {args.size} at {args.fps} fps with the {args.renderer} renderer -> {render_dir}', flush=True)
    started = time.time()
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
                            start_new_session=(os.name != 'nt'))
    done_at = None
    for line in proc.stdout:
        if line.startswith('trailer:') or 'SCRIPT ERROR' in line or line.startswith('ERROR: Failed'):
            print('  ' + line.rstrip(), flush=True)
        if line.startswith(DONE):
            done_at = time.time()
            break
    if done_at is not None:
        # Software Vulkan can stall during engine shutdown; everything is written by now.
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            _kill(proc)
    else:
        proc.wait()
        raise SystemExit(f'The render did not finish (exit code {proc.returncode}); see the lines above.')
    print(f'Rendered in {time.time() - started:.0f} s', flush=True)


def _kill(proc):
    if os.name == 'nt':
        proc.kill()
    else:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--godot', help='Godot 4.7.2 executable (default: the pinned engine in tools/.cache)')
    parser.add_argument('--out', type=Path, default=ROOT / 'builds' / 'trailer')
    parser.add_argument('--preview', action='store_true', help='640x360, 15 fps, cheap quality settings')
    parser.add_argument('--from', dest='start', type=float, help='start second (partial render)')
    parser.add_argument('--to', dest='end', type=float, help='end second (partial render)')
    parser.add_argument('--size', help='render WxH (default 2560x1440 supersampled for a 1080p master, '
                        'or 640x360 with --preview)')
    parser.add_argument('--msaa', type=int, default=4, choices=[2, 4], help='MSAA samples for full-quality renders')
    parser.add_argument('--fps', type=int, help='frames per second (default 30, or 15 with --preview)')
    parser.add_argument('--renderer', default='auto', choices=['auto', 'mobile', 'forward_plus', 'gl_compatibility'])
    parser.add_argument('--skip-import', action='store_true', help='skip the class-cache refresh')
    parser.add_argument('--no-video', action='store_true', help='render frames only')
    args, video_args = parser.parse_known_args()
    args.size = args.size or ('640x360' if args.preview else '2560x1440')
    args.fps = args.fps or (15 if args.preview else 30)
    if args.renderer == 'auto':
        args.renderer = 'mobile' if (not has_display() or has_vulkan()) else 'gl_compatibility'
    engine = find_engine(args.godot)
    if not args.skip_import:
        import_project(engine)
    out = args.out.resolve()
    render_dir = out / 'render'
    shutil.rmtree(render_dir / 'frames', ignore_errors=True)
    for stale in list(out.glob('trailer_*p*.mp4')) + list(out.glob('teaser_vertical_*p.mp4')) + [out / 'trailer_mix.wav']:
        stale.unlink(missing_ok=True)
    render(engine, args, render_dir)
    if args.no_video:
        print(f'Frames: {render_dir / "frames"}')
        return 0
    if args.preview and '--height' not in video_args:
        video_args += ['--height', args.size.split('x')[1], '--share-kbps', '2000']
    video = subprocess.run([sys.executable, str(Path(__file__).with_name('make_video.py')), '--render', str(render_dir),
                            '--out', str(out)] + video_args)
    if video.returncode != 0:
        return video.returncode
    print()
    for made in sorted(out.glob('*.mp4')):
        print(f'Video: {made}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
