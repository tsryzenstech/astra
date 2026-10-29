/*
 * astraOS init - shared helpers
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include "util.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static int kmsg_fd = -1;

void klog_init(void)
{
    if (kmsg_fd >= 0)
        return;
    kmsg_fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
}

void klog(int level, const char *fmt, ...)
{
    char buf[1024];
    int n = snprintf(buf, sizeof(buf), "<%d>init: ", level);
    va_list ap;
    va_start(ap, fmt);
    n += vsnprintf(buf + n, sizeof(buf) - (size_t)n - 2, fmt, ap);
    va_end(ap);
    if (n > (int)sizeof(buf) - 2)
        n = (int)sizeof(buf) - 2;
    buf[n++] = '\n';
    buf[n] = '\0';

    if (kmsg_fd >= 0 && write(kmsg_fd, buf, (size_t)n) == n)
        return;
    /* Skip the "<N>" priority prefix on stderr. */
    fputs(strchr(buf, '>') + 1, stderr);
}

int mkdir_p(const char *path, mode_t mode)
{
    char tmp[512];
    if (snprintf(tmp, sizeof(tmp), "%s", path) >= (int)sizeof(tmp))
        return -1;
    for (char *p = tmp + 1; *p; p++) {
        if (*p != '/')
            continue;
        *p = '\0';
        if (mkdir(tmp, 0755) < 0 && errno != EEXIST)
            return -1;
        *p = '/';
    }
    if (mkdir(tmp, mode) < 0 && errno != EEXIST)
        return -1;
    return 0;
}

int write_file(const char *path, const char *data)
{
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0)
        return -1;
    size_t len = strlen(data);
    ssize_t w = write(fd, data, len);
    close(fd);
    return w == (ssize_t)len ? 0 : -1;
}

char *read_file(const char *path, size_t *len_out)
{
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return NULL;
    size_t cap = 4096, len = 0;
    char *buf = malloc(cap + 1);
    for (;;) {
        if (len == cap) {
            cap *= 2;
            char *nb = realloc(buf, cap + 1);
            if (!nb) {
                free(buf);
                close(fd);
                return NULL;
            }
            buf = nb;
        }
        ssize_t r = read(fd, buf + len, cap - len);
        if (r < 0 && errno == EINTR)
            continue;
        if (r <= 0)
            break;
        len += (size_t)r;
    }
    close(fd);
    buf[len] = '\0';
    if (len_out)
        *len_out = len;
    return buf;
}

long long now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

/* Reads PARTNAME= and DEVNAME= from a sysfs uevent file. */
static int read_uevent(const char *dir, char *partname, size_t plen, char *devname, size_t dlen)
{
    char path[512];
    snprintf(path, sizeof(path), "/sys/class/block/%s/uevent", dir);
    char *data = read_file(path, NULL);
    if (!data)
        return -1;
    partname[0] = devname[0] = '\0';
    for (char *line = strtok(data, "\n"); line; line = strtok(NULL, "\n")) {
        if (!strncmp(line, "PARTNAME=", 9))
            snprintf(partname, plen, "%s", line + 9);
        else if (!strncmp(line, "DEVNAME=", 8))
            snprintf(devname, dlen, "%s", line + 8);
    }
    free(data);
    return partname[0] && devname[0] ? 0 : -1;
}

int find_block_by_partname(const char *name, char *out, size_t outlen, int timeout_ms)
{
    long long deadline = now_ms() + timeout_ms;
    do {
        DIR *d = opendir("/sys/class/block");
        if (d) {
            struct dirent *de;
            while ((de = readdir(d))) {
                char part[64], dev[64];
                if (de->d_name[0] == '.')
                    continue;
                if (read_uevent(de->d_name, part, sizeof(part), dev, sizeof(dev)) == 0 &&
                    !strcmp(part, name)) {
                    snprintf(out, outlen, "/dev/%s", dev);
                    closedir(d);
                    return 0;
                }
            }
            closedir(d);
        }
        usleep(50 * 1000);
    } while (now_ms() < deadline);
    return -1;
}

void create_by_name_links(void)
{
    mkdir_p("/dev/block/by-name", 0755);
    DIR *d = opendir("/sys/class/block");
    if (!d)
        return;
    struct dirent *de;
    while ((de = readdir(d))) {
        char part[64], dev[64], link[160], target[96];
        if (de->d_name[0] == '.')
            continue;
        if (read_uevent(de->d_name, part, sizeof(part), dev, sizeof(dev)) < 0)
            continue;
        snprintf(link, sizeof(link), "/dev/block/by-name/%s", part);
        snprintf(target, sizeof(target), "/dev/%s", dev);
        unlink(link);
        if (symlink(target, link) < 0)
            WARN("by-name link %s failed: %s", link, strerror(errno));
    }
    closedir(d);
}

int has_known_filesystem(const char *dev)
{
    unsigned char sb[4096];
    int fd = open(dev, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;
    ssize_t r = pread(fd, sb, sizeof(sb), 0);
    close(fd);
    if (r != (ssize_t)sizeof(sb))
        return 0;
    /* ext2/3/4: magic 0xEF53 at 1024 + 56 */
    if (sb[1024 + 56] == 0x53 && sb[1024 + 57] == 0xEF)
        return 1;
    /* f2fs: magic 0xF2F52010 at 1024 */
    if (sb[1024] == 0x10 && sb[1025] == 0x20 && sb[1026] == 0xF5 && sb[1027] == 0xF2)
        return 1;
    return 0;
}

static const struct {
    const char *name;
    unsigned id;
} android_ids[] = {
    {"root", 0},       {"system", 1000}, {"radio", 1001}, {"bluetooth", 1002},
    {"graphics", 1003}, {"input", 1004},  {"audio", 1005}, {"camera", 1006},
    {"log", 1007},     {"wifi", 1010},   {"media", 1013}, {"media_rw", 1023}, {"shell", 2000},
    {"inet", 3003},    {"net_admin", 3005}, {"video", 1040}, {"apps", 10000},
};

int decode_id(const char *name, unsigned *out)
{
    char *end;
    unsigned long v = strtoul(name, &end, 10);
    if (*name && !*end) {
        *out = (unsigned)v;
        return 0;
    }
    for (size_t i = 0; i < sizeof(android_ids) / sizeof(android_ids[0]); i++) {
        if (!strcmp(android_ids[i].name, name)) {
            *out = android_ids[i].id;
            return 0;
        }
    }
    return -1;
}

void remove_tree_same_dev(const char *path, dev_t dev)
{
    DIR *d = opendir(path);
    if (!d)
        return;
    struct dirent *de;
    while ((de = readdir(d))) {
        if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, ".."))
            continue;
        char child[512];
        struct stat st;
        snprintf(child, sizeof(child), "%s/%s", strcmp(path, "/") ? path : "", de->d_name);
        if (lstat(child, &st) < 0 || st.st_dev != dev)
            continue;
        if (S_ISDIR(st.st_mode)) {
            remove_tree_same_dev(child, dev);
            rmdir(child);
        } else {
            unlink(child);
        }
    }
    closedir(d);
}
