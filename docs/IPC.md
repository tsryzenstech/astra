# IPC protocol and system services

astrad listens on the Unix stream socket `/dev/socket/astrad`. Messages are
compact JSON objects, one per line.

```
→ {"id": 7, "method": "notifications.post", "params": {"title": "Hi"}}
← {"id": 7, "result": 12}
← {"id": 8, "error": {"code": -32001, "message": "... requires astra.permission.MANAGE_LOCK"}}
← {"event": "notifications.posted", "data": {...}}
```

Requests with `"id": 0` get no reply. Clients receive events of the topics
they subscribed to (`system.subscribe {"topics": [...]}`); a few events are
addressed to one package only (`activity.intent`, `media.command`).
`libastra`'s `astra::Client` implements the protocol, reconnects and
re-subscribes transparently when astrad restarts.

The caller is identified with `SO_PEERCRED`: its pid (for processes started
by the activity manager) or uid maps to a package. Processes that are not
apps (SysBoard, daemons) are *system* callers.

## Services

| Method | Caller | Description |
|---|---|---|
| `system.ping`, `system.info` | any | liveness, OS/device information |
| `system.bootCompleted` | system | SysBoard is up (posts the first-boot Tips notification) |
| `system.power {action}` | POWER | `reboot`, `poweroff`, `bootloader`, `recovery`, `restart-sysboard` (through init) |
| `packages.list`, `packages.get {package}`, `packages.widgets` | any | installed packages |
| `packages.install {path}`, `packages.uninstall {package}` | MANAGE_PACKAGES | system packages ("installed by root") cannot be removed |
| `activity.start {package, args}` | system, own package, MANAGE_PACKAGES | launch or deliver an intent |
| `activity.stop`, `activity.running`, `activity.registerDisplay` | system / own | |
| `notifications.post {title, body, package?}` | any (package: MANAGE_NOTIFICATIONS) | |
| `notifications.list`, `notifications.dismiss {id}` | own / MANAGE_NOTIFICATIONS | |
| `notifications.clear` | MANAGE_NOTIFICATIONS | |
| `settings.get`, `settings.getAll {prefix}` | any (`secure.*`: system) | |
| `settings.set`, `settings.reset` | MANAGE_SETTINGS | |
| `lock.state` | any | has a PIN, PIN length |
| `lock.verify {pin}` | system | throttled after 5 failures |
| `lock.setPin {current, pin}` | MANAGE_LOCK | PBKDF2-SHA256, salted |
| `media.publish {...}`, `media.release` | apps | the caller's media session |
| `media.current`, `media.command {action, position}` | MEDIA_CONTROL | |
| `hardware.state`, `hardware.battery` | any | |
| `hardware.setBrightness`, `setTorch`, `setRadio`, `setScreen` | HARDWARE | |
| `weather.current`, `weather.refresh` | any | Open-Meteo, configured city |
| `account.request {method, path, body}` | apps with INTERNET | the app's own API on the AstraID server (`/api/app/<package>/…`) with the phone's token; resolves `{status, body}` |
| `account.state`, `account.signIn`, … | MANAGE_SETTINGS | AstraID session (Settings) |

## Topics

| Topic | Events | Subscribers |
|---|---|---|
| `packages` | `changed`, `removed` | any |
| `settings` | `changed` | any (`secure.*` keys: system) |
| `hardware` | `battery`, `changed` | any |
| `weather` | `changed` | any |
| `system` | `bootCompleted` | any |
| `notifications` | `posted`, `removed`, `cleared` | MANAGE_NOTIFICATIONS |
| `media` | `changed` | MEDIA_CONTROL |
| `activity`, `lock`, `display` | | system |

## Permissions

| Permission | Granted to |
|---|---|
| `astra.permission.INTERNET` | any app that requests it (adds the `inet` group) |
| `astra.permission.MANAGE_SETTINGS` | privileged apps |
| `astra.permission.MANAGE_LOCK` | privileged apps |
| `astra.permission.MANAGE_PACKAGES` | privileged apps |
| `astra.permission.MANAGE_NOTIFICATIONS` | privileged apps |
| `astra.permission.MEDIA_CONTROL` | privileged apps |
| `astra.permission.HARDWARE` | privileged apps |
| `astra.permission.POWER` | privileged apps |

Privileged apps are the ones installed in `/system/priv-app`.
