# astraOS as a guest on another system's kernel

astraOS normally boots as the phone's own system. It can also run as a **guest** on a
rooted phone that keeps another system installed, like [OneOS](https://github.com/tsryzenstech/OneOS)
does with a second Android (device repository: `astra_device_samsung_e3q`). The guest has
its own mount namespace, but shares the host's processes, devices, kernel parameters,
hostname and watchdog. Starting astraOS's init there is therefore not the same as booting it.

`ASTRA_GUEST=1` in the environment of `init second_stage` makes init a guest. In this mode it:

| does | does not |
|---|---|
| become the subreaper of its services (`PR_SET_CHILD_SUBREAPER`: it can not be PID 1 on a kernel without PID namespaces) | mount pseudo filesystems or create block-device links, or bring up `lo` |
| run the rc files, services and triggers as usual | write under `/proc/sys` or `/sys/`, load modules (`insmod`), mount the fstab (`mount_all`), set the hostname |
| stop its services and **exit** on `reboot`/`poweroff` (exit status 10 for a reboot request, 0 for poweroff) | call `reboot(2)`, unmount `/data`, open or pet the hardware watchdog |
| | run `udevadm`, `modprobe`, `disptest`, `insmod`, `mount`, `umount`, `reboot` through `exec` |

What it does not do is the launcher's work: a private mount namespace, a private `/dev`
(a tmpfs with the device nodes the guest needs, so that `chown`/`chmod` in rc files do not
touch the host's), the rootfs, and the bridges to the host's drivers. The test of the guest
mode is `tests/manual/guest-init.sh` (as root; it needs no phone).
