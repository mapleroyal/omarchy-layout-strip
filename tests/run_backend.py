#!/usr/bin/env python3
"""Exercise the real QML scheduler with fake hyprctl; never contacts the compositor."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='layout-strip-backend-') as temporary:
    directory = Path(temporary)
    (directory / 'Plugin').symlink_to(root / 'plugin', target_is_directory=True)
    (directory / 'Commons').symlink_to('/usr/share/omarchy/shell/Commons', target_is_directory=True)
    (directory / 'Ui').symlink_to('/usr/share/omarchy/shell/Ui', target_is_directory=True)
    shutil.copy2(root / 'tests/backend.qml', directory / 'shell.qml')
    mock = directory / 'hyprctl'
    mock.write_text('''#!/usr/bin/python3
import json,re,sys,time
code=sys.argv[-1]
if "return api.snapshot_all(" in code:
 time.sleep(.08)
 print(json.dumps({"ok":True,"protocolVersion":2,"snapshots":[{"ok":True,"protocolVersion":2,"workspaceId":i+1,"monitorName":name,"columns":[]} for i,name in enumerate(["eDP-1","DP-2"])]}))
elif "return api.protect_regions(" in code:
 print('{"ok":true,"protocolVersion":2}')
elif "return api.focus(" in code:
 time.sleep(.12)
 literal=code.split("return api.focus(",1)[1].split('"',2)[1]
 address=bytes(int(v) for v in re.findall(r"\\\\(\\d{3})",literal)).decode()
 print(json.dumps({"ok":True,"changed":True,"protocolVersion":2,"address":address}))
else:
 raise SystemExit("Unexpected fake RPC")
''')
    mock.chmod(0o755)
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='generic', QT_STYLE_OVERRIDE='Fusion', PATH=str(directory) + os.pathsep + os.environ['PATH'])
    environment.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
    environment.pop('WAYLAND_DISPLAY', None)
    run = subprocess.run(['quickshell','-p',str(directory),'--no-color'],env=environment,
                         stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=15)
    print(run.stdout, end='')
    found = re.search(r'BACKEND_RESULTS (\{[^\n]+\})',run.stdout)
    result = json.loads(found.group(1)) if found else None
    if run.returncode or not result or result['failures']:
        raise SystemExit(1)
