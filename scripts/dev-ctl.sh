#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Drives a SysBoard started by scripts/dev-run.sh.
#   scripts/dev-ctl.sh screenshot /tmp/home.png
#   scripts/dev-ctl.sh tap 200 400
#   scripts/dev-ctl.sh press 200 400 800          (long press, ms)
#   scripts/dev-ctl.sh swipe 200 840 200 300 250  (x1 y1 x2 y2 ms)
#   scripts/dev-ctl.sh swipehold 196 845 196 600 250 1200  (then hold, ms)
#   scripts/dev-ctl.sh key power
set -euo pipefail
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=${ASTRA_ROOT:-$SRC/out/root}
exec python3 - "$ROOT/run/astra/sysboard-dev.sock" "$*" <<'PY'
import socket, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sys.argv[1])
s.sendall((sys.argv[2] + "\n").encode())
print(s.makefile().readline().strip())
PY
