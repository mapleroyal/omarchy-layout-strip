#!/usr/bin/env python3
"""Validate DesktopEntry runtime properties and icon bindings without live UI."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

directory = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix="strip-icons-") as temporary:
    base = Path(temporary)
    applications = base / "data" / "applications"
    applications.mkdir(parents=True)
    (applications / "test-chat.desktop").write_text(
        '[Desktop Entry]\nType=Application\nName=Test Chat\n'
        'Exec=omarchy-launch-webapp "https://chat.example.test/channels/@me"\n'
        'Icon=test-chat-icon\n', encoding="utf-8")
    (applications / "test-native.desktop").write_text(
        '[Desktop Entry]\nType=Application\nName=Test Native\n'
        'Exec=true\nStartupWMClass=CustomNative\nIcon=test-native-icon\n', encoding="utf-8")
    fixture = base / "fixture"
    fixture.mkdir()
    source = (directory / "shell.qml").read_text().replace('"../../plugin" as Strip', '"." as Strip')
    (fixture / "shell.qml").write_text(source)
    for name in ("IconResolver.qml", "IconModel.js"):
        shutil.copy2(directory.parent.parent / "plugin" / name, fixture / name)
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="generic", QT_STYLE_OVERRIDE="Fusion",
                       XDG_DATA_HOME=str(base / "data"), XDG_DATA_DIRS=str(base / "empty"),
                       XDG_CONFIG_HOME=str(base / "config"), XDG_CACHE_HOME=str(base / "cache"))
    environment.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["qs", "-p", str(fixture), "--no-color"],
                            env=environment, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=10, check=False)
    print(result.stdout, end="")
    match = re.search(r"ICON_RESULTS (\{[^\n]+\})", result.stdout)
    summary = json.loads(match.group(1)) if match else None
    raise SystemExit(0 if result.returncode == 0 and summary and summary["failures"] == 0 else 1)
