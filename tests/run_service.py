#!/usr/bin/env python3
"""Test both publication identities using IPC to an owned offscreen QML process."""
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
for plugin_id in ('user1.layout-strip', 'io.github.mapleroyal.layout-strip'):
    with tempfile.TemporaryDirectory(prefix='strip-service-') as temporary:
        base = Path(temporary)
        (base/'Plugin').symlink_to(ROOT/'plugin', target_is_directory=True)
        (base/'Commons').symlink_to('/usr/share/omarchy/shell/Commons', target_is_directory=True)
        (base/'Ui').mkdir()
        for entry in Path('/usr/share/omarchy/shell/Ui').iterdir():
            if entry.name != 'KeyboardPanel.qml':
                (base/'Ui'/entry.name).symlink_to(entry)
        # The offscreen platform has no layer-shell backend. Use the same
        # window wrapper as the input suite; all plugin components remain real.
        shutil.copy2(ROOT/'tests/qml/KeyboardPanel.qml', base/'Ui/KeyboardPanel.qml')
        shutil.copy2(ROOT/'tests/service.qml', base/'shell.qml')
        runtime = base/'runtime'; runtime.mkdir(mode=0o700)
        environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='generic',
                           QT_STYLE_OVERRIDE='Fusion', XDG_RUNTIME_DIR=str(runtime),
                           STRIP_PLUGIN_ID=plugin_id)
        for key in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'WAYLAND_SOCKET', 'DISPLAY'):
            environment.pop(key, None)
        process = subprocess.Popen(['qs', '-p', str(base), '--no-color'], env=environment,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        output = ''
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                deadline = time.monotonic()+8
                while 'SERVICE_READY' not in output and time.monotonic() < deadline:
                    if not selector.select(max(0, deadline-time.monotonic())):
                        break
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        break
                    output += chunk.decode(errors='replace')
            if 'SERVICE_READY' not in output:
                raise RuntimeError(output)
            # Exact owned process plus a private runtime cannot select the login shell.
            response = subprocess.run(['qs', 'ipc', '--pid', str(process.pid), 'call', plugin_id, 'debug'],
                                      env=environment, capture_output=True, text=True, timeout=4, check=True)
            debug = json.loads(response.stdout)
            assert debug['protocolVersion'] == 2 and debug['instances'] == [], debug
            print('Service identity and widget injection passed:', plugin_id)
        finally:
            process.terminate()
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill(); process.communicate()
