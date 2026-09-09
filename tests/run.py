#!/usr/bin/env python3
"""Run deterministic and offscreen tests without touching desktop configuration."""
from pathlib import Path
import os
import shlex
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[1]
def run(args):
    print('+ '+shlex.join(map(str,args)),flush=True)
    subprocess.run(list(map(str,args)),cwd=ROOT,check=True,timeout=60)

for name in ('Geometry.test.cjs','HostAdapter.test.cjs','ScopedHost.test.cjs','IconModel.test.cjs','model.test.cjs','protocol.cjs'):
    run(['node','tests/'+name])
for source in sorted((ROOT/'tests/lua').glob('*.lua')):
    run(['lua',source,'backend/'])
run([sys.executable,'-m','unittest','discover','-s','tests/python'])
run([sys.executable,'tests/test_install.py'])
with tempfile.TemporaryDirectory(prefix='strip-cpp-tests-') as temporary:
    directory=Path(temporary)
    compiler=os.environ.get('CXX','g++')
    for name in ('test-reorder','test-bar-press','test-regions'):
        extra=[]
        if name=='test-bar-press':
            extra=shlex.split(subprocess.check_output(['pkg-config','--cflags','--libs','hyprutils','wayland-server'],text=True))
        executable=directory/name
        run([compiler,'-std=c++26','-O2','-Wall','-Wextra','-I',ROOT/'native',ROOT/'tests/native'/f'{name}.cpp','-o',executable,*extra])
        run([executable])
run([sys.executable,'tests/icons/run.py'])
run([sys.executable,'tests/run_service.py'])
run([sys.executable,'tests/run_backend.py'])
run([sys.executable,'tests/facade-qml/run.py'])
run([sys.executable,'tests/qml/run.py'])
print('All deterministic and offscreen suites passed',flush=True)
