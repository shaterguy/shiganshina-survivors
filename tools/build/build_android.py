#!/usr/bin/env python3
"""Build unsigned Android APKs; final requires approval, explicit validation preserves pending art."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from android_common import BuildError, ROOT, PIN, engine_environment, read_manifest, sha256, stage_project, verify_apk, verify_source_hashes, verify_template


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--godot', default='godot', help='Path to the pinned official standard Godot executable')
    parser.add_argument('--template', type=Path, help='Extracted templates/android_debug.apk (no SDK required)')
    parser.add_argument('--output', type=Path, default=ROOT/'dist/shiganshina-dev-unsigned.apk')
    parser.add_argument('--development-validation', action='store_true', help='Build incomplete validation-only package with five approved basic placeholders; never approve final art')
    parser.add_argument('--check-ready', action='store_true', help='Check manifest approval and source assets only; never launch Godot')
    parser.add_argument('--timeout', type=int, default=600)
    args = parser.parse_args()
    try:
        root, output = args.project.resolve(), args.output.resolve()
        manifest = read_manifest(root, development_validation=args.development_validation)  # First: no tool, key, cache or output work while blocked.
        verify_source_hashes(root, manifest)
        if args.check_ready:
            print('DEVELOPMENT_VALIDATION_READY: five basic placeholders; final_export_allowed=false' if args.development_validation else 'EXPORT_READY: approved manifest and asset hashes verified')
            return 0
        if not args.template: raise BuildError('--template is required; see docs/build/android-local.md')
        template = args.template.expanduser().resolve()
        verify_template(template)
        if output.exists() or output.with_suffix('.apk.build.json').exists(): raise BuildError('Output or report already exists; choose a new output path')
        if output.suffix.lower() != '.apk': raise BuildError('Output must end in .apk')
        engine = shutil.which(args.godot)
        if not engine: raise BuildError('Godot executable not found; provide --godot')
        engine = str(Path(engine).resolve())
        with tempfile.TemporaryDirectory(prefix='shigan-build-') as temporary:
            work=Path(temporary); env=engine_environment(work/'profile')
            version = subprocess.run([engine,'--headless','--version'], env=env, capture_output=True, text=True, timeout=30)
            if version.returncode or version.stdout.strip() != PIN['godot_version']:
                raise BuildError('Godot version must be exactly ' + PIN['godot_version'])
            staged = work/'project'
            provenance = stage_project(root, staged, manifest)
            staged_manifest = read_manifest(staged, development_validation=args.development_validation)
            verify_source_hashes(staged, staged_manifest)
            built=work/'unsigned.apk'
            env.update({'SHIGAN_EXPORT_MODE':'development-validation' if args.development_validation else 'final', 'SHIGAN_EXPORT_KIND':'android','SHIGAN_EXPORT_TEMPLATE':str(template),'SHIGAN_EXPORT_OUTPUT':str(built)})
            # EditorPlugin export_project is intentional. --export-debug invokes the SDK/signing prerequisite check.
            result=subprocess.run([engine,'--headless','--editor','--path',str(staged)], env=env, capture_output=True, text=True, timeout=args.timeout)
            log=result.stdout+'\n'+result.stderr
            if result.returncode or 'EXPORT_RESULT kind=android code=0' not in log or re.search(r'^(SCRIPT ERROR:|ERROR:)',log,re.M):
                # This process has no credentials or private source files. Limit diagnostic size.
                print(log[-12000:], file=sys.stderr)
                raise BuildError('Godot export failed; no output APK was published')
            report=verify_apk(built,template,staged,staged_manifest,development_validation=args.development_validation)
            report.update(provenance)
            report.update({'godot_version':PIN['godot_version'],'template_sha256':PIN['template']['sha256'],'signed':False,'certificate_sha256':None})
            output.parent.mkdir(parents=True, exist_ok=True)
            with output.open('xb') as dest, built.open('rb') as src: shutil.copyfileobj(src,dest)
        report_path=output.with_suffix('.apk.build.json')
        with report_path.open('x', encoding='utf-8') as stream: json.dump(report,stream,indent=2); stream.write('\n')
        if sha256(output) != report['sha256']: raise BuildError('Published APK SHA-256 mismatch')
        print(json.dumps(report,indent=2))
        print('UNSIGNED_APK: '+str(output))
        return 0
    except subprocess.TimeoutExpired:
        print('BUILD_BLOCKED: Godot timed out; no output APK was published',file=sys.stderr)
        return 2
    except (BuildError,OSError,ValueError) as exc:
        print('BUILD_BLOCKED: '+str(exc),file=sys.stderr)
        return 2

if __name__ == '__main__': sys.exit(main())
