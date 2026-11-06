/*
 * astraOS display test: draws through each path a program can use, and prints
 * what the kernel and the GPU answered, for phones whose screen stays black.
 *
 *   disptest gpu                        renders without a display, reads back
 *   disptest kms legacy|atomic HZ RGB   a CPU-filled buffer, page flips for 8 s
 *   disptest gl  legacy|atomic HZ RGB   the same through the GPU (as Qt does)
 *   disptest fb  plain|force RGB        writes to /dev/fb0
 *   disptest reinit                     initialises the panel once more (boot)
 *
 * Exit status 0 means every call succeeded: it says nothing about what the
 * panel shows, which only a person can see.
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <errno.h>
#include <fcntl.h>
#include <gbm.h>
#include <linux/fb.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#define SECONDS 8

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

static int fail(const char *what)
{
    printf("FAILED: %s: %s\n", what, strerror(errno));
    return 1;
}

/* ---- the display ------------------------------------------------------- */

struct output {
    int fd, atomic;
    uint32_t connector, crtc, plane, mode_blob;
    drmModeModeInfo mode;
    int flips_done, flip_timeouts;
    int waiting;
};

static uint32_t prop_id(int fd, uint32_t object, uint32_t type, const char *name)
{
    drmModeObjectProperties *props = drmModeObjectGetProperties(fd, object, type);
    uint32_t id = 0;
    for (uint32_t i = 0; props && i < props->count_props && !id; i++) {
        drmModePropertyRes *p = drmModeGetProperty(fd, props->props[i]);
        if (p && !strcmp(p->name, name))
            id = p->prop_id;
        drmModeFreeProperty(p);
    }
    drmModeFreeObjectProperties(props);
    if (!id)
        printf("no property %s on object %u\n", name, object);
    return id;
}

static int primary_plane(int fd, unsigned crtc_index)
{
    drmModePlaneRes *planes = drmModeGetPlaneResources(fd);
    int found = 0;
    for (uint32_t i = 0; planes && i < planes->count_planes && !found; i++) {
        drmModePlane *plane = drmModeGetPlane(fd, planes->planes[i]);
        drmModeObjectProperties *props = plane ? drmModeObjectGetProperties(fd, plane->plane_id, DRM_MODE_OBJECT_PLANE) : NULL;
        for (uint32_t j = 0; props && j < props->count_props; j++) {
            drmModePropertyRes *p = drmModeGetProperty(fd, props->props[j]);
            if (p && !strcmp(p->name, "type") && props->prop_values[j] == DRM_PLANE_TYPE_PRIMARY &&
                (plane->possible_crtcs & (1u << crtc_index)))
                found = (int)plane->plane_id;
            drmModeFreeProperty(p);
        }
        drmModeFreeObjectProperties(props);
        drmModeFreePlane(plane);
    }
    drmModeFreePlaneResources(planes);
    return found;
}

/* The card with a connected connector, and its mode closest to hz. */
static int output_open(struct output *o, int atomic, int hz)
{
    memset(o, 0, sizeof(*o));
    o->atomic = atomic;
    for (int n = 0; n < 4; n++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/dri/card%d", n);
        int fd = open(path, O_RDWR | O_CLOEXEC);
        if (fd < 0)
            continue;
        drmModeRes *res = drmModeGetResources(fd);
        for (int i = 0; res && i < res->count_connectors && !o->connector; i++) {
            drmModeConnector *c = drmModeGetConnector(fd, res->connectors[i]);
            if (c && c->connection == DRM_MODE_CONNECTED && c->count_modes > 0) {
                int best = 0;
                for (int m = 0; m < c->count_modes; m++) {
                    printf("mode %d: %s @ %u Hz\n", m, c->modes[m].name, c->modes[m].vrefresh);
                    if (abs((int)c->modes[m].vrefresh - hz) < abs((int)c->modes[best].vrefresh - hz))
                        best = m;
                }
                o->mode = c->modes[best];
                o->connector = c->connector_id;
                o->crtc = res->crtcs[0];
                o->fd = fd;
                printf("%s: connector %u, crtc %u, using %s @ %u Hz\n", path, o->connector, o->crtc, o->mode.name, o->mode.vrefresh);
            }
            drmModeFreeConnector(c);
        }
        drmModeFreeResources(res);
        if (o->connector)
            break;
        close(fd);
    }
    if (!o->connector) {
        printf("FAILED: no connected display\n");
        return -1;
    }
    if (drmSetMaster(o->fd) < 0)
        printf("drmSetMaster: %s\n", strerror(errno));
    if (atomic) {
        drmSetClientCap(o->fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1);
        if (drmSetClientCap(o->fd, DRM_CLIENT_CAP_ATOMIC, 1) < 0)
            return fail("the driver refuses atomic modesetting");
        o->plane = (uint32_t)primary_plane(o->fd, 0);
        printf("primary plane %u\n", o->plane);
        if (!o->plane || drmModeCreatePropertyBlob(o->fd, &o->mode, sizeof(o->mode), &o->mode_blob) < 0)
            return fail("no primary plane or mode blob");
    }
    return 0;
}

static void flip_done(int fd, unsigned seq, unsigned sec, unsigned usec, void *data)
{
    struct output *o = data;
    (void)fd; (void)seq; (void)sec; (void)usec;
    o->flips_done++;
    o->waiting = 0;
}

static int atomic_commit(struct output *o, uint32_t fb, uint32_t flags, void *data)
{
    drmModeAtomicReq *r = drmModeAtomicAlloc();
    int w = o->mode.hdisplay, h = o->mode.vdisplay;
    if (flags & DRM_MODE_ATOMIC_ALLOW_MODESET) {
        drmModeAtomicAddProperty(r, o->connector, prop_id(o->fd, o->connector, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID"), o->crtc);
        drmModeAtomicAddProperty(r, o->crtc, prop_id(o->fd, o->crtc, DRM_MODE_OBJECT_CRTC, "MODE_ID"), o->mode_blob);
        drmModeAtomicAddProperty(r, o->crtc, prop_id(o->fd, o->crtc, DRM_MODE_OBJECT_CRTC, "ACTIVE"), 1);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "CRTC_ID"), o->crtc);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "SRC_X"), 0);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "SRC_Y"), 0);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "SRC_W"), (uint64_t)w << 16);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "SRC_H"), (uint64_t)h << 16);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "CRTC_X"), 0);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "CRTC_Y"), 0);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "CRTC_W"), (uint64_t)w);
        drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "CRTC_H"), (uint64_t)h);
    }
    drmModeAtomicAddProperty(r, o->plane, prop_id(o->fd, o->plane, DRM_MODE_OBJECT_PLANE, "FB_ID"), fb);
    int ret = drmModeAtomicCommit(o->fd, r, flags, data);
    drmModeAtomicFree(r);
    return ret;
}

/* The first frame: sets the mode. */
static int output_show(struct output *o, uint32_t fb)
{
    double t = now();
    int ret = o->atomic ? atomic_commit(o, fb, DRM_MODE_ATOMIC_ALLOW_MODESET, NULL)
                        : drmModeSetCrtc(o->fd, o->crtc, fb, 0, 0, &o->connector, 1, &o->mode);
    printf("modeset: %s, %.0f ms\n", ret ? strerror(errno) : "ok", (now() - t) * 1000);
    return ret ? -1 : 0;
}

/* Later frames: asks for a flip and waits up to a second for the panel. */
static void output_flip(struct output *o, uint32_t fb)
{
    int ret = o->atomic ? atomic_commit(o, fb, DRM_MODE_ATOMIC_NONBLOCK | DRM_MODE_PAGE_FLIP_EVENT, o)
                        : drmModePageFlip(o->fd, o->crtc, fb, DRM_MODE_PAGE_FLIP_EVENT, o);
    if (ret) {
        printf("flip refused: %s\n", strerror(errno));
        usleep(100000);
        return;
    }
    o->waiting = 1;
    drmEventContext ev = {.version = 2, .page_flip_handler = flip_done};
    struct pollfd p = {.fd = o->fd, .events = POLLIN};
    if (poll(&p, 1, 1000) > 0)
        drmHandleEvent(o->fd, &ev);
    if (o->waiting) {
        o->flip_timeouts++;
        o->waiting = 0;
    }
}

static int output_report(struct output *o, double seconds)
{
    printf("flips completed: %d in %.1f s (%.1f per second), no answer from the display within 1 s: %d\n",
           o->flips_done, seconds, o->flips_done / seconds, o->flip_timeouts);
    return o->flips_done > 0 ? 0 : 1;
}

/* ---- a buffer filled by the CPU ---------------------------------------- */

static uint32_t dumb_buffer(struct output *o, uint32_t color)
{
    struct drm_mode_create_dumb create = {.width = o->mode.hdisplay, .height = o->mode.vdisplay, .bpp = 32};
    if (drmIoctl(o->fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) < 0) {
        fail("create dumb buffer");
        return 0;
    }
    struct drm_mode_map_dumb map = {.handle = create.handle};
    if (drmIoctl(o->fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0) {
        fail("map dumb buffer");
        return 0;
    }
    uint32_t *pixels = mmap(NULL, create.size, PROT_WRITE, MAP_SHARED, o->fd, (off_t)map.offset);
    if (pixels == MAP_FAILED) {
        fail("mmap dumb buffer");
        return 0;
    }
    for (uint64_t i = 0; i < create.size / 4; i++)
        pixels[i] = color;
    munmap(pixels, create.size);
    uint32_t fb = 0;
    if (drmModeAddFB(o->fd, create.width, create.height, 24, 32, create.pitch, create.handle, &fb) < 0)
        fail("add framebuffer");
    return fb;
}

static int test_kms(int atomic, int hz, uint32_t color)
{
    struct output o;
    if (output_open(&o, atomic, hz) < 0)
        return 1;
    uint32_t fb[2] = {dumb_buffer(&o, color), dumb_buffer(&o, color)};
    if (!fb[0] || !fb[1])
        return 1;
    if (output_show(&o, fb[0]) < 0)
        return 1;
    double start = now();
    for (int i = 1; now() - start < SECONDS; i++)
        output_flip(&o, fb[i & 1]);
    return output_report(&o, now() - start);
}

/*
 * A panel whose first initialisation, as the kernel starts, leaves it dark: a
 * modeset to another rate powers it down and up again, and closing the device
 * gives the display back to the kernel at its own rate, which is the one in use
 * from then on.
 */
static int panel_reinit(void)
{
    struct output o;
    int ret = -1;
    /* The display driver may still be probing. */
    for (int tries = 0; tries < 50 && ret < 0; tries++) {
        ret = access("/dev/dri/card0", F_OK) == 0 ? output_open(&o, 1, 60) : -1;
        if (ret < 0)
            usleep(100000);
    }
    if (ret < 0)
        return 1;
    uint32_t fb = dumb_buffer(&o, 0);
    if (!fb || output_show(&o, fb) < 0)
        return 1;
    for (int i = 0; i < 6; i++)
        output_flip(&o, fb);
    return output_report(&o, 0.1);
}

/* ---- through the GPU --------------------------------------------------- */

static const char VERTEX[] =
    "attribute vec2 pos;\nvarying vec2 uv;\n"
    "void main() { uv = pos * 0.5 + 0.5; gl_Position = vec4(pos, 0.0, 1.0); }\n";
static const char FRAGMENT[] =
    "precision mediump float;\nuniform vec3 color;\nuniform float phase;\nvarying vec2 uv;\n"
    "void main() { float d = 0.9 + 0.1 * sin(uv.x * 6.28 + phase); gl_FragColor = vec4(color * d, 1.0); }\n";

struct gl {
    EGLDisplay display;
    EGLContext context;
    EGLSurface surface;
    GLuint program;
};

static GLuint shader(GLenum type, const char *source)
{
    GLuint s = glCreateShader(type);
    glShaderSource(s, 1, &source, NULL);
    glCompileShader(s);
    GLint ok = 0;
    glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
    char log[512] = "";
    glGetShaderInfoLog(s, sizeof(log), NULL, log);
    printf("shader compiled: %s %s\n", ok ? "yes" : "NO", log);
    return s;
}

static int gl_open(struct gl *g, struct gbm_device *gbm, struct gbm_surface *window)
{
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_display = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
    g->display = get_display ? get_display(EGL_PLATFORM_GBM_KHR, gbm, NULL) : eglGetDisplay((EGLNativeDisplayType)gbm);
    EGLint major = 0, minor = 0;
    if (!eglInitialize(g->display, &major, &minor)) {
        printf("FAILED: eglInitialize: 0x%x\n", eglGetError());
        return -1;
    }
    eglBindAPI(EGL_OPENGL_ES_API);
    const EGLint want[] = {EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
                           EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 0, EGL_NONE};
    EGLConfig configs[64], config = NULL;
    EGLint count = 0;
    eglChooseConfig(g->display, want, configs, 64, &count);
    for (EGLint i = 0; i < count && !config; i++) {
        EGLint id = 0;
        eglGetConfigAttrib(g->display, configs[i], EGL_NATIVE_VISUAL_ID, &id);
        if ((uint32_t)id == GBM_FORMAT_XRGB8888)
            config = configs[i];
    }
    if (!config) {
        printf("FAILED: no XRGB8888 EGL config among %d\n", count);
        return -1;
    }
    const EGLint context_attrs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    g->context = eglCreateContext(g->display, config, EGL_NO_CONTEXT, context_attrs);
    g->surface = eglCreateWindowSurface(g->display, config, (EGLNativeWindowType)window, NULL);
    if (g->context == EGL_NO_CONTEXT || g->surface == EGL_NO_SURFACE ||
        !eglMakeCurrent(g->display, g->surface, g->surface, g->context)) {
        printf("FAILED: EGL context or surface: 0x%x\n", eglGetError());
        return -1;
    }
    printf("EGL %d.%d, GL_RENDERER: %s, GL_VERSION: %s\n", major, minor, glGetString(GL_RENDERER), glGetString(GL_VERSION));
    fflush(stdout);
    g->program = glCreateProgram();
    glAttachShader(g->program, shader(GL_VERTEX_SHADER, VERTEX));
    glAttachShader(g->program, shader(GL_FRAGMENT_SHADER, FRAGMENT));
    glBindAttribLocation(g->program, 0, "pos");
    glLinkProgram(g->program);
    glUseProgram(g->program);
    return 0;
}

static void gl_draw(struct gl *g, int w, int h, uint32_t color, float phase)
{
    static const GLfloat quad[] = {-1, -1, 1, -1, -1, 1, 1, 1};
    glViewport(0, 0, w, h);
    glUniform3f(glGetUniformLocation(g->program, "color"), (float)((color >> 16) & 255) / 255,
                (float)((color >> 8) & 255) / 255, (float)(color & 255) / 255);
    glUniform1f(glGetUniformLocation(g->program, "phase"), phase);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
    glEnableVertexAttribArray(0);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

/* Without a display: the shader compiles, the GPU draws, the pixels come back. */
static int test_gpu(void)
{
    int fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
    if (fd < 0)
        return fail("/dev/dri/renderD128");
    struct gbm_device *gbm = gbm_create_device(fd);
    struct gbm_surface *window = gbm ? gbm_surface_create(gbm, 64, 64, GBM_FORMAT_XRGB8888, GBM_BO_USE_RENDERING) : NULL;
    if (!window)
        return fail("gbm surface");
    struct gl g;
    if (gl_open(&g, gbm, window) < 0)
        return 1;
    gl_draw(&g, 64, 64, 0xff0000, 0);
    glFinish();
    unsigned char pixel[4] = {0};
    glReadPixels(32, 32, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    printf("GL error 0x%x, pixel read back: %u %u %u (a red about 230-255 means the GPU really drew)\n", glGetError(), pixel[0], pixel[1], pixel[2]);
    return pixel[0] > 200 && pixel[1] < 30 && pixel[2] < 30 ? 0 : 1;
}

static int test_gl(int atomic, int hz, uint32_t color)
{
    struct output o;
    if (output_open(&o, atomic, hz) < 0)
        return 1;
    int w = o.mode.hdisplay, h = o.mode.vdisplay;
    struct gbm_device *gbm = gbm_create_device(o.fd);
    struct gbm_surface *window = gbm ? gbm_surface_create(gbm, (uint32_t)w, (uint32_t)h, GBM_FORMAT_XRGB8888,
                                                          GBM_BO_USE_SCANOUT | GBM_BO_USE_RENDERING) : NULL;
    if (!window)
        return fail("gbm scanout surface");
    struct gl g;
    if (gl_open(&g, gbm, window) < 0)
        return 1;

    struct gbm_bo *current = NULL;
    double start = now();
    for (int frame = 0; frame == 0 || now() - start < SECONDS; frame++) {
        gl_draw(&g, w, h, color, (float)frame * 0.1f);
        if (!eglSwapBuffers(g.display, g.surface)) {
            printf("FAILED: eglSwapBuffers: 0x%x\n", eglGetError());
            return 1;
        }
        struct gbm_bo *bo = gbm_surface_lock_front_buffer(window);
        if (!bo)
            return fail("gbm_surface_lock_front_buffer");
        uint32_t handles[4] = {gbm_bo_get_handle(bo).u32}, pitches[4] = {gbm_bo_get_stride(bo)}, offsets[4] = {0}, fb = 0;
        uint64_t modifiers[4] = {gbm_bo_get_modifier(bo)};
        if (frame == 0)
            printf("buffer: stride %u, modifier 0x%llx\n", pitches[0], (unsigned long long)modifiers[0]);
        int ret = drmModeAddFB2WithModifiers(o.fd, (uint32_t)w, (uint32_t)h, GBM_FORMAT_XRGB8888, handles, pitches, offsets,
                                             modifiers, &fb, modifiers[0] != DRM_FORMAT_MOD_INVALID ? DRM_MODE_FB_MODIFIERS : 0);
        if (ret)
            ret = drmModeAddFB(o.fd, (uint32_t)w, (uint32_t)h, 24, 32, pitches[0], handles[0], &fb);
        if (ret)
            return fail("add framebuffer");
        if (frame == 0) {
            if (output_show(&o, fb) < 0)
                return 1;
            start = now();
        } else {
            output_flip(&o, fb);
        }
        if (current)
            gbm_surface_release_buffer(window, current);
        current = bo;
    }
    return output_report(&o, now() - start);
}

/* ---- the framebuffer --------------------------------------------------- */

static int test_fb(int force, uint32_t color)
{
    int fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
    if (fd < 0)
        return fail("/dev/fb0");
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    if (ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0 || ioctl(fd, FBIOGET_FSCREENINFO, &fix) < 0)
        return fail("framebuffer info");
    printf("fb0: %ux%u, %u bits, line %u, %s\n", var.xres, var.yres, var.bits_per_pixel, fix.line_length, fix.id);
    uint32_t *pixels = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED)
        return fail("mmap framebuffer");
    for (uint32_t i = 0; i < fix.smem_len / 4; i++)
        pixels[i] = color;
    if (force) {
        var.activate = FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE;
        if (ioctl(fd, FBIOPUT_VSCREENINFO, &var) < 0)
            return fail("forced refresh");
        printf("forced refresh: ok\n");
    }
    fflush(stdout);
    sleep(SECONDS);
    return 0;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc == 2 && !strcmp(argv[1], "gpu"))
        return test_gpu();
    if (argc == 2 && !strcmp(argv[1], "reinit"))
        return panel_reinit();
    if (argc == 4 && !strcmp(argv[1], "fb"))
        return test_fb(!strcmp(argv[2], "force"), (uint32_t)strtoul(argv[3], NULL, 16));
    if (argc == 5 && (!strcmp(argv[1], "kms") || !strcmp(argv[1], "gl"))) {
        int atomic = !strcmp(argv[2], "atomic"), hz = atoi(argv[3]);
        uint32_t color = (uint32_t)strtoul(argv[4], NULL, 16);
        return !strcmp(argv[1], "kms") ? test_kms(atomic, hz, color) : test_gl(atomic, hz, color);
    }
    fprintf(stderr, "usage: disptest gpu | reinit | kms legacy|atomic HZ RGB | gl legacy|atomic HZ RGB | fb plain|force RGB\n");
    return 2;
}
