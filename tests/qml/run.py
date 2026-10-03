#!/usr/bin/env python3
"""Real QtTest input offscreen; no live surfaces, backend actions, or writes."""
import json
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

directory = Path(__file__).resolve().parent
repo = directory.parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--screenshots", type=Path, help="Save optional 1x and 2x offscreen visual checks here")
args = parser.parse_args()
if args.screenshots:
    args.screenshots.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="strip-qml-") as temporary:
    config = Path(temporary)
    source = (directory / "shell.qml").read_text()
    source = source.replace("import Quickshell.Wayland", "import QtQuick.Window")
    source = source.replace("  PanelWindow {", "  Window {").replace("    exclusionMode: ExclusionMode.Ignore\n", "")
    source = source.replace('    WlrLayershell.namespace: "layout-strip-input-tests"\n', "")
    source = source.replace("    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None\n", "")
    source = source.replace("    anchors { bottom: true; left: true }", "    visible: true")
    source = source.replace("    implicitWidth: 496", "    width: 496").replace("    implicitHeight: 60", "    height: 60")
    source = source.replace("panel.implicitWidth", "panel.width")
    source = source.replace("LayoutStrip.BarWidget { backendEnabled:false }", '''LayoutStrip.BarWidget {
            backendEnabled:false
            surface: panel
          }''')
    (config / "shell.qml").write_text(source)
    (config / "LayoutStrip").symlink_to(repo / "plugin", target_is_directory=True)
    (config / "Commons").symlink_to("/usr/share/omarchy/shell/Commons", target_is_directory=True)
    (config / "Ui").mkdir()
    for entry in Path("/usr/share/omarchy/shell/Ui").iterdir():
        if entry.name != "KeyboardPanel.qml":
            (config / "Ui" / entry.name).symlink_to(entry)
    shutil.copy2(directory / "KeyboardPanel.qml", config / "Ui" / "KeyboardPanel.qml")
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", STRIP_TEST_POPUP="0")
    for name, candidate in (("STRIP_TEST_BROWSER_ICON", "/usr/share/icons/hicolor/32x32/apps/google-chrome.png"),
                            ("STRIP_TEST_NOTES_ICON", "/usr/share/icons/hicolor/512x512/apps/obsidian.png")):
        if Path(candidate).is_file():
            environment[name] = candidate
    if args.screenshots:
        environment["STRIP_TEST_ARTIFACTS"] = str(args.screenshots.resolve())
    for key in ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "QT_QPA_PLATFORMTHEME", "QT_IM_MODULE"):
        environment.pop(key, None)
    result = subprocess.run(["qs", "-p", str(config), "--no-color"], env=environment,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30, check=False)
print(result.stdout, end="")
match = re.search(r"STRIP_INPUT_RESULTS (\{[^\n]+\})", result.stdout)
summary = json.loads(match.group(1)) if match else None
sys.exit(0 if result.returncode == 0 and summary and summary["failures"] == 0 else 1)
