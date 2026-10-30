/*
 * astraOS init - rescue mode
 *
 * When the first stage cannot boot the system it must not bounce the phone
 * back to the bootloader (that hides the reason). Instead it:
 *   - prints the error and the end of the kernel log on the screen (tty0),
 *   - stores the error in pstore (/sys/fs/pstore after the next boot),
 *   - exposes a serial console over USB (CDC ACM gadget) with a busybox
 *     shell when the ramdisk carries one: on a computer open the new serial
 *     port (/dev/ttyACM0, COMx on Windows) at any speed.
 * Holding power for ~10 s still turns the phone off; "reboot" in the shell
 * restarts it.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include "rescue.h"
#include "util.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/klog.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#define GADGET "/sys/kernel/config/usb_gadget/rescue"
#define BUSYBOX "/bin/busybox"

static void tty_print(const char *text)
{
    int fd = open("/dev/tty0", O_WRONLY | O_NOCTTY | O_CLOEXEC);
    if (fd < 0)
        fd = open("/dev/console", O_WRONLY | O_NOCTTY | O_CLOEXEC);
    if (fd < 0)
        return;
    (void)!write(fd, text, strlen(text));
    close(fd);
}

/* Last lines of the kernel log, so a photo of the screen tells the story. */
static void print_kernel_tail(int lines)
{
    int size = klogctl(10 /* SYSLOG_ACTION_SIZE_BUFFER */, NULL, 0);
    if (size <= 0)
        return;
    char *buf = malloc((size_t)size + 1);
    if (!buf)
        return;
    int n = klogctl(3 /* SYSLOG_ACTION_READ_ALL */, buf, size);
    if (n > 0) {
        buf[n] = '\0';
        char *start = buf + n;
        for (int seen = 0; start > buf && seen <= lines; start--)
            if (start[-1] == '\n')
                seen++;
        tty_print("\n---- kernel log (end) ----\n");
        tty_print(start);
    }
    free(buf);
}

/* Kernels with the USB gadget stack as modules (postmarketOS's): the
 * ramdisk carries them in /lib/modules, loaded in the order of gadget.order. */
static void load_gadget_modules(void)
{
    char *order = read_file("/lib/modules/gadget.order", NULL);
    for (char *line = order ? strtok(order, "\n") : NULL; line; line = strtok(NULL, "\n")) {
        char path[256];
        snprintf(path, sizeof(path), "/lib/modules/%s", line);
        int fd = open(path, O_RDONLY | O_CLOEXEC);
        if (fd < 0)
            continue;
        /* MODULE_INIT_COMPRESSED_FILE: the kernel decompresses .ko.zst itself. */
        if (syscall(SYS_finit_module, fd, "", 4) < 0 && errno != EEXIST &&
            syscall(SYS_finit_module, fd, "", 0) < 0 && errno != EEXIST)
            WARN("rescue: cannot load %s: %s", line, strerror(errno));
        close(fd);
    }
    free(order);
}

/* What tells why a boot fails, collected into a small FAT image that the
 * phone shows to the computer as a USB drive named ASTRALOGS: this boot's
 * kernel log (display and USB probing included), the previous boot's log
 * kept in RAM by ramoops, and the state of displays, drivers and devices. */
static const char COLLECT_LOGS[] =
    "sleep 12\n"
    "L=/logs; mkdir -p $L\n"
    "dmesg > $L/dmesg.txt\n"
    "for f in /sys/fs/pstore/*; do [ -f \"$f\" ] && cat \"$f\" > \"$L/previous-boot-${f##*/}.txt\"; done\n"
    "mkdir -p /sys/kernel/debug; mount -t debugfs none /sys/kernel/debug 2>/dev/null\n"
    "{ echo \"== reason\"; echo \"$ASTRA_RESCUE_REASON\"; echo \"== kernel\"; uname -a; cat /proc/cmdline\n"
    "  echo \"== partitions\"; cat /proc/partitions\n"
    "  echo \"== drm\"; ls -l /dev/dri /sys/class/drm /dev/fb* 2>&1\n"
    "  for s in /sys/class/drm/*/status; do echo \"$s: $(cat $s)\"; done\n"
    "  echo \"== devices waiting for a driver\"; cat /sys/kernel/debug/devices_deferred 2>&1\n"
    "  echo \"== usb\"; ls /sys/class/udc /sys/class/typec 2>&1\n"
    "  echo \"== modules\"; cat /proc/modules\n"
    "} > $L/info.txt 2>&1\n"
    "dd if=/dev/zero of=/logs.img bs=1M count=32 2>/dev/null\n"
    "mkfs.vfat -n ASTRALOGS /logs.img >/dev/null\n"
    "mkdir -p /mnt/logs && mount -t vfat -o loop /logs.img /mnt/logs && cp $L/* /mnt/logs/ && sync && umount /mnt/logs\n";

static void collect_logs(void)
{
    pid_t pid = fork();
    if (pid == 0) {
        setenv("PATH", "/bin", 1);
        execl(BUSYBOX, "sh", "-c", COLLECT_LOGS, (char *)NULL);
        _exit(127);
    }
    if (pid > 0)
        waitpid(pid, NULL, 0);
}

static int usb_serial_gadget(void)
{
    load_gadget_modules();
    mkdir("/sys/kernel/config", 0755);
    if (access("/sys/kernel/config/usb_gadget", F_OK) < 0 &&
        mount("configfs", "/sys/kernel/config", "configfs", 0, NULL) < 0 && errno != EBUSY)
        return -1;
    if (mkdir_p(GADGET "/strings/0x409", 0755) < 0 || mkdir_p(GADGET "/configs/c.1/strings/0x409", 0755) < 0 ||
        mkdir_p(GADGET "/functions/acm.GS0", 0755) < 0)
        return -1;
    write_file(GADGET "/idVendor", "0x1d6b");
    write_file(GADGET "/idProduct", "0x0104");
    write_file(GADGET "/strings/0x409/manufacturer", "astraOS");
    write_file(GADGET "/strings/0x409/product", "astraOS rescue");
    write_file(GADGET "/strings/0x409/serialnumber", "rescue");
    write_file(GADGET "/configs/c.1/strings/0x409/configuration", "rescue serial");
    write_file(GADGET "/configs/c.1/MaxPower", "500");
    symlink(GADGET "/functions/acm.GS0", GADGET "/configs/c.1/acm.GS0");
    /* The logs, as a read-only USB drive. */
    if (access("/logs.img", F_OK) == 0 && mkdir_p(GADGET "/functions/mass_storage.logs", 0755) == 0) {
        write_file(GADGET "/functions/mass_storage.logs/lun.0/removable", "1");
        write_file(GADGET "/functions/mass_storage.logs/lun.0/ro", "1");
        write_file(GADGET "/functions/mass_storage.logs/lun.0/file", "/logs.img");
        symlink(GADGET "/functions/mass_storage.logs", GADGET "/configs/c.1/mass_storage.logs");
    }

    /* The USB controller can take a moment to probe. */
    for (int i = 0; i < 100; i++) {
        DIR *d = opendir("/sys/class/udc");
        if (d) {
            struct dirent *de;
            while ((de = readdir(d)))
                if (de->d_name[0] != '.') {
                    int ok = write_file(GADGET "/UDC", de->d_name);
                    closedir(d);
                    return ok;
                }
            closedir(d);
        }
        usleep(100 * 1000);
    }
    return -1;
}

static void shell_on(const char *tty)
{
    pid_t pid = fork();
    if (pid != 0)
        return;
    setsid();
    int fd = open(tty, O_RDWR | O_NOCTTY);
    if (fd < 0)
        _exit(1);
    ioctl(fd, TIOCSCTTY, 1);
    struct termios t;
    if (tcgetattr(fd, &t) == 0) {
        cfmakeraw(&t);
        t.c_lflag |= ICANON | ECHO | ECHOE | ISIG;
        t.c_iflag |= ICRNL;
        t.c_oflag |= OPOST | ONLCR;
        tcsetattr(fd, TCSANOW, &t);
    }
    dup2(fd, 0);
    dup2(fd, 1);
    dup2(fd, 2);
    if (fd > 2)
        close(fd);
    setenv("PATH", "/bin:/sbin:/system/bin", 1);
    setenv("PS1", "astra-rescue# ", 1);
    printf("\r\nastraOS rescue shell. The boot stopped because of:\r\n  %s\r\n"
           "Useful: dmesg | tail -50, ls /dev/block, cat /proc/partitions, reboot\r\n\r\n",
           getenv("ASTRA_RESCUE_REASON") ? getenv("ASTRA_RESCUE_REASON") : "?");
    fflush(stdout);
    execl(BUSYBOX, "sh", "-i", (char *)NULL);
    _exit(127);
}

void rescue(const char *why)
{
    ERR("RESCUE: %s", why);
    setenv("ASTRA_RESCUE_REASON", why, 1);

    /* Keep the reason across a reboot (pstore pmsg, when the kernel has it). */
    char line[512];
    snprintf(line, sizeof(line), "astraOS first stage failed: %s\n", why);
    write_file("/dev/pmsg0", line);

    int have_shell = access(BUSYBOX, X_OK) == 0;
    if (have_shell) {
        mkdir("/bin", 0755);
        /* Let busybox install its applets (sh, ls, dmesg, mount, reboot...). */
        pid_t pid = fork();
        if (pid == 0) {
            execl(BUSYBOX, "busybox", "--install", "-s", "/bin", (char *)NULL);
            _exit(1);
        }
        if (pid > 0)
            waitpid(pid, NULL, 0);
    }
    /* The previous boot's kernel log (ramoops), read with cat in /sys/fs/pstore. */
    mkdir("/sys/fs/pstore", 0755);
    mount("pstore", "/sys/fs/pstore", "pstore", 0, NULL);
    if (have_shell)
        collect_logs();
    int usb = usb_serial_gadget();

    char banner[1024];
    snprintf(banner, sizeof(banner),
             "\033[2J\033[H\n"
             "  astraOS could not start\n"
             "  ------------------------\n"
             "  %s\n\n"
             "  %s\n"
             "  Hold the power button for 10 seconds to turn the phone off,\n"
             "  or connect it to a computer and run: fastboot reboot bootloader\n",
             why,
             usb == 0 && have_shell ? "Logs: USB drive ASTRALOGS. Shell: USB serial (ttyACM / COM port)."
                                    : "No USB rescue shell is available on this build.");
    tty_print(banner);
    print_kernel_tail(40);

    /* Serve the shell for as long as the phone stays on. */
    signal(SIGCHLD, SIG_DFL);
    for (;;) {
        if (usb == 0 && have_shell && access("/dev/ttyGS0", F_OK) == 0)
            shell_on("/dev/ttyGS0");
        else
            sleep(5);
        int status;
        while (waitpid(-1, &status, 0) > 0)
            ;
        sleep(1);
    }
}
