#!/usr/bin/env python3
"""Open a scanned location's directory without interpreting it as a command."""

import json
import os
from pathlib import Path
import stat
import subprocess
import sys


def directory_for(path: str) -> str:
    candidate = Path(path)
    if not candidate.is_absolute() or len(path) > 4096 or "\0" in path or ".." in candidate.parts:
        raise ValueError("Invalid location")
    # Never follow a link substituted after the scan. Opening is read-only, but
    # redirecting a click somewhere unexpected would still be misleading.
    for component in (*reversed(candidate.parents), candidate):
        if component.is_symlink():
            raise ValueError("The location contains a symbolic link")
    mode = candidate.stat(follow_symlinks=False).st_mode
    if stat.S_ISDIR(mode):
        folder = candidate
    elif stat.S_ISREG(mode):
        folder = candidate.parent
    else:
        raise ValueError("The location is not a directory or regular file")
    if not os.access(folder, os.R_OK | os.X_OK):
        raise PermissionError("The folder is not accessible")
    return os.fspath(folder)


def main() -> int:
    if len(sys.argv) != 2:
        print("Expected one scanned location", file=sys.stderr)
        return 2
    try:
        folder = directory_for(sys.argv[1])
        # FileManager1 acknowledges the request rather than keeping this helper
        # attached to a GUI process or a portal chooser.
        result = subprocess.run(
            ["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
             "--object-path", "/org/freedesktop/FileManager1", "--method",
             "org.freedesktop.FileManager1.ShowFolders",
             json.dumps([Path(folder).as_uri()]), ""],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, timeout=8, check=False,
        )
        if result.returncode:
            print("The file manager could not open this folder", file=sys.stderr)
            return 1
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(str(error)[:512], file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
