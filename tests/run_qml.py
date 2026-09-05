#!/usr/bin/env python3
"""Exercise QML without live navigation or configuration writes."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

source = Path(__file__).resolve().parent
shell = Path(os.environ.get('OMARCHY_PATH', '/usr/share/omarchy')) / 'shell'
with tempfile.TemporaryDirectory(prefix='layout-strip-qml-') as temporary:
    directory = Path(temporary)
    shutil.copy2(source / 'shell.qml', directory / 'shell.qml')
    for name, target in [('Commons', shell / 'Commons'), ('Ui', shell / 'Ui'),
                         ('LayoutStrip', source.parent)]:
        (directory / name).symlink_to(target, target_is_directory=True)
    result = subprocess.run(['qs', '-p', str(directory), '--no-color'], text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=20, check=False)
    print(result.stdout, end='')
    match = re.search(r'STRIP_INPUT_RESULTS (\{[^\n]+\})', result.stdout)
    summary = json.loads(match.group(1)) if match else None
    sys.exit(0 if result.returncode == 0 and summary and summary['failures'] == 0 else 1)
