#!/usr/bin/env python3
"""End-to-end check of the web terminal, with the Python standard library only (the CI runner has Python).

Speaks ttyd's WebSocket protocol: log in, run a command in a shell, and check that
  - a second connection with ?arg=<name> gets an independent shell (exercises with server and client need two),
  - reconnecting without an argument attaches to the same shell again (closing the tab must not end the session).

Environment: TTY_USER, TTY_PASSWORD (required), HOST (default ::1), PORT (default 8080).
"""

import base64
import json
import os
import re
import socket
import struct
import sys
import time

HOST = os.environ.get("HOST", "::1")
PORT = int(os.environ.get("PORT", "8080"))
USER = os.environ["TTY_USER"]
PASSWORD = os.environ["TTY_PASSWORD"]
TIMEOUT = 30.0

CRED = base64.b64encode(f"{USER}:{PASSWORD}".encode()).decode()


class Session:
    def __init__(self, query=""):
        self.sock = socket.create_connection((HOST, PORT), timeout=TIMEOUT)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            f"GET /ws{query} HTTP/1.1\r\n"
            f"Host: [{HOST}]:{PORT}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "Sec-WebSocket-Protocol: tty\r\n"
            f"Authorization: Basic {CRED}\r\n\r\n"
        )
        self.sock.sendall(request.encode())
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("connection closed during the WebSocket handshake")
            head += chunk
        header, _, self.buf = head.partition(b"\r\n\r\n")
        status = header.split(b"\r\n")[0]
        if b" 101 " not in status:
            raise RuntimeError(f"WebSocket handshake refused: {status.decode(errors='replace')}")
        self.output = ""
        # ttyd's first message: the token (the base64 of the credential) and the terminal size.
        self._send(json.dumps({"AuthToken": CRED, "columns": 120, "rows": 30}).encode())

    def _send(self, payload, opcode=2):
        mask = os.urandom(4)
        length = len(payload)
        if length < 126:
            header = bytes([0x80 | opcode, 0x80 | length])
        elif length < 65536:
            header = bytes([0x80 | opcode, 0x80 | 126]) + struct.pack(">H", length)
        else:
            header = bytes([0x80 | opcode, 0x80 | 127]) + struct.pack(">Q", length)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise RuntimeError("connection closed by the terminal")
            self.buf += chunk
        data, self.buf = self.buf[:n], self.buf[n:]
        return data

    def _frame(self):
        b0, b1 = self._read(2)
        opcode, length = b0 & 0x0F, b1 & 0x7F
        if length == 126:
            length = struct.unpack(">H", self._read(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", self._read(8))[0]
        if b1 & 0x80:
            mask = self._read(4)
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(self._read(length)))
        else:
            payload = self._read(length)
        return opcode, payload

    def run(self, command):
        # ttyd: input is the command byte "0" followed by the data.
        self._send(b"0" + command.encode() + b"\n")

    def expect(self, pattern):
        """Wait until the terminal output matches pattern, and return the first group."""
        deadline = time.monotonic() + TIMEOUT
        while time.monotonic() < deadline:
            match = re.search(pattern, self.output)
            if match:
                return match.group(1)
            opcode, payload = self._frame()
            if opcode == 8:
                raise RuntimeError("the terminal closed the connection")
            if opcode == 9:
                self._send(payload, opcode=10)
            elif opcode in (1, 2) and payload[:1] == b"0":
                # ttyd: output is the command byte "0" followed by the terminal data.
                self.output += payload[1:].decode(errors="replace")
        raise RuntimeError(f"no output matching {pattern!r}; got: {self.output[-500:]!r}")

    def pid(self):
        # The typed command shows "$$" literally; only the shell's answer has digits.
        self.run("echo SESSION-$$-END")
        return int(self.expect(r"SESSION-(\d+)-END"))

    def close(self):
        try:
            self._send(b"", opcode=8)
        except OSError:
            pass
        self.sock.close()


def main():
    first = Session()
    pid_first = first.pid()
    print(f"first terminal: shell {pid_first}")

    # The password is the login; the shells must not inherit it (`env` on a projector would show it).
    first.run("echo PW-[${PASSWORD:-unset}]-X")
    if first.expect(r"PW-\[([A-Za-z0-9_-]+)\]-X") != "unset":
        sys.exit("FAIL: the shell inherited PASSWORD")

    second = Session("?arg=second")
    pid_second = second.pid()
    print(f"second terminal (?arg=second): shell {pid_second}")
    if pid_second == pid_first:
        sys.exit("FAIL: ?arg=second did not open an independent shell")

    first.close()
    second.close()
    time.sleep(1)

    again = Session()
    pid_again = again.pid()
    print(f"reconnected terminal: shell {pid_again}")
    again.close()
    if pid_again != pid_first:
        sys.exit("FAIL: reconnecting did not attach to the same shell (closing the tab ended the session)")
    print("terminal OK")


if __name__ == "__main__":
    main()
