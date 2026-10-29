# ADU — Astra Debugging Utility

Manage an astraOS phone from a computer over USB: shell, files, apps, logs
and screenshots. Needs Python 3 only (Windows, macOS, Linux).

1. On the phone: Settings › About › More Settings, tap **Architecture** seven
   times and enter your PIN. Then Settings › Developer Options › **USB debugging**.
2. Connect the USB cable. The phone appears as a USB network adapter
   (RNDIS on Windows/Linux, NCM on macOS) at `10.42.0.1` / `10.42.1.1`.
3. Run a command; the first time, allow the computer on the phone.

```
adu info                      device information
adu shell                     interactive shell (or: adu shell <command>)
adu push <local> <remote>     copy a file to the phone (relative paths: /data/local/tmp)
adu pull <remote> [local]     copy a file from the phone
adu install <app.apkg>        install an app
adu uninstall <package>       remove an app
adu packages                  list installed apps
adu start <package>           launch an app
adu logcat                    follow the kernel log
adu screenshot [file.png]     capture the screen
adu reboot [bootloader|recovery]
```

On Windows use `adu.cmd`. Options: `-s <address>` (or `ADU_HOST`), `-p <port>`
(default 5560). The pairing key lives in `~/.adu/key` (`%APPDATA%\adu\key`).
Revoke computers in Developer Options. Protocol: `services/adud/protocol.md`.
