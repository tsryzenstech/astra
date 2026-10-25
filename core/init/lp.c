/*
 * astraOS init - dynamic partitions ("super") support
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include "lp.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/dm-ioctl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#define LP_PARTITION_RESERVED_BYTES 4096
#define LP_METADATA_GEOMETRY_MAGIC 0x616c4467
#define LP_METADATA_GEOMETRY_SIZE 4096
#define LP_METADATA_HEADER_MAGIC 0x414C5030
#define LP_SECTOR_SIZE 512
#define LP_PARTITION_ATTR_READONLY (1 << 0)
#define LP_TARGET_TYPE_LINEAR 0
#define LP_TARGET_TYPE_ZERO 1

struct lp_geometry {
    uint32_t magic;
    uint32_t struct_size;
    uint8_t checksum[32];
    uint32_t metadata_max_size;
    uint32_t metadata_slot_count;
    uint32_t logical_block_size;
} __attribute__((packed));

struct lp_table_desc {
    uint32_t offset;
    uint32_t num_entries;
    uint32_t entry_size;
} __attribute__((packed));

/* Fields common to every metadata version (v10.0 header is exactly this). */
struct lp_header {
    uint32_t magic;
    uint16_t major_version;
    uint16_t minor_version;
    uint32_t header_size;
    uint8_t header_checksum[32];
    uint32_t tables_size;
    uint8_t tables_checksum[32];
    struct lp_table_desc partitions;
    struct lp_table_desc extents;
    struct lp_table_desc groups;
    struct lp_table_desc block_devices;
} __attribute__((packed));

struct lp_partition {
    char name[36];
    uint32_t attributes;
    uint32_t first_extent_index;
    uint32_t num_extents;
    uint32_t group_index;
} __attribute__((packed));

struct lp_extent {
    uint64_t num_sectors;
    uint32_t target_type;
    uint64_t target_data;
    uint32_t target_source;
} __attribute__((packed));

static int dm_ioctl_init(struct dm_ioctl *io, size_t size, const char *name, unsigned flags)
{
    memset(io, 0, size);
    io->version[0] = DM_VERSION_MAJOR;
    io->version[1] = DM_VERSION_MINOR;
    io->version[2] = DM_VERSION_PATCHLEVEL;
    io->data_size = (uint32_t)size;
    io->data_start = sizeof(struct dm_ioctl);
    io->flags = flags;
    if (strlen(name) >= sizeof(io->name))
        return -1;
    strcpy(io->name, name);
    return 0;
}

/* Creates a dm device made of linear/zero targets and returns its minor. */
static int dm_create(const char *name, dev_t source, const struct lp_extent *ext, uint32_t count,
                     int readonly, unsigned *minor_out)
{
    int fd = open("/dev/mapper/control", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        mkdir_p("/dev/mapper", 0755);
        if (mknod("/dev/mapper/control", S_IFCHR | 0600, makedev(10, 236)) == 0)
            fd = open("/dev/mapper/control", O_RDWR | O_CLOEXEC);
    }
    if (fd < 0) {
        ERR("dm: cannot open control node: %s", strerror(errno));
        return -1;
    }

    size_t size = sizeof(struct dm_ioctl) + count * (sizeof(struct dm_target_spec) + 64) + 64;
    struct dm_ioctl *io = calloc(1, size);
    int ret = -1;

    dm_ioctl_init(io, sizeof(struct dm_ioctl), name, 0);
    if (ioctl(fd, DM_DEV_CREATE, io) < 0 && errno != EBUSY) {
        ERR("dm: create %s: %s", name, strerror(errno));
        goto out;
    }

    dm_ioctl_init(io, size, name, readonly ? DM_READONLY_FLAG : 0);
    io->target_count = count;
    char *cursor = (char *)io + sizeof(struct dm_ioctl);
    uint64_t start = 0;
    for (uint32_t i = 0; i < count; i++) {
        struct dm_target_spec *spec = (struct dm_target_spec *)cursor;
        char *params = cursor + sizeof(*spec);
        spec->sector_start = start;
        spec->length = ext[i].num_sectors;
        if (ext[i].target_type == LP_TARGET_TYPE_ZERO) {
            strcpy(spec->target_type, "zero");
            params[0] = '\0';
        } else {
            strcpy(spec->target_type, "linear");
            snprintf(params, 64, "%u:%u %llu", major(source), minor(source),
                     (unsigned long long)ext[i].target_data);
        }
        size_t step = sizeof(*spec) + strlen(params) + 1;
        step = (step + 7) & ~(size_t)7;
        spec->next = (uint32_t)step;
        cursor += step;
        start += ext[i].num_sectors;
    }
    if (ioctl(fd, DM_TABLE_LOAD, io) < 0) {
        ERR("dm: load table %s: %s", name, strerror(errno));
        goto out;
    }

    dm_ioctl_init(io, sizeof(struct dm_ioctl), name, 0);
    if (ioctl(fd, DM_DEV_SUSPEND, io) < 0) { /* flags == 0 means resume */
        ERR("dm: resume %s: %s", name, strerror(errno));
        goto out;
    }
    *minor_out = minor(io->dev);
    ret = 0;
out:
    free(io);
    close(fd);
    return ret;
}

int lp_map_super(const char *super_dev)
{
    int fd = open(super_dev, O_RDONLY | O_CLOEXEC);
    if (fd < 0) {
        ERR("lp: open %s: %s", super_dev, strerror(errno));
        return -1;
    }
    struct stat st;
    fstat(fd, &st);

    struct lp_geometry geo;
    if (pread(fd, &geo, sizeof(geo), LP_PARTITION_RESERVED_BYTES) != sizeof(geo) ||
        geo.magic != LP_METADATA_GEOMETRY_MAGIC) {
        ERR("lp: %s has no valid geometry", super_dev);
        close(fd);
        return -1;
    }

    off_t meta_off = LP_PARTITION_RESERVED_BYTES + 2 * LP_METADATA_GEOMETRY_SIZE;
    char *meta = malloc(geo.metadata_max_size);
    if (!meta || pread(fd, meta, geo.metadata_max_size, meta_off) != (ssize_t)geo.metadata_max_size) {
        ERR("lp: cannot read metadata");
        free(meta);
        close(fd);
        return -1;
    }
    close(fd);

    struct lp_header *hdr = (struct lp_header *)meta;
    if (hdr->magic != LP_METADATA_HEADER_MAGIC || hdr->major_version != 10 ||
        hdr->header_size + hdr->tables_size > geo.metadata_max_size) {
        ERR("lp: unsupported metadata header (v%u.%u)", hdr->major_version, hdr->minor_version);
        free(meta);
        return -1;
    }

    char *tables = meta + hdr->header_size;
    int mapped = 0;
    mkdir_p("/dev/block/mapper", 0755);

    for (uint32_t i = 0; i < hdr->partitions.num_entries; i++) {
        const struct lp_partition *p =
            (const struct lp_partition *)(tables + hdr->partitions.offset + i * hdr->partitions.entry_size);
        char name[37];
        memcpy(name, p->name, 36);
        name[36] = '\0';
        if (p->num_extents == 0) {
            INFO("lp: skipping empty partition %s", name);
            continue;
        }
        if (p->first_extent_index + p->num_extents > hdr->extents.num_entries) {
            ERR("lp: partition %s has out of range extents", name);
            continue;
        }

        struct lp_extent *ext = calloc(p->num_extents, sizeof(*ext));
        for (uint32_t e = 0; e < p->num_extents; e++)
            memcpy(&ext[e],
                   tables + hdr->extents.offset + (p->first_extent_index + e) * hdr->extents.entry_size,
                   sizeof(*ext));

        unsigned minor_num;
        if (dm_create(name, st.st_rdev, ext, p->num_extents, p->attributes & LP_PARTITION_ATTR_READONLY,
                      &minor_num) == 0) {
            char link[96], target[32];
            snprintf(link, sizeof(link), "/dev/block/mapper/%s", name);
            snprintf(target, sizeof(target), "/dev/dm-%u", minor_num);
            unlink(link);
            symlink(target, link);
            INFO("lp: mapped %s -> %s", name, target);
            mapped++;
        }
        free(ext);
    }
    free(meta);
    return mapped;
}

int lp_partition_path(const char *name, char *out, size_t outlen)
{
    snprintf(out, outlen, "/dev/block/mapper/%s", name);
    /* Wait for devtmpfs to publish the dm node the link points to. */
    for (int i = 0; i < 100; i++) {
        if (access(out, F_OK) == 0)
            return 0;
        usleep(20 * 1000);
    }
    return -1;
}
