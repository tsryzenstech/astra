/*
 * astraOS init - service supervision
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include "rc.h"
#include "util.h"

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define CRASH_WINDOW_MS (4 * 60 * 1000)
#define MAX_RESTART_DELAY_MS 30000

static struct service *services, *services_tail;

struct service *service_list(void)
{
    return services;
}

struct service *service_find(const char *name)
{
    for (struct service *s = services; s; s = s->next)
        if (!strcmp(s->name, name))
            return s;
    return NULL;
}

void service_add(struct service *s)
{
    if (services_tail)
        services_tail->next = s;
    else
        services = s;
    services_tail = s;
}

static char **build_env(struct service *s)
{
    char **global = init_environ();
    int n = 0;
    while (global && global[n])
        n++;
    char **env = calloc((size_t)(n + s->nenv + 1), sizeof(char *));
    for (int i = 0; i < n; i++)
        env[i] = global[i];
    for (int i = 0; i < s->nenv; i++)
        env[n + i] = s->env[i];
    return env;
}

void service_start(struct service *s)
{
    if (s->pid > 0)
        return;
    s->stopping = 0;
    s->restart_at_ms = 0;
    if (access(s->argv[0], X_OK) < 0) {
        /* e.g. an optional vendor daemon that is not part of this build */
        WARN("service '%s': %s missing, disabling", s->name, s->argv[0]);
        s->flags |= SVC_DISABLED;
        return;
    }

    pid_t pid = fork();
    if (pid < 0) {
        ERR("service %s: fork failed: %s", s->name, strerror(errno));
        return;
    }
    if (pid == 0) {
        sigset_t all;
        sigemptyset(&all);
        sigprocmask(SIG_SETMASK, &all, NULL);
        setsid();

        int null = open("/dev/null", O_RDWR);
        int log = open("/dev/kmsg", O_WRONLY);
        dup2(null, 0);
        dup2(log >= 0 ? log : null, 1);
        dup2(log >= 0 ? log : null, 2);

        if (s->ngroups && setgroups((size_t)s->ngroups, (gid_t *)s->groups) < 0)
            _exit(126);
        if (s->gid && setgid(s->gid) < 0)
            _exit(126);
        if (s->uid && setuid(s->uid) < 0)
            _exit(126);

        execve(s->argv[0], s->argv, build_env(s));
        _exit(127);
    }
    s->pid = pid;
    s->started_ms = now_ms();
    INFO("started service '%s' (pid %d)", s->name, pid);
}

void service_stop(struct service *s)
{
    s->restart_at_ms = 0;
    if (s->pid <= 0)
        return;
    s->stopping = 1;
    kill(-s->pid, SIGTERM);
}

void services_class_start(const char *klass)
{
    for (struct service *s = services; s; s = s->next)
        if (!strcmp(s->klass, klass) && !(s->flags & SVC_DISABLED))
            service_start(s);
}

void services_class_stop(const char *klass)
{
    for (struct service *s = services; s; s = s->next)
        if (!strcmp(s->klass, klass))
            service_stop(s);
}

static void service_exited(struct service *s, int status)
{
    long long now = now_ms();
    s->pid = 0;
    if (WIFSIGNALED(status))
        WARN("service '%s' killed by signal %d", s->name, WTERMSIG(status));
    else
        INFO("service '%s' exited with status %d", s->name, WEXITSTATUS(status));

    if (s->stopping || (s->flags & SVC_ONESHOT)) {
        s->stopping = 0;
        return;
    }
    /* Exponential backoff, reset after a minute of healthy uptime. */
    if (now - s->started_ms > 60000)
        s->crashes = 0;
    s->crashes++;
    long long delay = 500LL << (s->crashes > 6 ? 6 : s->crashes - 1);
    if (delay > MAX_RESTART_DELAY_MS)
        delay = MAX_RESTART_DELAY_MS;
    if ((s->flags & SVC_CRITICAL) && s->crashes > 4 && now - s->started_ms < CRASH_WINDOW_MS)
        ERR("critical service '%s' keeps crashing", s->name);
    s->restart_at_ms = now + delay;
}

void services_reap(void)
{
    for (;;) {
        int status;
        pid_t pid = waitpid(-1, &status, WNOHANG);
        if (pid <= 0)
            return;
        for (struct service *s = services; s; s = s->next) {
            if (s->pid == pid) {
                service_exited(s, status);
                break;
            }
        }
    }
}

void services_restart_due(void)
{
    long long now = now_ms();
    for (struct service *s = services; s; s = s->next)
        if (s->restart_at_ms && s->restart_at_ms <= now)
            service_start(s);
}

int services_poll_timeout(void)
{
    long long now = now_ms(), next = -1;
    for (struct service *s = services; s; s = s->next) {
        if (!s->restart_at_ms)
            continue;
        long long d = s->restart_at_ms - now;
        if (d < 0)
            d = 0;
        if (next < 0 || d < next)
            next = d;
    }
    return (int)next;
}

void services_stop_all(int timeout_ms)
{
    for (struct service *s = services; s; s = s->next)
        service_stop(s);
    long long deadline = now_ms() + timeout_ms;
    for (;;) {
        services_reap();
        int alive = 0;
        for (struct service *s = services; s; s = s->next)
            alive |= s->pid > 0;
        if (!alive || now_ms() > deadline)
            break;
        usleep(50 * 1000);
    }
    for (struct service *s = services; s; s = s->next)
        if (s->pid > 0)
            kill(-s->pid, SIGKILL);
}
