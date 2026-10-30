/*
 * astraOS init - fstab parsing and mounting
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include "fstab.h"
#include "lp.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <unistd.h>

static const struct {
    const char *name;
    unsigned long flag;
} mount_flags[] = {
    {"ro", MS_RDONLY},       {"rw", 0},           {"nosuid", MS_NOSUID},
    {"nodev", MS_NODEV},     {"noexec", MS_NOEXEC}, {"noatime", MS_NOATIME},
    {"nodiratime", MS_NODIRATIME}, {"relatime", MS_RELATIME}, {"sync", MS_SYNCHRONOUS},
    {"defaults", 0},
};

static void parse_mount_flags(char *opts, struct fstab_entry *e)
{
    char data[256] = "";
    for (char *tok = strtok(opts, ","); tok; tok = strtok(NULL, ",")) {
        int known = 0;
        for (size_t i = 0; i < sizeof(mount_flags) / sizeof(mount_flags[0]); i++) {
            if (!strcmp(tok, mount_flags[i].name)) {
                e->flags |= mount_flags[i].flag;
                known = 1;
                break;
            }
        }
        if (!known) {
            if (data[0])
                strncat(data, ",", sizeof(data) - strlen(data) - 1);
            strncat(data, tok, sizeof(data) - strlen(data) - 1);
        }
    }
    e->data = strdup(data);
}

static void parse_fsmgr_flags(char *opts, struct fstab_entry *e)
{
    for (char *tok = strtok(opts, ","); tok; tok = strtok(NULL, ",")) {
        if (!strcmp(tok, "wait"))
            e->wait = 1;
        else if (!strcmp(tok, "logical"))
            e->logical = 1;
        else if (!strcmp(tok, "first_stage_mount"))
            e->first_stage = 1;
        else if (!strcmp(tok, "formattable"))
            e->formattable = 1;
    }
}

struct fstab *fstab_read(const char *path)
{
    char *data = read_file(path, NULL);
    if (!data) {
        ERR("fstab: cannot read %s", path);
        return NULL;
    }
    struct fstab *fs = calloc(1, sizeof(*fs));
    char *save_line;
    for (char *line = strtok_r(data, "\n", &save_line); line; line = strtok_r(NULL, "\n", &save_line)) {
        while (*line == ' ' || *line == '\t')
            line++;
        if (!*line || *line == '#')
            continue;
        char *field[5] = {0};
        char *save_field;
        int n = 0;
        for (char *f = strtok_r(line, " \t\r", &save_field); f && n < 5; f = strtok_r(NULL, " \t\r", &save_field))
            field[n++] = f;
        if (n < 4) {
            WARN("fstab: malformed line in %s", path);
            continue;
        }
        fs->entries = realloc(fs->entries, sizeof(struct fstab_entry) * (size_t)(fs->count + 1));
        struct fstab_entry *e = &fs->entries[fs->count++];
        memset(e, 0, sizeof(*e));
        e->src = strdup(field[0]);
        e->mount_point = strdup(field[1]);
        e->type = strdup(field[2]);
        char opts[256];
        snprintf(opts, sizeof(opts), "%s", field[3]);
        parse_mount_flags(opts, e);
        if (field[4]) {
            snprintf(opts, sizeof(opts), "%s", field[4]);
            parse_fsmgr_flags(opts, e);
        }
    }
    free(data);
    return fs;
}

void fstab_free(struct fstab *fs)
{
    if (!fs)
        return;
    for (int i = 0; i < fs->count; i++) {
        free(fs->entries[i].src);
        free(fs->entries[i].mount_point);
        free(fs->entries[i].type);
        free(fs->entries[i].data);
    }
    free(fs->entries);
    free(fs);
}

/* Booted through U-Boot, userdata starts with a small disk image: a GPT
 * (4096 or 512 byte sectors) whose first partition, "astra_esp", is the EFI
 * system partition U-Boot starts astraOS from. /data is what follows the
 * first ASTRA_ESP_RESERVED bytes. */
#define ASTRA_ESP_RESERVED (128ULL << 20)

static int has_astra_esp(const char *dev)
{
    int fd = open(dev, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;
    int found = 0;
    for (unsigned lba = 512; lba <= 4096 && !found; lba *= 8) {
        unsigned char hdr[92], entry[128];
        if (pread(fd, hdr, sizeof(hdr), lba) != sizeof(hdr) || memcmp(hdr, "EFI PART", 8))
            continue;
        uint64_t entries_lba;
        memcpy(&entries_lba, hdr + 72, sizeof(entries_lba));
        if (pread(fd, entry, sizeof(entry), (off_t)(entries_lba * lba)) != sizeof(entry))
            continue;
        /* The partition name is UTF-16LE at offset 56. */
        const char *want = "astra_esp";
        found = 1;
        for (size_t i = 0; i <= strlen(want); i++)
            if (entry[56 + 2 * i] != (unsigned char)want[i] || entry[57 + 2 * i] != 0)
                found = 0;
    }
    close(fd);
    return found;
}

static int map_astra_data(const char *dev, char *out, size_t outlen)
{
    int fd = open(dev, O_RDONLY | O_CLOEXEC);
    uint64_t size = 0;
    if (fd < 0 || ioctl(fd, BLKGETSIZE64, &size) < 0 || size <= 2 * ASTRA_ESP_RESERVED) {
        if (fd >= 0)
            close(fd);
        return -1;
    }
    close(fd);
    if (lp_map_linear("astra-data", dev, ASTRA_ESP_RESERVED / 512, (size - ASTRA_ESP_RESERVED) / 512) < 0)
        return -1;
    return lp_partition_path("astra-data", out, outlen);
}

static int resolve_source(const struct fstab_entry *e, char *out, size_t outlen)
{
    if (e->logical)
        return lp_partition_path(e->src, out, outlen);

    const char *prefix = "/dev/block/by-name/";
    if (!strncmp(e->src, prefix, strlen(prefix))) {
        if (find_block_by_partname(e->src + strlen(prefix), out, outlen, e->wait ? 10000 : 0) < 0)
            return -1;
        if (!strcmp(e->mount_point, "/data") && has_astra_esp(out)) {
            char data[128];
            if (map_astra_data(out, data, sizeof(data)) == 0) {
                INFO("fstab: /data follows the EFI partition on %s", out);
                snprintf(out, outlen, "%s", data);
            }
        }
        return 0;
    }

    snprintf(out, outlen, "%s", e->src);
    if (e->wait) {
        for (int i = 0; i < 200 && access(out, F_OK) < 0; i++)
            usleep(50 * 1000);
    }
    return access(out, F_OK);
}

static int format_device(const char *dev, const char *type)
{
    INFO("fstab: formatting %s as %s", dev, type);
    pid_t pid = fork();
    if (pid == 0) {
        if (!strcmp(type, "f2fs"))
            execl("/system/bin/mkfs.f2fs", "mkfs.f2fs", "-f", "-l", "userdata", dev, (char *)NULL);
        else
            execl("/system/bin/mke2fs", "mke2fs", "-F", "-t", "ext4", "-L", "userdata", dev, (char *)NULL);
        _exit(127);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

int fstab_mount(const struct fstab_entry *e, const char *root)
{
    char dev[128], target[256];
    if (resolve_source(e, dev, sizeof(dev)) < 0) {
        ERR("fstab: source %s for %s not found", e->src, e->mount_point);
        return -1;
    }
    snprintf(target, sizeof(target), "%s%s", root, e->mount_point);
    mkdir_p(target, 0755);

    if (mount(dev, target, e->type, e->flags, e->data) == 0) {
        INFO("fstab: mounted %s on %s (%s)", dev, target, e->type);
        return 0;
    }
    int err = errno;
    /* Only blank devices are formatted: never touch a filesystem we failed to mount. */
    if (e->formattable && !has_known_filesystem(dev)) {
        if (format_device(dev, e->type) == 0 && mount(dev, target, e->type, e->flags, e->data) == 0) {
            INFO("fstab: formatted and mounted %s on %s", dev, target);
            return 0;
        }
    }
    if (e->formattable) {
        /* Data left by the stock system is often f2fs where we expect ext4
         * (or the other way round): mount it as it is. */
        const char *other = !strcmp(e->type, "ext4") ? "f2fs" : "ext4";
        if (mount(dev, target, other, e->flags, NULL) == 0) {
            WARN("fstab: %s is %s, not %s: mounted as it is", dev, other, e->type);
            return 0;
        }
        /* Still start the system, with a /data that lives in memory. */
        ERR("fstab: mount %s on %s failed: %s; using a temporary %s", dev, target, strerror(err), target);
        return mount("tmpfs", target, "tmpfs", MS_NOSUID | MS_NODEV, "mode=0755");
    }
    ERR("fstab: mount %s on %s failed: %s", dev, target, strerror(err));
    return -1;
}
