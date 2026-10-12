"""Real Godot save-root probe in a disposable profile; never reads user saves."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform.startswith('linux') and shutil.which('godot'),
                     'This disposable XDG profile probe requires Linux Godot')
class DesktopSaveIdentityTests(unittest.TestCase):
    def test_renamed_project_reads_the_unchanged_legacy_save_location(self):
        with tempfile.TemporaryDirectory(prefix='wings-save-root-') as directory:
            work = Path(directory)
            env = {**os.environ, 'XDG_DATA_HOME': str(work/'data'),
                   'XDG_CONFIG_HOME': str(work/'config'), 'XDG_CACHE_HOME': str(work/'cache')}
            for key in ('XDG_DATA_HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME'):
                Path(env[key]).mkdir()
            script = '''extends SceneTree
func _initialize() -> void:
 var marker := "user://saves/identity-probe.txt"
 var mode := OS.get_cmdline_user_args()[0]
 if mode == "write":
  DirAccess.make_dir_recursive_absolute("user://saves")
  var file := FileAccess.open(marker,FileAccess.WRITE)
  file.store_string("preserved-save")
  file.close()
 print("IDENTITY=" + JSON.stringify({"path":OS.get_user_data_dir(),"marker":FileAccess.get_file_as_string(marker)}))
 quit()
'''
            old = 'config_version=5\n[application]\nconfig/name="진격의 거인: 인류의 날개"\n'
            current = (ROOT/'project.godot').read_text()
            observed = []
            for name, config, mode in [('legacy', old, 'write'), ('current', current, 'read')]:
                project = work/name; project.mkdir()
                (project/'project.godot').write_text(config)
                (project/'probe.gd').write_text(script)
                result = subprocess.run(['godot','--headless','--path',str(project),
                    '--script','probe.gd','--',mode], env=env, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('SCRIPT ERROR:', result.stderr)
                records = [line.removeprefix('IDENTITY=') for line in result.stdout.splitlines()
                           if line.startswith('IDENTITY=')]
                self.assertEqual(len(records), 1, result.stdout + result.stderr)
                observed.append(json.loads(records[0]))
            self.assertEqual(observed[0]['path'], observed[1]['path'])
            self.assertEqual(observed[1]['marker'], 'preserved-save')
            self.assertTrue(observed[1]['path'].endswith('/godot/app_userdata/진격의 거인- 인류의 날개'))


if __name__ == '__main__': unittest.main()
