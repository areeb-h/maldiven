#!/usr/bin/env python3
"""Export a normal APK or a side-by-side Compatibility diagnostic build.
Requires a configured Godot Android SDK and matching export templates.
"""
import argparse, pathlib, shutil, subprocess, tempfile
from bootstrap_godot import ensure_engine, validate_engine

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--godot',help='Pinned Godot executable; otherwise bootstrap the Linux build host')
 p.add_argument('--renderer',choices=['mobile','compatibility'],default='mobile')
 args=p.parse_args()
 root=pathlib.Path(__file__).resolve().parents[1]
 out=root/'builds'/('maldiven-resources-'+args.renderer+'-arm64.apk');out.parent.mkdir(exist_ok=True)
 try:
  engine,_=validate_engine(args.godot or ensure_engine())
 except (OSError,RuntimeError,subprocess.SubprocessError) as exc:
  p.error(str(exc))
 engine=str(engine)
 with tempfile.TemporaryDirectory(prefix='maldiven-export-') as temp:
  stage=pathlib.Path(temp)/'project'
  shutil.copytree(root,stage,ignore=shutil.ignore_patterns('.git','.godot','builds','tools','previews'))
  if args.renderer=='compatibility':
   config=stage/'project.godot';text=config.read_text()
   text=text.replace('renderer/rendering_method="mobile"','renderer/rendering_method="gl_compatibility"')
   text=text.replace('renderer/rendering_method.mobile="mobile"','renderer/rendering_method.mobile="gl_compatibility"')
   text=text.replace('"4.7", "Mobile"','"4.7", "GL Compatibility"');config.write_text(text)
   config=stage/'export_presets.cfg';text=config.read_text().replace('com.areebh.maldiven"','com.areebh.maldiven.compat"').replace('package/name="Maldiven"','package/name="Maldiven GL Test"');config.write_text(text)
  subprocess.run([engine,'--headless','--path',str(stage),'--editor','--import'],check=True)
  subprocess.run([engine,'--headless','--path',str(stage),'--export-debug','Android',str(out)],check=True)
 print(out)

if __name__=='__main__':main()
