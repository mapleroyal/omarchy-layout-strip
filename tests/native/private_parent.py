"""Run headless.py with an explicitly supplied, privately built Weston parent.

The supplied Aquamarine library affects only the child test process. No display
socket or process from the login session is used, and no libraries are installed.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--weston-build', required=True, type=Path)
parser.add_argument('--aquamarine-build', required=True, type=Path)
parser.add_argument('--plugin', required=True, type=Path)
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
build = args.weston_build.resolve()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
runtime = Path(tempfile.mkdtemp(prefix='ls-weston-parent-'))
runtime.chmod(0o700)
env = os.environ.copy()
for name in ['WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'DISPLAY', 'HYPRLAND_INSTANCE_SIGNATURE', 'I3SOCK', 'SWAYSOCK']:
    env.pop(name, None)
env['XDG_RUNTIME_DIR'] = str(runtime)
env['LD_LIBRARY_PATH'] = ':'.join(str(build / p) for p in ['libweston', 'frontend'])
modules = {'headless-backend.so': 'libweston/backend-headless/headless-backend.so',
           'gl-renderer.so': 'libweston/renderer-gl/gl-renderer.so',
           'kiosk-shell.so': 'kiosk-shell/kiosk-shell.so'}
env['WESTON_MODULE_MAP'] = ';'.join(k + '=' + str(build / v) for k, v in modules.items())
parent = None
try:
    with (out / 'weston.log').open('w') as log:
        parent = subprocess.Popen([str(build / 'frontend/weston'), '--backend=headless',
            '--renderer=gl', '--shell=kiosk-shell.so', '--width=1600', '--height=1000',
            '--socket=layout-strip-parent', '--idle-time=0', '--no-config'],
            env=env, stdout=log, stderr=subprocess.STDOUT)
    for _ in range(100):
        if parent.poll() is not None:
            raise RuntimeError('Private Weston failed; see ' + str(out / 'weston.log'))
        if (runtime / 'layout-strip-parent').is_socket():
            break
        time.sleep(.1)
    else:
        raise RuntimeError('Private Weston startup timeout')
    child_env = os.environ.copy()
    child_env['LD_LIBRARY_PATH'] = str(args.aquamarine_build.resolve())
    result = subprocess.run(['python3', str(Path(__file__).with_name('headless.py')),
        '--plugin', str(args.plugin.resolve()), '--output', str(out),
        '--parent-display', str(runtime / 'layout-strip-parent')], env=child_env)
    raise SystemExit(result.returncode)
finally:
    if parent is not None and parent.poll() is None:
        parent.terminate()
        try:
            parent.wait(timeout=5)
        except subprocess.TimeoutExpired:
            parent.kill()
            parent.wait()
    shutil.rmtree(runtime)
