/*
 * astraOS init - .rc parser and builtin commands
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include "rc.h"
#include "fstab.h"
#include "util.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <glob.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct command {
    int argc;
    char **argv;
    const char *file;
    int line;
};

struct action {
    char *trigger;
    struct command *cmds;
    int ncmds;
    struct action *next;
};

static struct action *actions, *actions_tail;
static char **global_env;
static int global_nenv;

/* ---- environment ------------------------------------------------------ */

void init_setenv(const char *key, const char *value)
{
    size_t klen = strlen(key);
    char *entry;
    if (asprintf(&entry, "%s=%s", key, value) < 0)
        return;
    for (int i = 0; i < global_nenv; i++) {
        if (!strncmp(global_env[i], key, klen) && global_env[i][klen] == '=') {
            free(global_env[i]);
            global_env[i] = entry;
            return;
        }
    }
    global_env = realloc(global_env, sizeof(char *) * (size_t)(global_nenv + 2));
    global_env[global_nenv++] = entry;
    global_env[global_nenv] = NULL;
}

char **init_environ(void)
{
    return global_env;
}

/* ---- tokenizer -------------------------------------------------------- */

static int tokenize(char *line, char **argv, int max)
{
    int argc = 0;
    char *p = line;
    while (*p && argc < max) {
        while (*p == ' ' || *p == '\t' || *p == '\r')
            p++;
        if (!*p || *p == '#')
            break;
        if (*p == '"') {
            argv[argc++] = ++p;
            while (*p && *p != '"')
                p++;
        } else {
            argv[argc++] = p;
            while (*p && *p != ' ' && *p != '\t' && *p != '\r')
                p++;
        }
        if (*p)
            *p++ = '\0';
    }
    return argc;
}

static char **dup_argv(int argc, char **argv)
{
    char **out = calloc((size_t)argc + 1, sizeof(char *));
    for (int i = 0; i < argc; i++)
        out[i] = strdup(argv[i]);
    return out;
}

/* ---- parser ----------------------------------------------------------- */

static int parse_service_option(struct service *s, int argc, char **argv, const char *file, int line)
{
    if (!strcmp(argv[0], "user") && argc == 2) {
        if (decode_id(argv[1], &s->uid) < 0)
            goto bad;
    } else if (!strcmp(argv[0], "group") && argc >= 2) {
        if (decode_id(argv[1], &s->gid) < 0)
            goto bad;
        for (int i = 2; i < argc && s->ngroups < 16; i++) {
            if (decode_id(argv[i], &s->groups[s->ngroups]) < 0)
                goto bad;
            s->ngroups++;
        }
    } else if (!strcmp(argv[0], "class") && argc == 2) {
        free(s->klass);
        s->klass = strdup(argv[1]);
    } else if (!strcmp(argv[0], "oneshot")) {
        s->flags |= SVC_ONESHOT;
    } else if (!strcmp(argv[0], "disabled")) {
        s->flags |= SVC_DISABLED;
    } else if (!strcmp(argv[0], "critical")) {
        s->flags |= SVC_CRITICAL;
    } else if (!strcmp(argv[0], "setenv") && argc == 3) {
        s->env = realloc(s->env, sizeof(char *) * (size_t)(s->nenv + 2));
        if (asprintf(&s->env[s->nenv], "%s=%s", argv[1], argv[2]) < 0)
            return -1;
        s->env[++s->nenv] = NULL;
    } else {
        goto bad;
    }
    return 0;
bad:
    ERR("%s:%d: invalid service option '%s'", file, line, argv[0]);
    return -1;
}

int rc_parse_file(const char *path)
{
    char *data = read_file(path, NULL);
    if (!data)
        return -1;

    struct action *cur_action = NULL;
    struct service *cur_service = NULL;
    int lineno = 0;
    char *save;
    const char *file = strdup(path);

    for (char *line = strtok_r(data, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        lineno++;
        char *argv[64];
        int argc = tokenize(line, argv, 64);
        if (argc == 0)
            continue;

        int indented = line[0] == ' ' || line[0] == '\t';
        if (!indented && !strcmp(argv[0], "on") && argc >= 2) {
            cur_service = NULL;
            cur_action = calloc(1, sizeof(*cur_action));
            cur_action->trigger = strdup(argv[1]);
            if (actions_tail)
                actions_tail->next = cur_action;
            else
                actions = cur_action;
            actions_tail = cur_action;
        } else if (!indented && !strcmp(argv[0], "service") && argc >= 3) {
            cur_action = NULL;
            if (service_find(argv[1])) {
                ERR("%s:%d: duplicate service '%s'", path, lineno, argv[1]);
                cur_service = NULL;
                continue;
            }
            cur_service = calloc(1, sizeof(*cur_service));
            cur_service->name = strdup(argv[1]);
            cur_service->argv = dup_argv(argc - 2, argv + 2);
            cur_service->klass = strdup("default");
            service_add(cur_service);
        } else if (cur_action) {
            cur_action->cmds = realloc(cur_action->cmds, sizeof(struct command) * (size_t)(cur_action->ncmds + 1));
            struct command *c = &cur_action->cmds[cur_action->ncmds++];
            c->argc = argc;
            c->argv = dup_argv(argc, argv);
            c->file = file;
            c->line = lineno;
        } else if (cur_service) {
            parse_service_option(cur_service, argc, argv, path, lineno);
        } else {
            ERR("%s:%d: statement outside of a section", path, lineno);
        }
    }
    free(data);
    return 0;
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(char *const *)a, *(char *const *)b);
}

int rc_parse_dir(const char *dir)
{
    DIR *d = opendir(dir);
    if (!d)
        return -1;
    char *names[256];
    int n = 0;
    struct dirent *de;
    while ((de = readdir(d)) && n < 256) {
        size_t len = strlen(de->d_name);
        if (len > 3 && !strcmp(de->d_name + len - 3, ".rc"))
            names[n++] = strdup(de->d_name);
    }
    closedir(d);
    qsort(names, (size_t)n, sizeof(char *), cmp_str);
    for (int i = 0; i < n; i++) {
        char path[512];
        snprintf(path, sizeof(path), "%s/%s", dir, names[i]);
        rc_parse_file(path);
        free(names[i]);
    }
    return n;
}

/* ---- builtins --------------------------------------------------------- */

static int do_chown_one(const char *path, const char *user, const char *group)
{
    unsigned uid, gid = (unsigned)-1;
    if (decode_id(user, &uid) < 0 || (group && decode_id(group, &gid) < 0))
        return -1;
    return lchown(path, uid, gid);
}

/* Runs fn on every path matching a glob pattern (sysfs paths often use wildcards). */
static int for_each_glob(const char *pattern, int (*fn)(const char *, void *), void *ctx)
{
    glob_t g;
    if (glob(pattern, GLOB_NOSORT, NULL, &g) != 0)
        return -1;
    int ret = 0;
    for (size_t i = 0; i < g.gl_pathc; i++)
        if (fn(g.gl_pathv[i], ctx) < 0)
            ret = -1;
    globfree(&g);
    return ret;
}

struct chown_ctx {
    const char *user, *group;
};
static int chown_cb(const char *p, void *c)
{
    struct chown_ctx *ctx = c;
    return do_chown_one(p, ctx->user, ctx->group);
}
static int chmod_cb(const char *p, void *c)
{
    return chmod(p, *(mode_t *)c);
}
static int write_cb(const char *p, void *c)
{
    return write_file(p, c);
}

static int run_and_wait(char **argv)
{
    pid_t pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        execve(argv[0], argv, init_environ());
        _exit(127);
    }
    int status;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
        ;
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

static int builtin(struct command *c)
{
    int argc = c->argc;
    char **argv = c->argv;
    const char *cmd = argv[0];

    if (!strcmp(cmd, "mkdir") && argc >= 2) {
        mode_t mode = argc >= 3 ? (mode_t)strtoul(argv[2], NULL, 8) : 0755;
        if (mkdir_p(argv[1], mode) < 0)
            return -1;
        chmod(argv[1], mode);
        if (argc >= 4)
            return do_chown_one(argv[1], argv[3], argc >= 5 ? argv[4] : NULL);
        return 0;
    }
    if (!strcmp(cmd, "chmod") && argc == 3) {
        mode_t mode = (mode_t)strtoul(argv[1], NULL, 8);
        return for_each_glob(argv[2], chmod_cb, &mode);
    }
    if (!strcmp(cmd, "chown") && (argc == 3 || argc == 4)) {
        struct chown_ctx ctx = {argv[1], argc == 4 ? argv[2] : NULL};
        return for_each_glob(argv[argc - 1], chown_cb, &ctx);
    }
    if (!strcmp(cmd, "write") && argc == 3)
        return for_each_glob(argv[1], write_cb, argv[2]);
    if (!strcmp(cmd, "symlink") && argc == 3) {
        unlink(argv[2]);
        return symlink(argv[1], argv[2]);
    }
    if (!strcmp(cmd, "rm") && argc == 2)
        return unlink(argv[1]);
    if (!strcmp(cmd, "setenv") && argc == 3) {
        init_setenv(argv[1], argv[2]);
        return 0;
    }
    if (!strcmp(cmd, "hostname") && argc == 2)
        return sethostname(argv[1], strlen(argv[1]));
    if (!strcmp(cmd, "exec") && argc >= 2) {
        int skip = !strcmp(argv[1], "--") ? 2 : 1;
        return run_and_wait(argv + skip);
    }
    if (!strcmp(cmd, "insmod") && argc >= 2) {
        int fd = open(argv[1], O_RDONLY | O_CLOEXEC);
        if (fd < 0)
            return -1;
        int r = (int)syscall(SYS_finit_module, fd, argc >= 3 ? argv[2] : "", 0);
        close(fd);
        return r;
    }
    if (!strcmp(cmd, "mount_all") && argc == 2) {
        struct fstab *fs = fstab_read(argv[1]);
        if (!fs)
            return -1;
        int ret = 0;
        for (int i = 0; i < fs->count; i++)
            if (!fs->entries[i].first_stage && fstab_mount(&fs->entries[i], "") < 0)
                ret = -1;
        fstab_free(fs);
        return ret;
    }
    if (!strcmp(cmd, "start") && argc == 2) {
        struct service *s = service_find(argv[1]);
        if (!s)
            return -1;
        service_start(s);
        return 0;
    }
    if (!strcmp(cmd, "stop") && argc == 2) {
        struct service *s = service_find(argv[1]);
        if (!s)
            return -1;
        service_stop(s);
        return 0;
    }
    if (!strcmp(cmd, "class_start") && argc == 2) {
        services_class_start(argv[1]);
        return 0;
    }
    if (!strcmp(cmd, "class_stop") && argc == 2) {
        services_class_stop(argv[1]);
        return 0;
    }
    if (!strcmp(cmd, "trigger") && argc == 2) {
        rc_trigger(argv[1]);
        return 0;
    }
    errno = EINVAL;
    return -2;
}

void rc_trigger(const char *trigger)
{
    INFO("processing action '%s'", trigger);
    for (struct action *a = actions; a; a = a->next) {
        if (strcmp(a->trigger, trigger))
            continue;
        for (int i = 0; i < a->ncmds; i++) {
            struct command *c = &a->cmds[i];
            int r = builtin(c);
            if (r == -2)
                ERR("%s:%d: unknown command '%s'", c->file, c->line, c->argv[0]);
            else if (r < 0)
                WARN("%s:%d: '%s' failed: %s", c->file, c->line, c->argv[0], strerror(errno));
        }
    }
}

void rc_dump(void)
{
    for (struct action *a = actions; a; a = a->next) {
        printf("on %s\n", a->trigger);
        for (int i = 0; i < a->ncmds; i++) {
            printf("   ");
            for (int j = 0; j < a->cmds[i].argc; j++)
                printf(" %s", a->cmds[i].argv[j]);
            printf("\n");
        }
    }
    for (struct service *s = service_list(); s; s = s->next) {
        printf("service %s (class %s, uid %u, gid %u, flags 0x%x):", s->name, s->klass, s->uid, s->gid, s->flags);
        for (char **a = s->argv; *a; a++)
            printf(" %s", *a);
        printf("\n");
    }
}
