/*
 * astraOS init - .rc language (Android-style subset)
 *
 *   on <trigger>
 *       <command> <args...>
 *
 *   service <name> <path> [<args>...]
 *       user <user>
 *       group <group> [<supplementary>...]
 *       class <class>
 *       oneshot | disabled | critical
 *       setenv <key> <value>
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#pragma once

#include <sys/types.h>

#define SVC_ONESHOT (1u << 0)
#define SVC_DISABLED (1u << 1)
#define SVC_CRITICAL (1u << 2)

struct service {
    char *name;
    char **argv;
    unsigned uid;
    unsigned gid;
    unsigned groups[16];
    int ngroups;
    char *klass;
    unsigned flags;
    char **env;
    int nenv;

    pid_t pid;
    int crashes;
    long long started_ms;
    long long restart_at_ms;
    int stopping;
    struct service *next;
};

int rc_parse_file(const char *path);
int rc_parse_dir(const char *dir);
void rc_trigger(const char *trigger);
void rc_dump(void);

/* Global environment handed to every service (setenv). */
void init_setenv(const char *key, const char *value);
char **init_environ(void);

struct service *service_list(void);
struct service *service_find(const char *name);
void service_add(struct service *s);
void service_start(struct service *s);
void service_stop(struct service *s);
void services_class_start(const char *klass);
void services_class_stop(const char *klass);
void services_reap(void);
void services_restart_due(void);
int services_poll_timeout(void);
void services_stop_all(int timeout_ms);
