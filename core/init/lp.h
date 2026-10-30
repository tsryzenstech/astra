/*
 * astraOS init - dynamic partitions ("super") support
 *
 * Parses the logical partition metadata written by lpmake and maps every
 * logical partition to a device-mapper device (/dev/block/mapper/<name>).
 * The on-disk format is the one used by Android's liblp, so stock tooling
 * (lpmake, lpdump, fastboot) keeps working with astraOS images.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <stddef.h>
#include <stdint.h>

/* Maps all logical partitions found on the super device.
 * Returns the number of mapped partitions, or -1 on error. */
int lp_map_super(const char *super_dev);

/* Resolves the mapped device node of a logical partition. */
int lp_partition_path(const char *name, char *out, size_t outlen);

/* Maps num_sectors (512 bytes) of dev from start_sector as
 * /dev/block/mapper/<name>. Returns 0 on success. */
int lp_map_linear(const char *name, const char *dev, uint64_t start_sector, uint64_t num_sectors);
