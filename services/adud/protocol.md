# ADU protocol (version 1)

TCP, port 5560. Over USB the phone exposes a network interface (RNDIS/NCM)
with address `10.42.0.1` and hands the computer an address with DHCP.

Every message is a frame:

```
u32 length (big endian, counts type + payload)
u8  type     1 = JSON control, 2 = data (stdout / file bytes), 3 = stderr, 4 = end of stream
...payload
```

## Authentication

```
→ {"cmd":"hello", "proto":1, "name":"<computer name>", "id":"<key fingerprint>"}
← {"challenge":"<hex nonce>", "known":true|false}
→ {"cmd":"auth", "mac":"<hex HMAC-SHA256(secret, nonce)>"}          (known computers)
→ {"cmd":"pair", "secret":"<hex 32 bytes>"}                        (first connection)
← {"ok":true, "device":{...}}   or   {"ok":false, "error":"..."}
```

The key fingerprint is the first 32 hex digits of SHA-256(secret). Pairing
shows an authorization dialog on the phone; once allowed, the secret is
stored in `/data/misc/adu/keys.json` and later connections only prove they
know it. Settings › Developer options › Revoke authorizations clears it.

## Commands (one per connection, after authentication)

| Request | Behaviour |
|---|---|
| `{"cmd":"info"}` | `{device info}` |
| `{"cmd":"shell", "command":"…"?, "cols":80, "rows":24, "tty":true}` | interactive PTY (no command) or one command; stdin as type 2 frames, output as type 2, exit as `{"exit":code}`. `"tty":false` turns off echo and CRLF translation, for pipes and scripts |
| `{"cmd":"push", "path":"…", "mode":420}` | then data frames and an end frame; `{"ok":true}` |
| `{"cmd":"pull", "path":"…"}` | `{"size":n}`, data frames, end frame |
| `{"cmd":"install", "path":"…"}` | installs an `.apkg` already pushed to the phone |
| `{"cmd":"uninstall", "package":"…"}`, `{"cmd":"packages"}` | |
| `{"cmd":"start", "package":"…"}` | launches an app |
| `{"cmd":"logcat"}` | streams kernel and service logs |

Paths are device paths; relative paths start in `/data/local/tmp`.
| `{"cmd":"screenshot"}` | `{"size":n}` and a PNG as data frames |
| `{"cmd":"reboot", "target":"bootloader"\|"recovery"\|""}` | |
