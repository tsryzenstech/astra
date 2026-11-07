/*
 * astraOS init - OTA updates
 *
 * The update service (astrad) downloads and verifies an update while the
 * system runs and leaves it in /data/ota/apply:
 *
 *   super.img   the new "super" partition (Android sparse image, as lpmake writes it)
 *   esp.fat     the new EFI partition (kernel, ramdisk, device tree)
 *   state       "ready"
 *
 * The first stage writes them before it maps or mounts anything from super,
 * so nothing it writes is in use, then restarts the phone into the new
 * system. An interrupted write ("applying") starts again on the next boot.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

/* Returns only when there is nothing to apply, or applying failed: after a
 * successful update it restarts the phone. */
void ota_apply_pending(const char *super_dev);
