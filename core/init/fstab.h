/*
 * astraOS init - fstab parsing and mounting
 *
 * Format (Android style):
 *   <src> <mount point> <type> <mount flags> <fs_mgr flags>
 *
 * fs_mgr flags: wait, logical, first_stage_mount, formattable
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <stddef.h>

struct fstab_entry {
    char *src;
    char *mount_point;
    char *type;
    unsigned long flags;
    char *data;
    int wait;
    int logical;
    int first_stage;
    int formattable;
};

struct fstab {
    struct fstab_entry *entries;
    int count;
};

struct fstab *fstab_read(const char *path);
void fstab_free(struct fstab *fs);

/* Mounts an entry below root (use "" for the real root). */
int fstab_mount(const struct fstab_entry *e, const char *root);

/* Booted through U-Boot: maps what follows the EFI partition at the start of
 * the userdata device as /dev/block/mapper/astra-data. -1 without that layout. */
int fstab_astra_data(const char *userdata, char *out, size_t outlen);
