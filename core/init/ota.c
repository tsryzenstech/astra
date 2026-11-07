/*
 * astraOS init - OTA updates, applied by the first stage (see ota.h)
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include "ota.h"
#include "fstab.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/fs.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/reboot.h>
#include <sys/stat.h>
#include <unistd.h>

#define OTA_MOUNT "/ota-data"
#define OTA_DIR OTA_MOUNT "/ota/apply"
#define OTA_ATTEMPTS 3

/* Android sparse images (system/core/libsparse/sparse_format.h). */
#define SPARSE_MAGIC 0xed26ff3aU
#define CHUNK_RAW 0xCAC1
#define CHUNK_FILL 0xCAC2
#define CHUNK_DONT_CARE 0xCAC3
#define CHUNK_CRC32 0xCAC4

struct sparse_header {
    uint32_t magic;
    uint16_t major_version;
    uint16_t minor_version;
    uint16_t file_hdr_sz;
    uint16_t chunk_hdr_sz;
    uint32_t blk_sz;
    uint32_t total_blks;
    uint32_t total_chunks;
    uint32_t image_checksum;
} __attribute__((packed));

struct chunk_header {
    uint16_t chunk_type;
    uint16_t reserved1;
    uint32_t chunk_sz;
    uint32_t total_sz;
} __attribute__((packed));

#define BUF_SIZE (4u << 20)

static int read_full(int fd, void *buf, size_t len)
{
    char *p = buf;
    while (len) {
        ssize_t n = read(fd, p, len);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        p += n;
        len -= (size_t)n;
    }
    return 0;
}

static int pwrite_full(int fd, const void *buf, size_t len, uint64_t off)
{
    const char *p = buf;
    while (len) {
        ssize_t n = pwrite(fd, p, len, (off_t)off);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            return -1;
        p += n;
        len -= (size_t)n;
        off += (uint64_t)n;
    }
    return 0;
}

static uint64_t device_size(int fd)
{
    uint64_t size = 0;
    struct stat st;
    if (ioctl(fd, BLKGETSIZE64, &size) < 0 && fstat(fd, &st) == 0)
        size = (uint64_t)st.st_size; /* a plain file (tests) */
    return size;
}

/* Writes a sparse image to a block device, as fastboot does: the chunks that
 * carry no data ("don't care") leave the device as it is. */
static int write_sparse(const char *image, const char *dev)
{
    int in = open(image, O_RDONLY | O_CLOEXEC);
    int out = open(dev, O_WRONLY | O_CLOEXEC);
    char *buf = malloc(BUF_SIZE);
    int ret = -1;
    struct sparse_header h;
    if (in < 0 || out < 0 || !buf || read_full(in, &h, sizeof(h)) < 0) {
        ERR("ota: cannot open %s or %s: %s", image, dev, strerror(errno));
        goto out;
    }
    if (h.magic != SPARSE_MAGIC || h.major_version != 1 || h.file_hdr_sz < sizeof(h) ||
        h.chunk_hdr_sz < sizeof(struct chunk_header) || !h.blk_sz || h.blk_sz % 4) {
        ERR("ota: %s is not a sparse image", image);
        goto out;
    }
    uint64_t total = (uint64_t)h.total_blks * h.blk_sz;
    if (total > device_size(out)) {
        ERR("ota: %s (%llu bytes) does not fit %s", image, (unsigned long long)total, dev);
        goto out;
    }
    lseek(in, h.file_hdr_sz, SEEK_SET);
    uint64_t pos = 0;
    int shown = -1;
    for (uint32_t c = 0; c < h.total_chunks; c++) {
        struct chunk_header ch;
        if (read_full(in, &ch, sizeof(ch)) < 0)
            goto short_read;
        if (h.chunk_hdr_sz > sizeof(ch))
            lseek(in, h.chunk_hdr_sz - sizeof(ch), SEEK_CUR);
        uint64_t len = (uint64_t)ch.chunk_sz * h.blk_sz;
        if (pos + len > total && ch.chunk_type != CHUNK_CRC32) {
            ERR("ota: chunk %u goes past the end of the image", c);
            goto out;
        }
        switch (ch.chunk_type) {
        case CHUNK_RAW:
            for (uint64_t done = 0; done < len;) {
                size_t n = len - done > BUF_SIZE ? BUF_SIZE : (size_t)(len - done);
                if (read_full(in, buf, n) < 0)
                    goto short_read;
                if (pwrite_full(out, buf, n, pos + done) < 0)
                    goto write_error;
                done += n;
            }
            break;
        case CHUNK_FILL: {
            uint32_t value;
            if (read_full(in, &value, sizeof(value)) < 0)
                goto short_read;
            for (size_t i = 0; i < BUF_SIZE / 4; i++)
                ((uint32_t *)buf)[i] = value;
            for (uint64_t done = 0; done < len;) {
                size_t n = len - done > BUF_SIZE ? BUF_SIZE : (size_t)(len - done);
                if (pwrite_full(out, buf, n, pos + done) < 0)
                    goto write_error;
                done += n;
            }
            break;
        }
        case CHUNK_DONT_CARE:
            break;
        case CHUNK_CRC32:
            lseek(in, 4, SEEK_CUR);
            len = 0;
            break;
        default:
            ERR("ota: unknown chunk type 0x%x", ch.chunk_type);
            goto out;
        }
        pos += len;
        int percent = (int)(pos * 100 / total);
        if (percent / 10 != shown) {
            shown = percent / 10;
            INFO("ota: super %d%%", percent);
        }
    }
    if (fsync(out) < 0)
        goto write_error;
    ret = 0;
    goto out;
short_read:
    ERR("ota: %s ends too early", image);
    goto out;
write_error:
    ERR("ota: writing %s: %s", dev, strerror(errno));
out:
    free(buf);
    if (in >= 0)
        close(in);
    if (out >= 0)
        close(out);
    return ret;
}

/* Where the EFI partition ("astra_esp", the first entry of the GPT at the
 * start of userdata) lies, in bytes. */
static int esp_extent(int fd, uint64_t *start, uint64_t *size)
{
    for (unsigned sector = 512; sector <= 4096; sector *= 8) {
        unsigned char hdr[92], entry[128];
        if (pread(fd, hdr, sizeof(hdr), sector) != sizeof(hdr) || memcmp(hdr, "EFI PART", 8))
            continue;
        uint64_t entries_lba, first, last;
        memcpy(&entries_lba, hdr + 72, sizeof(entries_lba));
        if (pread(fd, entry, sizeof(entry), (off_t)(entries_lba * sector)) != sizeof(entry))
            continue;
        memcpy(&first, entry + 32, sizeof(first));
        memcpy(&last, entry + 40, sizeof(last));
        if (!first || last < first)
            continue;
        *start = first * sector;
        *size = (last - first + 1) * sector;
        return 0;
    }
    return -1;
}

static int write_esp(const char *image, const char *dev)
{
    int in = open(image, O_RDONLY | O_CLOEXEC);
    int out = open(dev, O_RDWR | O_CLOEXEC);
    char *buf = malloc(BUF_SIZE);
    int ret = -1;
    struct stat st;
    uint64_t start, size;
    if (in < 0 || out < 0 || !buf || fstat(in, &st) < 0) {
        ERR("ota: cannot open %s or %s: %s", image, dev, strerror(errno));
        goto out;
    }
    if (esp_extent(out, &start, &size) < 0 || (uint64_t)st.st_size != size) {
        /* Only the EFI partition's contents change: a different size would
         * need a new partition table, which only fastboot writes. */
        ERR("ota: %s (%lld bytes) does not match the EFI partition on %s", image, (long long)st.st_size, dev);
        goto out;
    }
    for (uint64_t done = 0; done < size;) {
        size_t n = size - done > BUF_SIZE ? BUF_SIZE : (size_t)(size - done);
        if (read_full(in, buf, n) < 0 || pwrite_full(out, buf, n, start + done) < 0) {
            ERR("ota: writing the EFI partition: %s", strerror(errno));
            goto out;
        }
        done += n;
    }
    ret = fsync(out);
out:
    free(buf);
    if (in >= 0)
        close(in);
    if (out >= 0)
        close(out);
    return ret;
}

static void set_state(const char *fmt, int attempt)
{
    char state[64];
    snprintf(state, sizeof(state), fmt, attempt);
    write_file(OTA_DIR "/state", state);
    sync();
}

void ota_apply_pending(const char *super_dev)
{
    char userdata[64], data[128];
    if (find_block_by_partname("userdata", userdata, sizeof(userdata), 10000) < 0 ||
        fstab_astra_data(userdata, data, sizeof(data)) < 0)
        return;
    mkdir_p(OTA_MOUNT, 0700);
    if (mount(data, OTA_MOUNT, "ext4", MS_NOATIME | MS_NOSUID | MS_NODEV, NULL) < 0) {
        rmdir(OTA_MOUNT);
        return; /* first boot (not formatted yet) or not ext4: nothing staged */
    }
    char *state = read_file(OTA_DIR "/state", NULL);
    int attempt = 0;
    if (state && !strncmp(state, "applying", 8))
        attempt = atoi(state + 8);
    int pending = state && (!strncmp(state, "ready", 5) || !strncmp(state, "applying", 8));
    free(state);
    if (!pending)
        goto done;
    if (attempt >= OTA_ATTEMPTS) {
        ERR("ota: the update failed %d times, giving up", attempt);
        set_state("failed", 0);
        goto done;
    }

    INFO("ota: applying the update (attempt %d)", attempt + 1);
    set_state("applying %d", attempt + 1);
    if (write_sparse(OTA_DIR "/super.img", super_dev) < 0 || write_esp(OTA_DIR "/esp.fat", userdata) < 0) {
        /* The next boot tries again: the images stay. */
        ERR("ota: the update could not be written");
        goto done;
    }
    unlink(OTA_DIR "/super.img");
    unlink(OTA_DIR "/esp.fat");
    set_state("installed", 0);
    INFO("ota: update written, restarting into it");
    umount(OTA_MOUNT);
    sync();
    reboot(RB_AUTOBOOT);
    return;
done:
    umount(OTA_MOUNT);
    rmdir(OTA_MOUNT);
}
