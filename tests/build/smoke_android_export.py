#!/usr/bin/env python3
"""Optional real-engine smoke test of an isolated tiny app, never the blocked game."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/build'))
from android_common import sha256


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default='godot')
    parser.add_argument('--template',type=Path,required=True)
    args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='shigan-fixture-') as temporary:
        work=Path(temporary); root=work/'fixture'; root.mkdir()
        files=['addons/chapter_export/plugin.gd','addons/chapter_export/plugin.cfg',
               'tools/build/export_readiness.gd','tools/build/production_export_filter.gd',
               'assets/art/ui/game_icon.png']
        for relative in files:
            path=root/relative; path.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/relative,path)
        content={
            'game/main.gd':'extends Node2D\nfunc _ready(): pass\n',
            'scenes/main.tscn':'[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://game/main.gd" id="1"]\n[node name="Fixture" type="Node2D"]\nscript = ExtResource("1")\n',
            'data/fixture.json':'{"fixture":true}',
            'chapters/fixture.json':'{"fixture":true}',
            'project.godot':'config_version=5\n[application]\nconfig/name="Build fixture only"\nconfig/icon="res://assets/art/ui/game_icon.png"\nrun/main_scene="res://scenes/main.tscn"\n[editor_plugins]\nenabled=PackedStringArray("res://addons/chapter_export/plugin.cfg")\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',
        }
        for relative,text in content.items():
            path=root/relative; path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text,encoding='utf-8')
        manifest={'assets':{'game_icon':{'path':'res://assets/art/ui/game_icon.png','sha256':sha256(root/'assets/art/ui/game_icon.png')}},'art_revision_status':{'final_export_allowed':True}}
        (root/'assets/manifest.json').write_text(json.dumps(manifest),encoding='utf-8')
        result=subprocess.run([sys.executable,str(ROOT/'tools/build/build_android.py'),
                               '--project',str(root),'--godot',args.godot,
                               '--template',str(args.template.resolve()),'--output',str(work/'fixture.apk')])
        if result.returncode: return result.returncode
        report=json.loads((work/'fixture.apk.build.json').read_text(encoding='utf-8'))
        if report['permissions'] or report['signed'] or report['abi']!='arm64-v8a':
            raise RuntimeError('Fixture package verification failed')
        print('PASS: isolated unsigned Android fixture; temporary fixture/output removed on exit')
        return 0

if __name__ == '__main__': sys.exit(main())
