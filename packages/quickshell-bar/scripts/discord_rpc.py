#!/usr/bin/env python3
"""Local Discord RPC bridge for the Quickshell Control Center."""
from __future__ import annotations

import getpass
import base64
import json
import os
import queue
import secrets
import socket
import struct
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
CONFIG = Path.home() / ".config/quickshell/discord-rpc.json"
STATUS = RUNTIME / "quickshell-discord.json"
ACTION_SOCKET = RUNTIME / "quickshell-discord.sock"
REDIRECT_URI = "http://127.0.0.1:8765/callback"
RPC_TIMEOUT = 5


def write_json(path: Path, value: dict, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + f".{os.getpid()}.tmp")
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, mode)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f, ensure_ascii=False)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(temp, path)
        os.chmod(path, mode)
    finally:
        try:
            temp.unlink()
        except FileNotFoundError:
            pass


def post_form(url: str, values: dict) -> dict:
    form = dict(values)
    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json, text/plain, */*",
        "Origin": "https://discord.com",
        "Referer": "https://discord.com/developers/",
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.7827.102 Safari/537.36",
    }
    client_id = form.pop("client_id", None)
    client_secret = form.pop("client_secret", None)
    if client_id and client_secret:
        credentials = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode("ascii")
        headers["Authorization"] = f"Basic {credentials}"
    data = urllib.parse.urlencode(form).encode()
    request = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"Discord token request failed ({exc.code}): {body[:300]}") from exc


def find_rpc_socket() -> str:
    candidates = []
    for base in (RUNTIME, RUNTIME / "app/com.discordapp.Discord", Path("/tmp")):
        candidates.extend(str(base / f"discord-ipc-{i}") for i in range(10))
    for path in candidates:
        if os.path.exists(path):
            return path
    raise RuntimeError("Discord RPC socket not found; make sure the Discord desktop client is running.")


class Rpc:
    def __init__(self, client_id: str, token: str):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(RPC_TIMEOUT)
        self.sock.connect(find_rpc_socket())
        self.send(0, {"v": 1, "client_id": client_id})
        _, ready = self.receive()
        if ready.get("evt") != "READY":
            raise RuntimeError(ready.get("message", "Discord RPC handshake failed."))
        self.send(1, {"cmd": "AUTHENTICATE", "args": {"access_token": token}, "nonce": secrets.token_hex(12)})
        _, response = self.receive()
        if response.get("evt") == "ERROR" or response.get("cmd") == "ERROR":
            raise RuntimeError(response.get("message", "Discord RPC authentication failed."))

    def send(self, opcode: int, payload: dict) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.sock.sendall(struct.pack("<II", opcode, len(body)) + body)

    def receive(self):
        header = self._recv_exact(8)
        opcode, size = struct.unpack("<II", header)
        return opcode, json.loads(self._recv_exact(size))

    def _recv_exact(self, size: int) -> bytes:
        data = bytearray()
        while len(data) < size:
            block = self.sock.recv(size - len(data))
            if not block:
                raise ConnectionError("Discord closed its RPC connection.")
            data.extend(block)
        return bytes(data)

    def command(self, command: str, args: dict | None = None) -> dict:
        nonce = secrets.token_hex(12)
        self.send(1, {"cmd": command, "args": args or {}, "nonce": nonce})
        while True:
            _, response = self.receive()
            if response.get("nonce") != nonce:
                continue
            if response.get("cmd") == "ERROR" or response.get("evt") == "ERROR":
                raise RuntimeError(response.get("message", f"Discord RPC {command} failed."))
            return response.get("data") or {}

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def authorize() -> None:
    existing = load_config()
    if existing:
        client_id = existing["client_id"]
        client_secret = existing["client_secret"]
    else:
        client_id = input("Discord Application Client ID: ").strip()
        if not client_id.isdecimal():
            raise SystemExit("Client ID must contain digits only.")
        client_secret = getpass.getpass("Discord Application Client Secret: ").strip()
        if not client_secret:
            raise SystemExit("Client Secret cannot be empty.")
    print("Connecting to the running Discord client. Approve the RPC request in Discord when prompted…")
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(180)
    sock.connect(find_rpc_socket())

    def send(opcode, value):
        body = json.dumps(value, separators=(",", ":")).encode()
        sock.sendall(struct.pack("<II", opcode, len(body)) + body)

    def receive():
        header = b""
        while len(header) < 8:
            part = sock.recv(8 - len(header))
            if not part:
                raise ConnectionError("Discord closed its RPC connection.")
            header += part
        opcode, size = struct.unpack("<II", header)
        body = b""
        while len(body) < size:
            body += sock.recv(size - len(body))
        return opcode, json.loads(body)

    try:
        send(0, {"v": 1, "client_id": client_id})
        _, ready = receive()
        if ready.get("evt") != "READY":
            raise RuntimeError(ready.get("message", "Discord RPC handshake failed."))
        nonce = secrets.token_hex(12)
        send(1, {"cmd": "AUTHORIZE", "args": {"client_id": client_id, "scopes": ["rpc", "rpc.video.write", "rpc.screenshare.write"]}, "nonce": nonce})
        deadline = time.monotonic() + 180
        code = None
        while time.monotonic() < deadline:
            _, response = receive()
            if response.get("nonce") != nonce:
                continue
            if response.get("cmd") == "ERROR" or response.get("evt") == "ERROR":
                raise RuntimeError(response.get("message", "Discord RPC authorization failed."))
            code = (response.get("data") or {}).get("code")
            break
        if not code:
            raise TimeoutError("Timed out waiting for Discord authorization.")
    finally:
        sock.close()

    tokens = post_form("https://discord.com/api/v10/oauth2/token", {
        "client_id": client_id,
        "client_secret": client_secret,
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": REDIRECT_URI,
    })
    if not tokens.get("access_token") or not tokens.get("refresh_token"):
        raise RuntimeError("Discord did not return a usable token pair.")
    config = {
        "client_id": client_id,
        "client_secret": client_secret,
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],
        "expires_at": time.time() + int(tokens.get("expires_in", 604800)) - 60,
    }
    write_json(CONFIG, config)
    print(f"Authorization saved privately to {CONFIG} (mode 0600).")


def load_config() -> dict | None:
    try:
        config = json.loads(CONFIG.read_text(encoding="utf-8"))
        if not all(config.get(key) for key in ("client_id", "client_secret", "access_token", "refresh_token")):
            return None
        return config
    except (OSError, ValueError):
        return None


def refresh_token(config: dict) -> dict:
    if time.time() < float(config.get("expires_at", 0)):
        return config
    tokens = post_form("https://discord.com/api/v10/oauth2/token", {
        "client_id": config["client_id"],
        "client_secret": config["client_secret"],
        "grant_type": "refresh_token",
        "refresh_token": config["refresh_token"],
    })
    config.update({
        "access_token": tokens["access_token"],
        "refresh_token": tokens.get("refresh_token", config["refresh_token"]),
        "expires_at": time.time() + int(tokens.get("expires_in", 604800)) - 60,
    })
    write_json(CONFIG, config)
    return config


def snapshot(rpc: Rpc) -> dict:
    channel = rpc.command("GET_SELECTED_VOICE_CHANNEL")
    voice = rpc.command("GET_VOICE_SETTINGS")
    return {
        "configured": True,
        "connected": bool(channel),
        "channel": channel.get("name", "") if channel else "",
        "server": channel.get("guild_name", "") if channel else "",
        "muted": bool(voice.get("mute", False)),
        "deafened": bool(voice.get("deaf", False)),
        "error": "",
    }


def serve_actions(work: queue.Queue) -> socket.socket:
    try:
        ACTION_SOCKET.unlink()
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(ACTION_SOCKET))
    os.chmod(ACTION_SOCKET, 0o600)
    server.listen(4)

    def accept_loop():
        while True:
            try:
                conn, _ = server.accept()
                with conn:
                    request = json.loads(conn.recv(2048).decode("utf-8"))
                    reply = queue.Queue(maxsize=1)
                    work.put((request, reply))
                    try:
                        conn.sendall(json.dumps(reply.get(timeout=8)).encode())
                    except queue.Empty:
                        conn.sendall(b'{"ok":false,"error":"Discord RPC action timed out."}')
            except (OSError, ValueError):
                break

    threading.Thread(target=accept_loop, daemon=True).start()
    return server


def daemon() -> None:
    state = {"configured": False, "connected": False, "channel": "", "server": "", "muted": False, "deafened": False, "error": ""}
    write_json(STATUS, state)
    pending: queue.Queue = queue.Queue()
    server = None
    rpc = None
    try:
        server = serve_actions(pending)
        while True:
            config = load_config()
            if not config:
                state["configured"] = False
                state["error"] = ""
                write_json(STATUS, state)
                time.sleep(3)
                continue
            state["configured"] = True
            try:
                config = refresh_token(config)
                if rpc is None:
                    rpc = Rpc(config["client_id"], config["access_token"])
                state = snapshot(rpc)
                write_json(STATUS, state)
                try:
                    request, reply = pending.get(timeout=1.2)
                except queue.Empty:
                    continue
                action = request.get("action")
                try:
                    if action == "mute":
                        rpc.command("SET_VOICE_SETTINGS", {"mute": not state["muted"]})
                    elif action == "deafen":
                        rpc.command("SET_VOICE_SETTINGS", {"deaf": not state["deafened"]})
                    elif action == "disconnect":
                        rpc.command("SELECT_VOICE_CHANNEL", {"channel_id": None})
                    elif action == "camera":
                        rpc.command("TOGGLE_VIDEO")
                    elif action == "screenshare":
                        rpc.command("TOGGLE_SCREENSHARE")
                    else:
                        raise RuntimeError("Unknown action.")
                    state = snapshot(rpc)
                    write_json(STATUS, state)
                    reply.put({"ok": True})
                except Exception as exc:
                    reply.put({"ok": False, "error": str(exc)[:300]})
            except Exception as exc:
                if rpc:
                    rpc.close()
                    rpc = None
                state.update({"configured": True, "connected": False, "channel": "", "server": "", "error": str(exc)[:300]})
                write_json(STATUS, state)
                time.sleep(2)
    finally:
        if rpc:
            rpc.close()
        if server:
            server.close()
        try:
            ACTION_SOCKET.unlink()
        except FileNotFoundError:
            pass


def status() -> None:
    try:
        value = json.loads(STATUS.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        value = {"configured": bool(load_config()), "connected": False, "channel": "", "server": "", "muted": False, "deafened": False, "error": ""}
    print(json.dumps(value, ensure_ascii=False))


def action(name: str) -> None:
    if not ACTION_SOCKET.exists():
        raise RuntimeError("Discord RPC bridge is not running yet.")
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(9)
    client.connect(str(ACTION_SOCKET))
    client.sendall(json.dumps({"action": name}).encode())
    answer = json.loads(client.recv(2048).decode())
    client.close()
    if not answer.get("ok"):
        raise RuntimeError(answer.get("error", "Discord action failed."))


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "authorize":
        authorize()
    elif command == "daemon":
        daemon()
    elif command == "status":
        status()
    elif command == "action" and len(sys.argv) == 3:
        action(sys.argv[2])
    else:
        raise SystemExit("Usage: discord_rpc.py authorize|daemon|status|action mute|deafen|disconnect")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, TimeoutError) as exc:
        if len(sys.argv) > 1 and sys.argv[1] == "status":
            print(json.dumps({"configured": bool(load_config()), "connected": False, "channel": "", "server": "", "muted": False, "deafened": False, "error": str(exc)[:300]}))
        else:
            print(f"Discord RPC: {exc}", file=sys.stderr)
            raise SystemExit(1)
