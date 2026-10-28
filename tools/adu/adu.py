#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""adu - Astra Debugging Utility.

Manage an astraOS device from a computer over USB (or Wi-Fi):

  adu info                         device information
  adu shell [command...]           interactive shell, or run one command
  adu push <local> <remote>        copy a file to the device
  adu pull <remote> [local]        copy a file from the device
  adu install <app.apkg>           install an app
  adu uninstall <package>          remove an app
  adu packages                     list installed apps
  adu start <package>              launch an app
  adu logcat                       follow the kernel and system log
  adu screenshot [file.png]        capture the screen
  adu reboot [bootloader|recovery]

Enable "USB debugging" in Settings > Developer options first. The first
connection from a computer must be allowed on the phone.

Options: -s/--host <address> (default: 10.42.0.1, then 10.42.1.1; or $ADU_HOST)
         -p/--port <port> (default 5560)
"""
import argparse
import hashlib
import hmac
import json
import os
import platform
import secrets
import socket
import struct
import sys
import threading

PORT = 5560
DEFAULT_HOSTS = ["10.42.0.1", "10.42.1.1"]
CONTROL, DATA, STDERR, END = 1, 2, 3, 4


class AduError(Exception):
    pass


def key_dir():
    base = os.environ.get("APPDATA") if os.name == "nt" else os.path.expanduser("~")
    return os.path.join(base, "adu" if os.name == "nt" else ".adu")


def load_secret():
    path = os.path.join(key_dir(), "key")
    if not os.path.exists(path):
        os.makedirs(key_dir(), exist_ok=True)
        with open(path, "w") as f:
            f.write(secrets.token_hex(32))
        try:
            os.chmod(path, 0o600)
        except OSError:
            pass
    with open(path) as f:
        return bytes.fromhex(f.read().strip())


class Connection:
    def __init__(self, host, port):
        self.sock = socket.create_connection((host, port), timeout=10)
        self.sock.settimeout(None)
        self.buffer = b""

    def send(self, ftype, payload=b""):
        self.sock.sendall(struct.pack(">IB", len(payload) + 1, ftype) + payload)

    def send_json(self, obj):
        self.send(CONTROL, json.dumps(obj).encode())

    def recv(self):
        while len(self.buffer) < 5:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise AduError("connection closed by the device")
            self.buffer += chunk
        length, ftype = struct.unpack(">IB", self.buffer[:5])
        while len(self.buffer) < 4 + length:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise AduError("connection closed by the device")
            self.buffer += chunk
        payload = self.buffer[5:4 + length]
        self.buffer = self.buffer[4 + length:]
        return ftype, payload

    def recv_json(self):
        while True:
            ftype, payload = self.recv()
            if ftype == CONTROL:
                return json.loads(payload)

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def connect(args):
    hosts = [args.host] if args.host else ([os.environ["ADU_HOST"]] if os.environ.get("ADU_HOST") else DEFAULT_HOSTS)
    last = None
    for host in hosts:
        try:
            conn = Connection(host, args.port)
            break
        except OSError as e:
            last = e
    else:
        raise AduError(f"cannot reach the device ({last}). Is USB debugging on and the cable connected?")

    secret = load_secret()
    fingerprint = hashlib.sha256(secret).hexdigest()[:32]
    conn.send_json({"cmd": "hello", "proto": 1, "name": platform.node() or "computer", "id": fingerprint})
    hello = conn.recv_json()
    if hello.get("known"):
        mac = hmac.new(secret, bytes.fromhex(hello["challenge"]), hashlib.sha256).hexdigest()
        conn.send_json({"cmd": "auth", "mac": mac})
    else:
        conn.send_json({"cmd": "pair", "secret": secret.hex()})
    while True:
        reply = conn.recv_json()
        if "waiting" in reply:
            print("adu: allow USB debugging on the phone...", file=sys.stderr)
            continue
        if not reply.get("ok"):
            raise AduError(reply.get("error", "unauthorized"))
        return conn


def request(args, msg):
    conn = connect(args)
    conn.send_json(msg)
    reply = conn.recv_json()
    conn.close()
    if not reply.get("ok"):
        raise AduError(reply.get("error", "failed"))
    return reply.get("result")


def receive_file(conn, target):
    header = conn.recv_json()
    if "size" not in header:
        raise AduError(header.get("error", "transfer failed"))
    got = 0
    with open(target, "wb") as f:
        while True:
            ftype, payload = conn.recv()
            if ftype == END:
                break
            f.write(payload)
            got += len(payload)
    return got


# ---- commands ------------------------------------------------------------------

def cmd_info(args):
    info = request(args, {"cmd": "info"})
    for key in ("name", "version", "codename", "channel", "buildId", "model", "device", "cpu", "kernel", "architecture"):
        if key in info:
            print(f"{key:>13}: {info[key]}")


def cmd_packages(args):
    for p in sorted(request(args, {"cmd": "packages"}), key=lambda p: p["package"]):
        flag = "system" if p.get("system") else "user"
        print(f"{p['package']:<36} {p.get('version', ''):<10} {flag}")


def cmd_push(args, local=None, remote=None):
    local = local or args.local
    remote = remote or args.remote
    if remote.endswith("/"):
        remote += os.path.basename(local)
    conn = connect(args)
    conn.send_json({"cmd": "push", "path": remote, "mode": 0o644})
    ready = conn.recv_json()
    if not ready.get("ready"):
        raise AduError(ready.get("error", "push refused"))
    size = os.path.getsize(local)
    with open(local, "rb") as f:
        while chunk := f.read(256 * 1024):
            conn.send(DATA, chunk)
    conn.send(END)
    reply = conn.recv_json()
    conn.close()
    if not reply.get("ok"):
        raise AduError(reply.get("error", "push failed"))
    print(f"{local}: {size} bytes pushed to {remote}", file=sys.stderr)


def cmd_pull(args):
    target = args.local or os.path.basename(args.remote.rstrip("/"))
    conn = connect(args)
    conn.send_json({"cmd": "pull", "path": args.remote})
    size = receive_file(conn, target)
    conn.close()
    print(f"{args.remote}: {size} bytes pulled to {target}", file=sys.stderr)


def cmd_install(args):
    remote = "/data/local/tmp/" + os.path.basename(args.apkg)
    cmd_push(args, args.apkg, remote)
    request(args, {"cmd": "install", "path": remote})
    print("Success")


def cmd_uninstall(args):
    request(args, {"cmd": "uninstall", "package": args.package})
    print("Success")


def cmd_start(args):
    request(args, {"cmd": "start", "package": args.package})


def cmd_reboot(args):
    request(args, {"cmd": "reboot", "target": args.target or ""})


def cmd_screenshot(args):
    target = args.file or "screenshot.png"
    conn = connect(args)
    conn.send_json({"cmd": "screenshot"})
    size = receive_file(conn, target)
    conn.close()
    print(f"saved {target} ({size} bytes)", file=sys.stderr)


def cmd_logcat(args):
    conn = connect(args)
    conn.send_json({"cmd": "logcat"})
    reply = conn.recv_json()
    if not reply.get("ok"):
        raise AduError(reply.get("error", "logcat failed"))
    try:
        while True:
            ftype, payload = conn.recv()
            if ftype == DATA:
                sys.stdout.write(payload.decode(errors="replace"))
                sys.stdout.flush()
    except KeyboardInterrupt:
        pass
    finally:
        conn.close()


def cmd_shell(args):
    command = " ".join(args.command)
    interactive = not command and sys.stdin.isatty()
    cols, rows = os.get_terminal_size() if sys.stdout.isatty() else (80, 24)
    conn = connect(args)
    msg = {"cmd": "shell", "cols": cols, "rows": rows,
           "tty": interactive or (bool(command) and sys.stdout.isatty())}
    if command:
        msg["command"] = command
    conn.send_json(msg)
    reply = conn.recv_json()
    if not reply.get("ok"):
        raise AduError(reply.get("error", "shell failed"))

    exit_code = [0]
    done = threading.Event()

    def reader():
        out = sys.stdout.buffer
        try:
            while True:
                ftype, payload = conn.recv()
                if ftype in (DATA, STDERR):
                    out.write(payload)
                    out.flush()
                elif ftype == CONTROL:
                    msg = json.loads(payload)
                    if "exit" in msg:
                        exit_code[0] = msg["exit"]
                        break
        except (AduError, OSError):
            pass
        done.set()

    threading.Thread(target=reader, daemon=True).start()
    if interactive:
        _interactive_input(conn, done)
    elif not command:
        data = sys.stdin.buffer.read()
        conn.send(DATA, data + b"\nexit\n")
    done.wait()
    conn.close()
    sys.exit(exit_code[0])


def _interactive_input(conn, done):
    if os.name == "nt":
        import msvcrt
        keymap = {b"H": b"\x1b[A", b"P": b"\x1b[B", b"M": b"\x1b[C", b"K": b"\x1b[D",
                  b"G": b"\x1b[H", b"O": b"\x1b[F", b"S": b"\x1b[3~"}
        os.system("")  # enable ANSI escape handling in the Windows console
        while not done.is_set():
            if not msvcrt.kbhit():
                done.wait(0.01)
                continue
            ch = msvcrt.getwch()
            if ch in ("\x00", "\xe0"):
                seq = keymap.get(msvcrt.getwch().encode(), b"")
                if seq:
                    conn.send(DATA, seq)
                continue
            conn.send(DATA, ("\r" if ch == "\r" else ch).encode())
        return

    import select
    import termios
    import tty
    fd = sys.stdin.fileno()
    saved = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while not done.is_set():
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                data = os.read(fd, 1024)
                if not data:
                    break
                conn.send(DATA, data)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)


def main(argv=None):
    parser = argparse.ArgumentParser(prog="adu", description="Astra Debugging Utility",
                                     formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__.split("\n\n")[1])
    parser.add_argument("-s", "--host")
    parser.add_argument("-p", "--port", type=int, default=PORT)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("info").set_defaults(func=cmd_info)
    sub.add_parser("packages").set_defaults(func=cmd_packages)
    p = sub.add_parser("shell")
    p.add_argument("command", nargs=argparse.REMAINDER)
    p.set_defaults(func=cmd_shell)
    p = sub.add_parser("push")
    p.add_argument("local")
    p.add_argument("remote")
    p.set_defaults(func=cmd_push)
    p = sub.add_parser("pull")
    p.add_argument("remote")
    p.add_argument("local", nargs="?")
    p.set_defaults(func=cmd_pull)
    p = sub.add_parser("install")
    p.add_argument("apkg")
    p.set_defaults(func=cmd_install)
    p = sub.add_parser("uninstall")
    p.add_argument("package")
    p.set_defaults(func=cmd_uninstall)
    p = sub.add_parser("start")
    p.add_argument("package")
    p.set_defaults(func=cmd_start)
    sub.add_parser("logcat").set_defaults(func=cmd_logcat)
    p = sub.add_parser("screenshot")
    p.add_argument("file", nargs="?")
    p.set_defaults(func=cmd_screenshot)
    p = sub.add_parser("reboot")
    p.add_argument("target", nargs="?", choices=["bootloader", "recovery"])
    p.set_defaults(func=cmd_reboot)

    args = parser.parse_args(argv)
    try:
        args.func(args)
    except AduError as e:
        print(f"adu: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
