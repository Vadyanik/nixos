#!/usr/bin/env python3
"""Focus an exact Niri workspace ID rather than a per-output index."""
import json
import os
import socket
import sys

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as ipc:
    ipc.settimeout(3)
    ipc.connect(os.environ["NIRI_SOCKET"])
    request = {"Action": {"FocusWorkspace": {"reference": {"Id": int(sys.argv[1])}}}}
    ipc.sendall((json.dumps(request) + "\n").encode())
    response = json.loads(ipc.makefile("r").readline())
    if "Err" in response:
        sys.exit(str(response["Err"]))
