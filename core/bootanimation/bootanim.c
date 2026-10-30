/*
 * astraOS boot animation
 *
 * Shows the astra logo, centered on a black background, from early boot
 * until SysBoard takes over the display. Draws straight to a KMS dumb
 * buffer (no GPU needed); falls back to /dev/fb0 on fbdev-only kernels.
 *
 * Configuration: /system/media/bootanimation/desc.txt
 *   logo <file>                 (relative to the desc.txt directory)
 *   background #RRGGBB
 *   logo_width_percent <1-100>  (logo width relative to the screen width)
 *
 * Control: writing "stop" to /run/astra/bootanim.ctl (a FIFO) fades the logo
 * out, releases the display and exits. The FIFO disappears right before exit.
 *
 * Testing: bootanim --dump out.ppm <width> <height>
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <png.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#define DEFAULT_DESC "/system/media/bootanimation/desc.txt"
#define CONTROL_FIFO "/run/astra/bootanim.ctl"

struct config {
    char logo[1024];
    uint32_t background;
    int logo_width_percent;
};

struct image {
    int width, height;
    uint8_t *rgba;
};

struct surface {
    int width, height, stride; /* stride in bytes, XRGB8888 */
    uint8_t *pixels;
    /* DRM state */
    int drm_fd;
    uint32_t fb_id, crtc_id, conn_id, handle;
    uint64_t size;
    drmModeModeInfo mode;
    drmModeCrtc *saved_crtc;
    /* fbdev state */
    int fb_fd;
};

static volatile sig_atomic_t stop_requested;

static void on_signal(int sig)
{
    (void)sig;
    stop_requested = 1;
}

static void load_config(const char *desc_path, struct config *cfg)
{
    char dir[512];
    snprintf(dir, sizeof(dir), "%s", desc_path);
    char *slash = strrchr(dir, '/');
    if (slash)
        *slash = '\0';
    else
        strcpy(dir, ".");

    snprintf(cfg->logo, sizeof(cfg->logo), "%s/logo.png", dir);
    cfg->background = 0x000000;
    cfg->logo_width_percent = 50;

    FILE *f = fopen(desc_path, "r");
    if (!f)
        return;
    char line[600], key[64], value[512];
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == '#' || sscanf(line, "%63s %511s", key, value) != 2)
            continue;
        if (!strcmp(key, "logo"))
            snprintf(cfg->logo, sizeof(cfg->logo), "%s/%s", dir, value);
        else if (!strcmp(key, "background") && value[0] == '#')
            cfg->background = (uint32_t)strtoul(value + 1, NULL, 16);
        else if (!strcmp(key, "logo_width_percent"))
            cfg->logo_width_percent = atoi(value);
    }
    fclose(f);
    if (cfg->logo_width_percent < 1 || cfg->logo_width_percent > 100)
        cfg->logo_width_percent = 50;
}

static int load_png(const char *path, struct image *img)
{
    png_image png;
    memset(&png, 0, sizeof(png));
    png.version = PNG_IMAGE_VERSION;
    if (!png_image_begin_read_from_file(&png, path)) {
        fprintf(stderr, "bootanim: cannot read %s: %s\n", path, png.message);
        return -1;
    }
    png.format = PNG_FORMAT_RGBA;
    img->rgba = malloc(PNG_IMAGE_SIZE(png));
    if (!img->rgba || !png_image_finish_read(&png, NULL, img->rgba, 0, NULL)) {
        png_image_free(&png);
        free(img->rgba);
        return -1;
    }
    img->width = (int)png.width;
    img->height = (int)png.height;
    return 0;
}

/* Bilinear sample of the logo at (u, v) in source pixel space. */
static void sample(const struct image *img, float u, float v, float out[4])
{
    int x0 = (int)u, y0 = (int)v;
    float fx = u - (float)x0, fy = v - (float)y0;
    int x1 = x0 + 1 < img->width ? x0 + 1 : x0;
    int y1 = y0 + 1 < img->height ? y0 + 1 : y0;
    const uint8_t *p00 = img->rgba + 4 * (y0 * img->width + x0);
    const uint8_t *p10 = img->rgba + 4 * (y0 * img->width + x1);
    const uint8_t *p01 = img->rgba + 4 * (y1 * img->width + x0);
    const uint8_t *p11 = img->rgba + 4 * (y1 * img->width + x1);
    for (int c = 0; c < 4; c++) {
        float top = p00[c] + (p10[c] - p00[c]) * fx;
        float bottom = p01[c] + (p11[c] - p01[c]) * fx;
        out[c] = top + (bottom - top) * fy;
    }
}

/* Renders background + centered logo. intensity fades the logo (0..1). */
static void render(struct surface *s, const struct config *cfg, const struct image *logo, float intensity)
{
    uint8_t br = (cfg->background >> 16) & 0xff, bg = (cfg->background >> 8) & 0xff, bb = cfg->background & 0xff;
    for (int y = 0; y < s->height; y++) {
        uint32_t *row = (uint32_t *)(s->pixels + y * s->stride);
        for (int x = 0; x < s->width; x++)
            row[x] = (uint32_t)(br << 16 | bg << 8 | bb);
    }
    if (!logo->rgba)
        return;

    int dw = s->width * cfg->logo_width_percent / 100;
    int dh = dw * logo->height / logo->width;
    int ox = (s->width - dw) / 2, oy = (s->height - dh) / 2;
    float scale = (float)logo->width / (float)dw;

    for (int y = 0; y < dh; y++) {
        uint32_t *row = (uint32_t *)(s->pixels + (oy + y) * s->stride);
        float v = ((float)y + 0.5f) * scale - 0.5f;
        if (v < 0)
            v = 0;
        for (int x = 0; x < dw; x++) {
            float u = ((float)x + 0.5f) * scale - 0.5f, px[4];
            if (u < 0)
                u = 0;
            sample(logo, u, v, px);
            float a = px[3] / 255.0f * intensity;
            uint8_t r = (uint8_t)(px[0] * a + br * (1 - a));
            uint8_t g = (uint8_t)(px[1] * a + bg * (1 - a));
            uint8_t b = (uint8_t)(px[2] * a + bb * (1 - a));
            row[ox + x] = (uint32_t)(r << 16 | g << 8 | b);
        }
    }
}

/* ---- KMS -------------------------------------------------------------- */

static int drm_open(struct surface *s)
{
    for (int card = 0; card < 4; card++) {
        char path[32];
        snprintf(path, sizeof(path), "/dev/dri/card%d", card);
        int fd = open(path, O_RDWR | O_CLOEXEC);
        if (fd < 0)
            continue;
        drmModeRes *res = drmModeGetResources(fd);
        if (!res) {
            close(fd);
            continue;
        }
        for (int i = 0; i < res->count_connectors; i++) {
            drmModeConnector *conn = drmModeGetConnector(fd, res->connectors[i]);
            if (!conn)
                continue;
            if (conn->connection != DRM_MODE_CONNECTED || conn->count_modes == 0) {
                drmModeFreeConnector(conn);
                continue;
            }
            s->mode = conn->modes[0];
            for (int m = 0; m < conn->count_modes; m++)
                if (conn->modes[m].type & DRM_MODE_TYPE_PREFERRED)
                    s->mode = conn->modes[m];

            uint32_t crtc = 0;
            drmModeEncoder *enc = conn->encoder_id ? drmModeGetEncoder(fd, conn->encoder_id) : NULL;
            if (enc && enc->crtc_id)
                crtc = enc->crtc_id;
            for (int e = 0; !crtc && e < conn->count_encoders; e++) {
                drmModeEncoder *cand = drmModeGetEncoder(fd, conn->encoders[e]);
                for (int c = 0; cand && c < res->count_crtcs; c++)
                    if (cand->possible_crtcs & (1u << c)) {
                        crtc = res->crtcs[c];
                        break;
                    }
                drmModeFreeEncoder(cand);
            }
            drmModeFreeEncoder(enc);
            s->conn_id = conn->connector_id;
            drmModeFreeConnector(conn);
            if (!crtc)
                continue;

            s->crtc_id = crtc;
            s->drm_fd = fd;
            s->width = s->mode.hdisplay;
            s->height = s->mode.vdisplay;
            drmModeFreeResources(res);

            struct drm_mode_create_dumb creq = {.width = (uint32_t)s->width, .height = (uint32_t)s->height, .bpp = 32};
            if (drmIoctl(fd, DRM_IOCTL_MODE_CREATE_DUMB, &creq) < 0)
                goto fail;
            s->handle = creq.handle;
            s->stride = (int)creq.pitch;
            s->size = creq.size;
            if (drmModeAddFB(fd, (uint32_t)s->width, (uint32_t)s->height, 24, 32, creq.pitch, creq.handle, &s->fb_id))
                goto fail;
            struct drm_mode_map_dumb mreq = {.handle = creq.handle};
            if (drmIoctl(fd, DRM_IOCTL_MODE_MAP_DUMB, &mreq) < 0)
                goto fail;
            s->pixels = mmap(NULL, s->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, (off_t)mreq.offset);
            if (s->pixels == MAP_FAILED)
                goto fail;
            s->saved_crtc = drmModeGetCrtc(fd, crtc);
            return 0;
        fail:
            fprintf(stderr, "bootanim: dumb buffer setup failed: %s\n", strerror(errno));
            close(fd);
            return -1;
        }
        drmModeFreeResources(res);
        close(fd);
    }
    return -1;
}

static void drm_present(struct surface *s, int first)
{
    if (first && drmModeSetCrtc(s->drm_fd, s->crtc_id, s->fb_id, 0, 0, &s->conn_id, 1, &s->mode))
        fprintf(stderr, "bootanim: set crtc failed: %s\n", strerror(errno));
    /* Command-mode DSI panels only refresh on an explicit flush. */
    drmModeDirtyFB(s->drm_fd, s->fb_id, NULL, 0);
}

static void drm_close(struct surface *s)
{
    drmDropMaster(s->drm_fd);
    munmap(s->pixels, s->size);
    drmModeRmFB(s->drm_fd, s->fb_id);
    struct drm_mode_destroy_dumb dreq = {.handle = s->handle};
    drmIoctl(s->drm_fd, DRM_IOCTL_MODE_DESTROY_DUMB, &dreq);
    drmModeFreeCrtc(s->saved_crtc);
    close(s->drm_fd);
}

/* ---- fbdev fallback ---------------------------------------------------- */

static int fb_open(struct surface *s)
{
    int fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
    if (fd < 0)
        return -1;
    struct fb_var_screeninfo var;
    struct fb_fix_screeninfo fix;
    if (ioctl(fd, FBIOGET_VSCREENINFO, &var) < 0 || ioctl(fd, FBIOGET_FSCREENINFO, &fix) < 0 ||
        var.bits_per_pixel != 32) {
        close(fd);
        return -1;
    }
    s->fb_fd = fd;
    s->width = (int)var.xres;
    s->height = (int)var.yres;
    s->stride = (int)fix.line_length;
    s->size = (uint64_t)fix.smem_len;
    s->pixels = mmap(NULL, s->size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (s->pixels == MAP_FAILED) {
        close(fd);
        return -1;
    }
    return 0;
}

/* ---- main ------------------------------------------------------------- */

static int dump(const struct config *cfg, const struct image *logo, const char *out, int w, int h)
{
    struct surface s = {.width = w, .height = h, .stride = w * 4};
    s.pixels = calloc((size_t)h, (size_t)s.stride);
    render(&s, cfg, logo, 1.0f);
    FILE *f = fopen(out, "wb");
    if (!f)
        return 1;
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    for (int i = 0; i < w * h; i++) {
        uint32_t p = ((uint32_t *)s.pixels)[i];
        uint8_t rgb[3] = {(uint8_t)(p >> 16), (uint8_t)(p >> 8), (uint8_t)p};
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
    free(s.pixels);
    return 0;
}

static int open_control(void)
{
    mkdir("/run/astra", 0755);
    unlink(CONTROL_FIFO);
    if (mkfifo(CONTROL_FIFO, 0620) < 0)
        return -1;
    chown(CONTROL_FIFO, 0, 1000); /* writable by the system user (SysBoard) */
    /* O_RDWR keeps a writer around so poll() does not spin on EOF. */
    return open(CONTROL_FIFO, O_RDWR | O_NONBLOCK | O_CLOEXEC);
}

int main(int argc, char **argv)
{
    const char *desc = getenv("BOOTANIM_DESC") ? getenv("BOOTANIM_DESC") : DEFAULT_DESC;
    struct config cfg;
    struct image logo = {0};
    load_config(desc, &cfg);
    load_png(cfg.logo, &logo);

    if (argc == 5 && !strcmp(argv[1], "--dump"))
        return dump(&cfg, &logo, argv[2], atoi(argv[3]), atoi(argv[4]));

    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);

    struct surface s = {.drm_fd = -1, .fb_fd = -1};
    /* Started as soon as /dev exists: the display driver (and its panel)
     * may still be probing, so give it a few seconds. */
    int use_drm = 0;
    for (int tries = 0; tries < 80 && !stop_requested; tries++) {
        if ((use_drm = drm_open(&s) == 0))
            break;
        usleep(100000);
    }
    if (!use_drm && fb_open(&s) < 0) {
        fprintf(stderr, "bootanim: no display available\n");
        return 1;
    }

    render(&s, &cfg, &logo, 1.0f);
    if (use_drm)
        drm_present(&s, 1);

    int ctl = open_control();
    while (!stop_requested) {
        struct pollfd pfd = {.fd = ctl, .events = POLLIN};
        if (poll(&pfd, ctl >= 0 ? 1 : 0, ctl >= 0 ? -1 : 1000) > 0) {
            char buf[32];
            ssize_t n = read(ctl, buf, sizeof(buf) - 1);
            if (n > 0) {
                buf[n] = '\0';
                if (strstr(buf, "stop"))
                    stop_requested = 1;
            }
        }
    }

    /* Short fade-out so the hand-over to SysBoard does not look like a cut. */
    for (int step = 9; step >= 0; step--) {
        render(&s, &cfg, &logo, (float)step / 10.0f);
        if (use_drm)
            drm_present(&s, 0);
        usleep(16000);
    }

    if (use_drm)
        drm_close(&s);
    else {
        munmap(s.pixels, s.size);
        close(s.fb_fd);
    }
    unlink(CONTROL_FIFO);
    free(logo.rgba);
    return 0;
}
