/*
 * astraOS init - shared helpers
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <stddef.h>
#include <sys/types.h>

#define INIT_LOG_ERR 3
#define INIT_LOG_WARN 4
#define INIT_LOG_INFO 6

void klog_init(void);
void klog(int level, const char *fmt, ...) __attribute__((format(printf, 2, 3)));

#define ERR(...) klog(INIT_LOG_ERR, __VA_ARGS__)
#define WARN(...) klog(INIT_LOG_WARN, __VA_ARGS__)
#define INFO(...) klog(INIT_LOG_INFO, __VA_ARGS__)

int mkdir_p(const char *path, mode_t mode);
int write_file(const char *path, const char *data);
char *read_file(const char *path, size_t *len_out);
long long now_ms(void);

/* Resolve a partition by its GPT name (PARTNAME) through sysfs.
 * Writes "/dev/<devname>" into out. Waits up to timeout_ms for it to appear. */
int find_block_by_partname(const char *name, char *out, size_t outlen, int timeout_ms);

/* Create /dev/block/by-name/<PARTNAME> symlinks for every partition currently known. */
void create_by_name_links(void);

/* Returns 1 if the block device carries an ext4 or f2fs superblock. */
int has_known_filesystem(const char *dev);

/* Android-style user/group names (system, graphics, ...) or numeric ids. */
int decode_id(const char *name, unsigned *out);

/* Recursively delete a directory tree without crossing filesystems. */
void remove_tree_same_dev(const char *path, dev_t dev);
