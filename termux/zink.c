#define _GNU_SOURCE
#include "termux/zink.h"

#include "termux/ahb.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <drm_fourcc.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <scenefx/render/fx_renderer/fx_renderer.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/util/log.h>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif
#ifndef EGL_NO_CONFIG_KHR
#define EGL_NO_CONFIG_KHR ((EGLConfig)0)
#endif
#ifndef EGL_OPENGL_ES2_BIT
#define EGL_OPENGL_ES2_BIT 0x0004
#endif

static EGLDisplay zink_display = EGL_NO_DISPLAY;
static EGLConfig zink_config = EGL_NO_CONFIG_KHR;
static PFNEGLCREATEIMAGEKHRPROC zink_create_image;
static bool zink_active;

static void set_default_env(const char *name, const char *value) {
	if (getenv(name) == NULL) {
		setenv(name, value, 1);
	}
}

static void set_zink_env(void) {
	const char *prefix = getenv("PREFIX");
	if (prefix == NULL || prefix[0] == '\0') {
		prefix = "/data/data/com.termux/files/usr";
	}

	char icd[PATH_MAX];
	int len = snprintf(icd, sizeof(icd),
		"%s/share/vulkan/icd.d/freedreno_icd.aarch64.json", prefix);
	if (len > 0 && (size_t)len < sizeof(icd) && access(icd, R_OK) == 0) {
		set_default_env("VK_ICD_FILENAMES", icd);
	}

	set_default_env("MESA_LOADER_DRIVER_OVERRIDE", "zink");
	set_default_env("GALLIUM_DRIVER", "zink");
	set_default_env("EGL_PLATFORM", "surfaceless");
}

static EGLImageKHR zink_ahb_egl_image(struct wlr_buffer *wlr_buffer) {
	struct wlr_dmabuf_attributes dmabuf = {0};
	if (!termux_ahb_buffer_get_dmabuf(wlr_buffer, &dmabuf)) {
		return EGL_NO_IMAGE_KHR;
	}
	if (zink_display == EGL_NO_DISPLAY || zink_create_image == NULL) {
		return EGL_NO_IMAGE_KHR;
	}

	EGLint attribs[50];
	unsigned int atti = 0;
	attribs[atti++] = EGL_WIDTH;
	attribs[atti++] = dmabuf.width;
	attribs[atti++] = EGL_HEIGHT;
	attribs[atti++] = dmabuf.height;
	attribs[atti++] = EGL_LINUX_DRM_FOURCC_EXT;
	attribs[atti++] = dmabuf.format;

	struct {
		EGLint fd;
		EGLint offset;
		EGLint pitch;
		EGLint mod_lo;
		EGLint mod_hi;
	} attr_names[WLR_DMABUF_MAX_PLANES] = {
		{
			EGL_DMA_BUF_PLANE0_FD_EXT,
			EGL_DMA_BUF_PLANE0_OFFSET_EXT,
			EGL_DMA_BUF_PLANE0_PITCH_EXT,
			EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
			EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT
		}, {
			EGL_DMA_BUF_PLANE1_FD_EXT,
			EGL_DMA_BUF_PLANE1_OFFSET_EXT,
			EGL_DMA_BUF_PLANE1_PITCH_EXT,
			EGL_DMA_BUF_PLANE1_MODIFIER_LO_EXT,
			EGL_DMA_BUF_PLANE1_MODIFIER_HI_EXT
		}, {
			EGL_DMA_BUF_PLANE2_FD_EXT,
			EGL_DMA_BUF_PLANE2_OFFSET_EXT,
			EGL_DMA_BUF_PLANE2_PITCH_EXT,
			EGL_DMA_BUF_PLANE2_MODIFIER_LO_EXT,
			EGL_DMA_BUF_PLANE2_MODIFIER_HI_EXT
		}, {
			EGL_DMA_BUF_PLANE3_FD_EXT,
			EGL_DMA_BUF_PLANE3_OFFSET_EXT,
			EGL_DMA_BUF_PLANE3_PITCH_EXT,
			EGL_DMA_BUF_PLANE3_MODIFIER_LO_EXT,
			EGL_DMA_BUF_PLANE3_MODIFIER_HI_EXT
		}
	};

	for (int i = 0; i < dmabuf.n_planes; i++) {
		attribs[atti++] = attr_names[i].fd;
		attribs[atti++] = dmabuf.fd[i];
		attribs[atti++] = attr_names[i].offset;
		attribs[atti++] = dmabuf.offset[i];
		attribs[atti++] = attr_names[i].pitch;
		attribs[atti++] = dmabuf.stride[i];
		if (dmabuf.modifier != DRM_FORMAT_MOD_INVALID) {
			attribs[atti++] = attr_names[i].mod_lo;
			attribs[atti++] = dmabuf.modifier & 0xFFFFFFFF;
			attribs[atti++] = attr_names[i].mod_hi;
			attribs[atti++] = dmabuf.modifier >> 32;
		}
	}

	attribs[atti++] = EGL_IMAGE_PRESERVED_KHR;
	attribs[atti++] = EGL_TRUE;
	attribs[atti++] = EGL_NONE;

	return zink_create_image(zink_display, EGL_NO_CONTEXT,
		EGL_LINUX_DMA_BUF_EXT, NULL, attribs);
}

static bool zink_egl_init(void) {
	set_zink_env();

	zink_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (zink_display == EGL_NO_DISPLAY) {
		wlr_log(WLR_ERROR, "Zink: eglGetDisplay failed");
		return false;
	}

	EGLint major, minor;
	if (!eglInitialize(zink_display, &major, &minor)) {
		wlr_log(WLR_ERROR, "Zink: eglInitialize failed: 0x%x",
			eglGetError());
		zink_display = EGL_NO_DISPLAY;
		return false;
	}

	const char *vendor = eglQueryString(zink_display, EGL_VENDOR);
	wlr_log(WLR_INFO, "Zink: EGL %d.%d (%s)", major, minor,
		vendor ? vendor : "unknown");

	const char *exts = eglQueryString(zink_display, EGL_EXTENSIONS);
	if (exts == NULL || strstr(exts, "EGL_EXT_image_dma_buf_import") == NULL) {
		wlr_log(WLR_ERROR,
			"Zink: EGL_EXT_image_dma_buf_import is not supported");
		eglTerminate(zink_display);
		zink_display = EGL_NO_DISPLAY;
		return false;
	}

	if (!eglBindAPI(EGL_OPENGL_ES_API)) {
		wlr_log(WLR_ERROR, "Zink: eglBindAPI failed: 0x%x", eglGetError());
		eglTerminate(zink_display);
		zink_display = EGL_NO_DISPLAY;
		return false;
	}

	const EGLint config_attribs[] = {
		EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8,
		EGL_GREEN_SIZE, 8,
		EGL_BLUE_SIZE, 8,
		EGL_ALPHA_SIZE, 8,
		EGL_NONE,
	};
	EGLint n = 0;
	if (eglChooseConfig(zink_display, config_attribs, &zink_config, 1, &n) &&
			n > 0) {
		wlr_log(WLR_INFO, "Zink: using EGL config");
	} else {
		zink_config = EGL_NO_CONFIG_KHR;
		wlr_log(WLR_INFO, "Zink: using configless EGL context");
	}

	zink_create_image = (PFNEGLCREATEIMAGEKHRPROC)
		eglGetProcAddress("eglCreateImageKHR");
	if (zink_create_image == NULL) {
		wlr_log(WLR_ERROR, "Zink: eglCreateImageKHR is unavailable");
		eglTerminate(zink_display);
		zink_display = EGL_NO_DISPLAY;
		return false;
	}

	return true;
}

struct wlr_renderer *termux_zink_renderer_create(void) {
	zink_active = false;

	if (!zink_egl_init()) {
		return NULL;
	}

	const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE,
	};
	EGLContext context = eglCreateContext(zink_display, zink_config,
		EGL_NO_CONTEXT, context_attribs);
	if (context == EGL_NO_CONTEXT) {
		wlr_log(WLR_ERROR, "Zink: eglCreateContext failed: 0x%x",
			eglGetError());
		eglTerminate(zink_display);
		zink_display = EGL_NO_DISPLAY;
		return NULL;
	}

	fx_renderer_set_buffer_egl_image_provider(zink_ahb_egl_image);

	struct wlr_renderer *renderer =
		fx_renderer_create_with_egl(zink_display, context);
	if (renderer == NULL) {
		wlr_log(WLR_ERROR, "Zink: FX renderer creation failed");
		fx_renderer_set_buffer_egl_image_provider(NULL);
		return NULL;
	}

	zink_active = true;
	return renderer;
}

bool termux_zink_active(void) {
	return zink_active;
}
