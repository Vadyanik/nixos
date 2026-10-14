"""Focus a numbered workspace by name, with native zoom when supported."""

import json
import os
import socket
import sys


def request(action, name):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as ipc:
        ipc.settimeout(3)
        ipc.connect(os.environ["NIRI_SOCKET"])
        message = {"Action": {action: {"reference": {"Name": name}}}}
        ipc.sendall((json.dumps(message) + "\n").encode())
        response = ipc.makefile("r").readline()
        if not response:
            raise RuntimeError("Niri closed the IPC connection without a response")
        return json.loads(response)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in {str(i) for i in range(1, 11)}:
        raise ValueError("Expected a workspace number from 1 to 10")
    name = sys.argv[1]
    result = request("FocusWorkspaceZoom", name)
    if "Err" in result:
        # The already-running compositor may predate the installed zoom package.
        error = str(result["Err"])
        unsupported = error == "error parsing request" or (
            "unknown variant" in error and "FocusWorkspaceZoom" in error
        )
        if not unsupported:
            raise RuntimeError(error)
        result = request("FocusWorkspace", name)
    if "Err" in result:
        raise RuntimeError(result["Err"])


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, ValueError) as error:
        sys.exit(str(error))
