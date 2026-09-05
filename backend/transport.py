#!/usr/bin/env python3
"""One-request JSON transport for the scrolling layout bar."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


def lua_string(value):
    # Numeric byte escapes are unambiguous in Lua and never become shell text.
    return '"' + ''.join(f'\\{byte:03d}' for byte in value.encode('utf-8')) + '"'


def request_code(command, monitor=None, address=None, workspace=None):
    """Load only this checkout's backend; reuse a configured tape integration."""
    directory = Path(__file__).resolve().parent
    create_backend = (
        f'local tape = dofile({lua_string(str(directory / "tape.lua"))}).new(hl); '
        f'local backend = omarchy_tape_bar or dofile({lua_string(str(directory / "tape-bar.lua"))})'
        '.new(hl, tape, function(result) return result end); '
    )
    monitor_literal = lua_string(monitor) if monitor else 'nil'
    invocation = (f'backend.snapshot({monitor_literal})' if command == 'snapshot' else
                  f'backend.focus({lua_string(address)}, {workspace}, {monitor_literal})')
    return create_backend + 'return ' + invocation


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    snapshot = commands.add_parser('snapshot')
    snapshot.add_argument('--monitor')
    focus = commands.add_parser('focus')
    focus.add_argument('address')
    focus.add_argument('--workspace', type=int, required=True)
    focus.add_argument('--monitor')
    args = parser.parse_args()
    if args.command == 'focus' and not re.fullmatch(r'0x[0-9a-fA-F]+', args.address):
        parser.error('address must be a Hyprland hexadecimal window address')
    code = request_code(args.command, args.monitor, getattr(args, 'address', None),
                        getattr(args, 'workspace', None))
    try:
        completed = subprocess.run(['hyprctl', 'repl', code], capture_output=True, text=True, timeout=3, check=False)
        if completed.returncode:
            raise RuntimeError(completed.stderr.strip() or completed.stdout.strip() or 'hyprctl failed')
        result = json.loads(completed.stdout)
        if not isinstance(result, dict) or 'ok' not in result:
            raise ValueError('unexpected reply from Hyprland')
    except (OSError, subprocess.SubprocessError, ValueError, RuntimeError) as error:
        result = {'ok': False, 'error': str(error), 'columns': []}
    print(json.dumps(result, ensure_ascii=False, separators=(',', ':')))
    return 0 if result['ok'] else 1


if __name__ == '__main__':
    sys.exit(main())
