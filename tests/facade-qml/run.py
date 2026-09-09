#!/usr/bin/env python3
"""Check scoped bar geometry bindings offscreen without desktop access."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

directory = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="strip-facade-") as temporary:
    config = Path(temporary)
    shutil.copy2(directory / "shell.qml", config / "shell.qml")
    (config / "Plugin").symlink_to(directory.parent.parent / "plugin", target_is_directory=True)
    runtime = config / "runtime"
    runtime.mkdir(mode=0o700)
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       QT_QPA_PLATFORMTHEME="generic", QT_STYLE_OVERRIDE="Fusion",
                       XDG_RUNTIME_DIR=str(runtime))
    for key in ("WAYLAND_DISPLAY", "WAYLAND_SOCKET", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "QT_IM_MODULE"):
        environment.pop(key, None)
    result = subprocess.run(["qs", "-p", str(config), "--no-color"], env=environment,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            timeout=10, check=False)
print(result.stdout, end="")
match = re.search(r"FACADE_GEOMETRY_RESULTS (\{[^\n]+\})", result.stdout)
summary = json.loads(match.group(1)) if match else None
sys.exit(0 if result.returncode == 0 and summary and summary["failures"] == 0 else 1)
