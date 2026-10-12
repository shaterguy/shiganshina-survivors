"""Test-only BFS operation counting without adding a product diagnostic or subclass.
Runs the exact navigation scripts in a temporary copy, preserving script identity.
"""
from pathlib import Path
import os, shutil, subprocess, tempfile
source=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='navigation-field-tests-') as name:
    project=Path(name)/'project'
    shutil.copytree(source,project,ignore=shutil.ignore_patterns('.git','artifacts'))
    nav=project/'game/world/city_navigation.gd'
    s=nav.read_text()
    old='\twhile head < queue.size():\n\t\tvar id := queue[head]'
    assert s.count(old)==1
    s=s.replace(old,'\tset_meta("field_expansions",int(get_meta("field_expansions",0))+1)\n'+old)
    nav.write_text(s)
    raise SystemExit(subprocess.call(['godot','--headless','--path',str(project),'--script','res://tests/run_all.gd','--','navigation_field_reuse'],env={**os.environ,"FIELD_TEST_INSTRUMENTED":"1"}))
