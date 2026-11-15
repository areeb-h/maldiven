#!/usr/bin/env python3
"""Assemble the Drift Station trailer from a trailer.gd render.

Takes the PNG sequence and cues.json written by tools/trailer/trailer.gd, builds
the sound effects track from the cue sheet (game SFX in assets/audio), mixes in
the score (ducked under the effects) when present, downscales the frames with
Lanczos (render supersampled, e.g. 2560x1440, for a crisp 1080p) and encodes:

  trailer_1080p.mp4          master: H.264 High, CRF 16, preset slow, tune film, AAC 256k
  trailer_1080p_share.mp4    share copy: 2-pass ~8 Mbit/s (about 80 MB for the cut)
  teaser_vertical_1080p.mp4  ~15 s 1080x1920 cut from the same frames, CRF 18

Usage: python3 tools/trailer/make_video.py --render <dir> --out <dir>
           [--height 1080] [--share-kbps 8000] [--max-mb N] [--music PATH] [--no-teaser]

--max-mb N additionally writes trailer_<h>p_capped.mp4, raising CRF until it
fits N MB (no size cap by default).
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIO = ROOT / 'assets' / 'audio'
DEFAULT_MUSIC = AUDIO / 'music' / 'trailer_theme.wav'
# (start, end) seconds of the full cut used for the vertical teaser, in order.
TEASER = [(4.2, 6.2), (7.1, 9.2), (21.2, 22.8), (37.0, 38.5), (40.4, 42.4), (56.0, 58.0), (64.5, 66.6), (74.6, 76.9)]


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr[-3000:])
        raise SystemExit(f'ffmpeg failed: {" ".join(cmd[:6])} ...')


def build_audio(sheet, music, out_wav):
    """Effects from the cue sheet, plus the score ducked under them."""
    duration = sheet['frames'] / sheet['fps']
    cues = [c for c in sheet['cues'] if (AUDIO / f"{c['sound']}.wav").exists()]
    cmd = ['ffmpeg', '-y', '-f', 'lavfi', '-t', f'{duration:.3f}', '-i', 'anullsrc=r=48000:cl=stereo']
    for cue in cues:
        cmd += ['-i', str(AUDIO / f"{cue['sound']}.wav")]
    parts = []
    labels = ['[0:a]']
    for i, cue in enumerate(cues, start=1):
        delay = max(0, int((cue['t'] - sheet['from']) * 1000))
        parts.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,volume={cue['gain_db']}dB,"
                     f"adelay={delay}|{delay}[c{i}]")
        labels.append(f'[c{i}]')
    parts.append(f"{''.join(labels)}amix=inputs={len(labels)}:normalize=0:duration=first,alimiter=limit=0.95[sfx]")
    if music and Path(music).exists():
        cmd += ['-stream_loop', '-1', '-i', str(music)]
        m = len(cues) + 1
        parts.append('[sfx]asplit=2[sfx_mix][sfx_key]')
        parts.append(f'[{m}:a]aresample=48000,aformat=channel_layouts=stereo,atrim=0:{duration:.3f},'
                     f'afade=t=out:st={max(0.0, duration - 0.8):.3f}:d=0.8,volume=-3dB[mus]')
        parts.append('[mus][sfx_key]sidechaincompress=threshold=0.05:ratio=6:attack=15:release=350[ducked]')
        parts.append('[ducked][sfx_mix]amix=inputs=2:normalize=0:duration=first,alimiter=limit=0.95[out]')
    else:
        parts.append('[sfx]anull[out]')
    cmd += ['-filter_complex', ';'.join(parts), '-map', '[out]', '-c:a', 'pcm_s16le', str(out_wav)]
    run(cmd)


def _frames(render, fps):
    return ['-framerate', str(fps), '-i', str(render / 'frames' / 'f_%05d.png')]


def _scale(height):
    return f'scale=-2:{height}:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p'


def encode_master(render, audio_wav, fps, height, out_mp4, crf=16):
    run(['ffmpeg', '-y'] + _frames(render, fps) + ['-i', str(audio_wav), '-vf', _scale(height),
         '-c:v', 'libx264', '-preset', 'slow', '-tune', 'film', '-crf', str(crf), '-profile:v', 'high',
         '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '256k', '-movflags', '+faststart', '-shortest', str(out_mp4)])


def encode_share(render, audio_wav, fps, height, out_mp4, kbps):
    log = out_mp4.with_suffix('.2pass')
    common = ['-vf', _scale(height), '-c:v', 'libx264', '-preset', 'slow', '-tune', 'film', '-profile:v', 'high',
              '-b:v', f'{kbps}k', '-maxrate', f'{int(kbps * 1.6)}k', '-bufsize', f'{kbps * 3}k',
              '-pix_fmt', 'yuv420p', '-passlogfile', str(log)]
    run(['ffmpeg', '-y'] + _frames(render, fps) + common + ['-pass', '1', '-an', '-f', 'mp4', '/dev/null'])
    run(['ffmpeg', '-y'] + _frames(render, fps) + ['-i', str(audio_wav)] + common +
        ['-pass', '2', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', '-shortest', str(out_mp4)])
    for leftover in log.parent.glob(log.name + '*'):
        leftover.unlink()


def encode_capped(render, audio_wav, fps, height, out_mp4, max_mb):
    for crf in (18, 20, 23, 26, 29):
        encode_master(render, audio_wav, fps, height, out_mp4, crf)
        if out_mp4.stat().st_size / 1e6 <= max_mb:
            break


def teaser(render, audio_wav, fps, out_mp4, height_share):
    """Vertical 1080x1920 from the master frames: the letterboxed picture centred
    over a blurred, zoomed fill."""
    parts, labels = [], []
    for i, (a, b) in enumerate(TEASER):
        parts.append(f'[0:v]trim={a}:{b},setpts=PTS-STARTPTS[v{i}];[1:a]atrim={a}:{b},asetpts=PTS-STARTPTS,'
                     f'afade=t=in:d=0.05,afade=t=out:st={b - a - 0.08:.2f}:d=0.08[a{i}]')
        labels.append(f'[v{i}][a{i}]')
    pic = 1.0 - 2.0 * height_share
    parts.append(f"{''.join(labels)}concat=n={len(TEASER)}:v=1:a=1[cv][ca]")
    parts.append('[cv]split=2[bgsrc][fgsrc]')
    parts.append('[bgsrc]scale=-2:1920:flags=lanczos,crop=1080:1920,gblur=sigma=28,eq=brightness=-0.12[bg]')
    parts.append(f'[fgsrc]crop=iw:trunc(ih*{pic:.4f}/2)*2:0:(ih-oh)/2,scale=1080:-2:flags=lanczos+accurate_rnd[fg]')
    parts.append('[bg][fg]overlay=(W-w)/2:(H-h)/2,format=yuv420p[vout]')
    run(['ffmpeg', '-y'] + _frames(render, fps) + ['-i', str(audio_wav), '-filter_complex', ';'.join(parts),
         '-map', '[vout]', '-map', '[ca]', '-c:v', 'libx264', '-preset', 'slow', '-tune', 'film', '-crf', '18',
         '-profile:v', 'high', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', str(out_mp4)])


def describe(path):
    probe = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                            'stream=width,height,bit_rate:format=duration,size,bit_rate', '-of', 'json', str(path)],
                           capture_output=True, text=True)
    info = json.loads(probe.stdout or '{}')
    stream = (info.get('streams') or [{}])[0]
    fmt = info.get('format', {})
    video_kbps = int(stream.get('bit_rate', 0)) / 1000
    return (f'{path}: {stream.get("width")}x{stream.get("height")}, {float(fmt.get("duration", 0)):.1f} s, '
            f'{int(fmt.get("size", 0)) / 1e6:.1f} MB, video {video_kbps / 1000:.2f} Mbit/s, '
            f'total {int(fmt.get("bit_rate", 0)) / 1e6:.2f} Mbit/s')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--render', type=Path, required=True, help='trailer.gd --out directory')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--music', type=Path, default=DEFAULT_MUSIC)
    parser.add_argument('--height', type=int, default=1080, help='output height (frames are Lanczos-scaled)')
    parser.add_argument('--share-kbps', type=int, default=8000, help='video bitrate of the share copy')
    parser.add_argument('--max-mb', type=float, help='also write a size-capped copy')
    parser.add_argument('--no-teaser', action='store_true')
    args = parser.parse_args()
    cues = args.render / 'cues.json'
    first = args.render / 'frames' / 'f_00000.png'
    if not cues.is_file() or not first.is_file():
        print(f'No frames found in {args.render}: render first, e.g.\n'
              f'  python3 tools/trailer/render_trailer.py --preview', file=sys.stderr)
        return 1
    if not shutil.which('ffmpeg'):
        print('ffmpeg is not installed (e.g. apt install ffmpeg); the frames are in ' + str(args.render), file=sys.stderr)
        return 1
    sheet = json.loads(cues.read_text())
    fps = sheet['fps']
    h = args.height
    args.out.mkdir(parents=True, exist_ok=True)
    audio_wav = args.out / 'trailer_mix.wav'
    build_audio(sheet, args.music, audio_wav)
    print(f'music: {"yes" if args.music.exists() else "no"}')
    master = args.out / f'trailer_{h}p.mp4'
    encode_master(args.render, audio_wav, fps, h, master)
    print(describe(master))
    share = args.out / f'trailer_{h}p_share.mp4'
    encode_share(args.render, audio_wav, fps, h, share, args.share_kbps)
    print(describe(share))
    if args.max_mb:
        capped = args.out / f'trailer_{h}p_capped.mp4'
        encode_capped(args.render, audio_wav, fps, h, capped, args.max_mb)
        print(describe(capped))
    if not args.no_teaser and sheet['from'] == 0 and sheet['frames'] / fps >= TEASER[-1][1]:
        vertical = args.out / f'teaser_vertical_{h}p.mp4'
        teaser(args.render, audio_wav, fps, vertical, 0.128)
        print(describe(vertical))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
