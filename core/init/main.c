/*
 * astraOS init (PID 1)
 *
 *   first stage  - runs from the boot.img ramdisk: maps the dynamic
 *                  partitions inside "super", mounts system/vendor/product
 *                  and switches root to the system partition.
 *   second stage - runs from /system/bin/init: mounts the remaining
 *                  filesystems, executes the .rc scripts and supervises
 *                  services. Listens on /dev/socket/init for control
 *                  requests (start/stop/restart <service>, reboot, poweroff).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include "fstab.h"
#include "lp.h"
#include "rc.h"
#include "rescue.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/reboot.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/signalfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/un.h>
#include <unistd.h>

#define FIRST_STAGE_FSTAB "/first_stage.fstab"
#define VENDOR_FSTAB "/vendor/etc/fstab"
#define CONTROL_SOCKET "/dev/socket/init"
#define NEW_ROOT "/newroot"

static void mount_pseudo(void)
{
    mkdir("/dev", 0755);
    mkdir("/proc", 0555);
    mkdir("/sys", 0555);
    mount("devtmpfs", "/dev", "devtmpfs", MS_NOSUID, "mode=0755");
    mount("proc", "/proc", "proc", MS_NOSUID | MS_NODEV | MS_NOEXEC, "hidepid=2");
    mount("sysfs", "/sys", "sysfs", MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL);
}

/* Never bounce to the bootloader: that looks like "it does not boot" and
 * hides the reason. Show it on screen and offer a USB rescue shell. */
static void fatal_reboot(const char *why)
{
    sync();
    rescue(why);
}

/* ---- first stage ------------------------------------------------------ */

static int first_stage_main(void)
{
    mount_pseudo();
    klog_init();
    INFO("astraOS init: first stage");
    /* Make our progress visible on the boot console. */
    write_file("/proc/sys/kernel/printk", "7 4 1 7");

    struct fstab *fs = fstab_read(FIRST_STAGE_FSTAB);
    if (!fs)
        fatal_reboot("no first stage fstab");

    char super_dev[64];
    if (find_block_by_partname("super", super_dev, sizeof(super_dev), 20000) < 0)
        fatal_reboot("the \"super\" partition was not found (is the UFS driver built in?)");
    INFO("super is %s", super_dev);
    int mapped = lp_map_super(super_dev);
    if (mapped <= 0)
        fatal_reboot("no logical partition could be mapped from super (flash super.img again)");
    INFO("%d logical partitions mapped", mapped);

    mkdir(NEW_ROOT, 0755);
    /* "/" must be mounted first, every other mount point lives inside it. */
    for (int pass = 0; pass < 2; pass++) {
        for (int i = 0; i < fs->count; i++) {
            struct fstab_entry *e = &fs->entries[i];
            int is_root = !strcmp(e->mount_point, "/");
            if (!e->first_stage || is_root != (pass == 0))
                continue;
            if (fstab_mount(e, NEW_ROOT) < 0 && is_root)
                fatal_reboot("the system partition cannot be mounted");
        }
    }
    fstab_free(fs);
    /* Quiet again for the rest of the boot. */
    write_file("/proc/sys/kernel/printk", "4 4 1 7");

    struct stat st;
    stat("/", &st);
    remove_tree_same_dev("/", st.st_dev);

    const char *moves[] = {"/dev", "/proc", "/sys"};
    for (size_t i = 0; i < 3; i++) {
        char target[64];
        snprintf(target, sizeof(target), NEW_ROOT "%s", moves[i]);
        mkdir(target, 0755);
        if (mount(moves[i], target, NULL, MS_MOVE, NULL) < 0)
            WARN("move %s: %s", moves[i], strerror(errno));
    }
    if (chdir(NEW_ROOT) < 0 || mount(".", "/", NULL, MS_MOVE, NULL) < 0 || chroot(".") < 0 || chdir("/") < 0)
        fatal_reboot("switch root failed");

    execl("/system/bin/init", "init", "second_stage", (char *)NULL);
    fatal_reboot("cannot exec second stage init");
    return 1;
}

/* ---- second stage ----------------------------------------------------- */

static void do_reboot(const char *mode)
{
    INFO("shutting down (%s)", mode);
    rc_trigger("shutdown");
    services_stop_all(3000);
    sync();
    umount2("/data", MNT_DETACH);
    if (!strcmp(mode, "poweroff"))
        reboot(RB_POWER_OFF);
    else if (!strcmp(mode, "reboot"))
        reboot(RB_AUTOBOOT);
    else
        syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2, LINUX_REBOOT_CMD_RESTART2, mode);
}

static int open_control_socket(void)
{
    int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (fd < 0)
        return -1;
    struct sockaddr_un addr = {.sun_family = AF_UNIX};
    snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", CONTROL_SOCKET);
    mkdir_p("/dev/socket", 0755);
    unlink(CONTROL_SOCKET);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd);
        return -1;
    }
    /* root and the system user may control init. */
    chown(CONTROL_SOCKET, 0, 1000);
    chmod(CONTROL_SOCKET, 0660);
    return fd;
}

static void handle_control(int fd)
{
    char buf[256];
    ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
    if (n <= 0)
        return;
    buf[n] = '\0';
    buf[strcspn(buf, "\r\n")] = '\0';

    char *argv[3] = {0};
    int argc = 0;
    for (char *t = strtok(buf, " "); t && argc < 3; t = strtok(NULL, " "))
        argv[argc++] = t;
    if (!argc)
        return;
    INFO("control request: %s %s", argv[0], argc > 1 ? argv[1] : "");

    if (!strcmp(argv[0], "reboot")) {
        do_reboot(argc > 1 ? argv[1] : "reboot");
    } else if (!strcmp(argv[0], "poweroff")) {
        do_reboot("poweroff");
    } else if (argc == 2) {
        struct service *s = service_find(argv[1]);
        if (!s)
            return;
        if (!strcmp(argv[0], "start"))
            service_start(s);
        else if (!strcmp(argv[0], "stop"))
            service_stop(s);
        else if (!strcmp(argv[0], "restart")) {
            service_stop(s);
            s->restart_at_ms = now_ms() + 300;
        }
    }
}

static int second_stage_main(void)
{
    /* Booting without a ramdisk (e.g. testing in a VM) skips the first stage. */
    if (access("/proc/self", F_OK) < 0)
        mount_pseudo();
    klog_init();
    INFO("astraOS init: second stage");
    umask(022);

    mkdir_p("/dev/pts", 0755);
    mkdir_p("/dev/shm", 01777);
    mount("devpts", "/dev/pts", "devpts", MS_NOSUID | MS_NOEXEC, "gid=5,mode=620,ptmxmode=0666");
    mount("tmpfs", "/dev/shm", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
    mount("tmpfs", "/run", "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755");
    mount("tmpfs", "/tmp", "tmpfs", MS_NOSUID | MS_NODEV, "mode=1777");
    create_by_name_links();

    init_setenv("PATH", "/system/bin:/vendor/bin:/product/bin");
    init_setenv("LANG", "en_US.UTF-8");
    init_setenv("TZ", "UTC");

    rc_parse_dir("/system/etc/init");
    rc_parse_dir("/vendor/etc/init");
    rc_parse_dir("/product/etc/init");

    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGCHLD);
    sigaddset(&mask, SIGTERM);
    sigaddset(&mask, SIGINT);
    sigprocmask(SIG_BLOCK, &mask, NULL);
    int sfd = signalfd(-1, &mask, SFD_CLOEXEC | SFD_NONBLOCK);
    int cfd = open_control_socket();

    rc_trigger("early-init");
    rc_trigger("init");
    rc_trigger("fs");
    rc_trigger("post-fs-data");
    rc_trigger("boot");

    for (;;) {
        struct pollfd pfd[2] = {{.fd = sfd, .events = POLLIN}, {.fd = cfd, .events = POLLIN}};
        int r = poll(pfd, cfd >= 0 ? 2 : 1, services_poll_timeout());
        if (r < 0 && errno != EINTR)
            continue;
        if (pfd[0].revents & POLLIN) {
            struct signalfd_siginfo si;
            while (read(sfd, &si, sizeof(si)) == sizeof(si)) {
                if (si.ssi_signo == SIGTERM)
                    do_reboot("reboot");
                else if (si.ssi_signo == SIGINT) /* ctrl-alt-del */
                    do_reboot("reboot");
            }
            services_reap();
        }
        if (cfd >= 0 && (pfd[1].revents & POLLIN))
            handle_control(cfd);
        services_restart_due();
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "--check")) {
        /* Host-side validation of .rc files: init --check <file-or-dir> */
        struct stat st;
        if (stat(argv[2], &st) < 0)
            return 1;
        if (S_ISDIR(st.st_mode))
            rc_parse_dir(argv[2]);
        else
            rc_parse_file(argv[2]);
        rc_dump();
        return 0;
    }
    if (argc >= 2 && !strcmp(argv[1], "second_stage"))
        return second_stage_main();
    if (getpid() == 1 && access(FIRST_STAGE_FSTAB, F_OK) == 0)
        return first_stage_main();
    if (getpid() == 1)
        return second_stage_main();

    fprintf(stderr, "usage: init [second_stage | --check <rc>]\n");
    return 1;
}
