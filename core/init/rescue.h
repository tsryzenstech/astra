/*
 * astraOS init - rescue mode for a failed first stage (see rescue.c)
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

/* Shows why the boot stopped and serves a USB serial shell. Never returns. */
void rescue(const char *why) __attribute__((noreturn));
