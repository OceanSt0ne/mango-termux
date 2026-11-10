#define _GNU_SOURCE
#include "termux/ahb.h"

#include <drm_fourcc.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdlib.h>

#include <scenefx/render/fx_renderer/fx_renderer.h>
#include <wlr/interfaces/wlr_buffer.h>
#include <wlr/render/allocator.h>
#include <wlr/render/drm_format_set.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/types/wlr_buffer.h>
#include <wlr/util/log.h>

/*
 * Declare the small subset of the NDK AHardwareBuffer API we need locally.
 * The NDK headers mark these as unavailable below API 26, but Termux targets
 * an older API level while running on a modern Android release.
 */
typedef struct AHardwareBuffer AHardwareBuffer;

typedef struct AHardwareBuffer_Desc {
	uint32_t width;
	uint32_t height;
	uint32_t layers;
	uint32_t format;
	uint64_t usage;
	uint32_t stride;
	uint32_t rfu0;
	uint64_t rfu1;
} AHardwareBuffer_Desc;

enum {
	AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN = 3,
	AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN = 3 << 4,
	AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE = 1 << 8,
	AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER = 1 << 9,
};

int AHardwareBuffer_allocate(const AHardwareBuffer_Desc *desc,
	AHardwareBuffer **buffer);
void AHardwareBuffer_describe(const AHardwareBuffer *buffer,
	AHardwareBuffer_Desc *out_desc);
void AHardwareBuffer_release(AHardwareBuffer *buffer);
int AHardwareBuffer_lock(AHardwareBuffer *buffer, uint64_t usage,
	int32_t fence, void *rect, void **out_virtual_address);
int AHardwareBuffer_unlock(AHardwareBuffer *buffer, int32_t *fence);

#ifndef EGL_NATIVE_BUFFER_ANDROID
#define EGL_NATIVE_BUFFER_ANDROID 0x3140
#endif
#ifndef EGL_NO_CONFIG_KHR
#define EGL_NO_CONFIG_KHR ((EGLConfig)0)
#endif
#ifndef EGL_OPENGL_ES2_BIT
#define EGL_OPENGL_ES2_BIT 0x0004
#endif

/* Not present in some NDK header versions. */
#define AHB_FORMAT_BGRA 5
#define AHB_FORMAT_RGBA 1

struct ahb_native_handle {
	int version;
	int numFds;
	int numInts;
	int data[];
};

extern const struct ahb_native_handle *AHardwareBuffer_getNativeHandle(
	const AHardwareBuffer *buffer);

typedef EGLClientBuffer (*ahb_get_native_client_buffer_proc)(
	const AHardwareBuffer *buffer);

struct ahb_buffer {
	struct wlr_buffer base;
	AHardwareBuffer *ahb;
	int fd;
	uint32_t drm_format;
	uint32_t stride;
	void *data;
	bool locked;
};

struct ahb_allocator {
	struct wlr_allocator base;
};

static EGLDisplay egl_display = EGL_NO_DISPLAY;
static EGLConfig egl_config = EGL_NO_CONFIG_KHR;
static ahb_get_native_client_buffer_proc get_native_client_buffer;
static PFNEGLCREATEIMAGEKHRPROC create_image;
static bool ahb_active;

static const struct wlr_buffer_impl ahb_buffer_impl;

static bool ahb_buffer_is_ours(struct wlr_buffer *buffer) {
	return buffer->impl == &ahb_buffer_impl;
}

static bool drm_to_ahb(uint32_t drm_format, uint32_t *ahb_format) {
	switch (drm_format) {
	case DRM_FORMAT_XRGB8888:
	case DRM_FORMAT_ARGB8888:
		*ahb_format = AHB_FORMAT_BGRA;
		return true;
	case DRM_FORMAT_XBGR8888:
	case DRM_FORMAT_ABGR8888:
		*ahb_format = AHB_FORMAT_RGBA;
		return true;
	default:
		return false;
	}
}

static EGLImageKHR ahb_egl_image(struct wlr_buffer *wlr_buffer) {
	if (!ahb_buffer_is_ours(wlr_buffer)) {
		return EGL_NO_IMAGE_KHR;
	}

	struct ahb_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
	if (get_native_client_buffer == NULL || create_image == NULL) {
		return EGL_NO_IMAGE_KHR;
	}

	EGLClientBuffer client_buffer = get_native_client_buffer(buffer->ahb);
	if (client_buffer == NULL) {
		return EGL_NO_IMAGE_KHR;
	}

	const EGLint attribs[] = {
		EGL_IMAGE_PRESERVED_KHR, EGL_TRUE,
		EGL_NONE,
	};
	return create_image(egl_display, EGL_NO_CONTEXT,
		EGL_NATIVE_BUFFER_ANDROID, client_buffer, attribs);
}

static void ahb_buffer_destroy(struct wlr_buffer *wlr_buffer) {
	struct ahb_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
	AHardwareBuffer_release(buffer->ahb);
	free(buffer);
}

static bool ahb_buffer_get_dmabuf(struct wlr_buffer *wlr_buffer,
		struct wlr_dmabuf_attributes *attribs) {
	/* Present through the SHM path: the AHardwareBuffer fd is mappable. */
	return false;
}

static bool ahb_buffer_get_shm(struct wlr_buffer *wlr_buffer,
		struct wlr_shm_attributes *attribs) {
	struct ahb_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
	attribs->fd = buffer->fd;
	attribs->format = buffer->drm_format;
	/*
	 * xcb_shm_create_pixmap() only accepts buffers whose stride is exactly
	 * width * bytes-per-pixel. AHardwareBuffer pads the stride (e.g. 1280
	 * pixels for a 1024 pixel wide buffer), so report the padded width to
	 * the X11 backend. The compositor still renders/scales into the real
	 * buffer width; the extra columns are simply cropped by the X server.
	 */
	attribs->width = buffer->stride / 4;
	attribs->height = wlr_buffer->height;
	attribs->stride = buffer->stride;
	attribs->offset = 0;
	return true;
}

static bool ahb_buffer_begin_data_ptr_access(struct wlr_buffer *wlr_buffer,
		uint32_t flags, void **data, uint32_t *format, size_t *stride) {
	struct ahb_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);

	uint64_t usage = 0;
	if (flags & WLR_BUFFER_DATA_PTR_ACCESS_READ) {
		usage |= AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN;
	}
	if (flags & WLR_BUFFER_DATA_PTR_ACCESS_WRITE) {
		usage |= AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN;
	}

	int ret = AHardwareBuffer_lock(buffer->ahb, usage, -1, NULL,
		&buffer->data);
	if (ret != 0 || buffer->data == NULL) {
		wlr_log(WLR_ERROR, "AHardwareBuffer_lock failed: %d", ret);
		return false;
	}

	buffer->locked = true;
	*data = buffer->data;
	*format = buffer->drm_format;
	*stride = buffer->stride;
	return true;
}

static void ahb_buffer_end_data_ptr_access(struct wlr_buffer *wlr_buffer) {
	struct ahb_buffer *buffer = wl_container_of(wlr_buffer, buffer, base);
	if (buffer->locked) {
		AHardwareBuffer_unlock(buffer->ahb, NULL);
		buffer->locked = false;
		buffer->data = NULL;
	}
}

static const struct wlr_buffer_impl ahb_buffer_impl = {
	.destroy = ahb_buffer_destroy,
	.get_dmabuf = ahb_buffer_get_dmabuf,
	.get_shm = ahb_buffer_get_shm,
	.begin_data_ptr_access = ahb_buffer_begin_data_ptr_access,
	.end_data_ptr_access = ahb_buffer_end_data_ptr_access,
};

static struct wlr_buffer *ahb_allocator_create_buffer(
		struct wlr_allocator *allocator, int width, int height,
		const struct wlr_drm_format *format) {
	(void)allocator;

	uint32_t ahb_format;
	if (!drm_to_ahb(format->format, &ahb_format)) {
		wlr_log(WLR_ERROR, "AHB: unsupported DRM format 0x%" PRIX32,
			format->format);
		return NULL;
	}

	AHardwareBuffer_Desc desc = {
		.width = width,
		.height = height,
		.layers = 1,
		.format = ahb_format,
		.usage = AHARDWAREBUFFER_USAGE_CPU_READ_OFTEN |
			AHARDWAREBUFFER_USAGE_CPU_WRITE_OFTEN |
			AHARDWAREBUFFER_USAGE_GPU_SAMPLED_IMAGE |
			AHARDWAREBUFFER_USAGE_GPU_FRAMEBUFFER,
	};

	AHardwareBuffer *ahb = NULL;
	if (AHardwareBuffer_allocate(&desc, &ahb) != 0 || ahb == NULL) {
		wlr_log(WLR_ERROR, "AHB: allocation of %dx%d failed", width, height);
		return NULL;
	}

	AHardwareBuffer_Desc got;
	AHardwareBuffer_describe(ahb, &got);
	const struct ahb_native_handle *handle =
		AHardwareBuffer_getNativeHandle(ahb);
	if (handle == NULL || handle->numFds < 1) {
		wlr_log(WLR_ERROR, "AHB: no native handle");
		AHardwareBuffer_release(ahb);
		return NULL;
	}

	struct ahb_buffer *buffer = calloc(1, sizeof(*buffer));
	if (buffer == NULL) {
		AHardwareBuffer_release(ahb);
		return NULL;
	}

	wlr_buffer_init(&buffer->base, &ahb_buffer_impl, width, height);
	buffer->ahb = ahb;
	buffer->fd = handle->data[0];
	buffer->drm_format = format->format;
	buffer->stride = got.stride * 4;

	wlr_log(WLR_DEBUG, "AHB buffer %dx%d drm_format=0x%" PRIX32
		" stride=%" PRIu32 " (ahb stride=%" PRIu32 ")",
		width, height, buffer->drm_format, buffer->stride, got.stride);

	return &buffer->base;
}

static void ahb_allocator_destroy(struct wlr_allocator *allocator) {
	/* struct ahb_allocator only contains the wlr_allocator base. */
	free((struct ahb_allocator *)allocator);
}

static const struct wlr_allocator_interface ahb_allocator_impl = {
	.create_buffer = ahb_allocator_create_buffer,
	.destroy = ahb_allocator_destroy,
};

struct wlr_allocator *termux_ahb_allocator_create(void) {
	struct ahb_allocator *allocator = calloc(1, sizeof(*allocator));
	if (allocator == NULL) {
		return NULL;
	}

	wlr_allocator_init(&allocator->base, &ahb_allocator_impl,
		WLR_BUFFER_CAP_DMABUF | WLR_BUFFER_CAP_SHM |
		WLR_BUFFER_CAP_DATA_PTR);
	return &allocator->base;
}

static bool ahb_egl_init(void) {
	if (egl_display != EGL_NO_DISPLAY) {
		return true;
	}

	egl_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (egl_display == EGL_NO_DISPLAY) {
		wlr_log(WLR_ERROR, "AHB: eglGetDisplay failed");
		return false;
	}

	EGLint major, minor;
	if (!eglInitialize(egl_display, &major, &minor)) {
		wlr_log(WLR_ERROR, "AHB: eglInitialize failed: 0x%x",
			eglGetError());
		egl_display = EGL_NO_DISPLAY;
		return false;
	}
	wlr_log(WLR_INFO, "AHB: EGL %d.%d", major, minor);

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
	if (eglChooseConfig(egl_display, config_attribs, &egl_config, 1, &n) &&
			n > 0) {
		wlr_log(WLR_INFO, "AHB: using EGL config");
	} else {
		egl_config = EGL_NO_CONFIG_KHR;
		wlr_log(WLR_INFO, "AHB: using configless EGL context");
	}

	get_native_client_buffer = (ahb_get_native_client_buffer_proc)
		eglGetProcAddress("eglGetNativeClientBufferANDROID");
	create_image = (PFNEGLCREATEIMAGEKHRPROC)
		eglGetProcAddress("eglCreateImageKHR");
	if (get_native_client_buffer == NULL || create_image == NULL) {
		wlr_log(WLR_ERROR,
			"AHB: EGL native buffer/image extensions unavailable");
		eglTerminate(egl_display);
		egl_display = EGL_NO_DISPLAY;
		return false;
	}

	return true;
}

static struct wlr_renderer *ahb_renderer_create_internal(void) {
	if (!ahb_egl_init()) {
		return NULL;
	}

	const EGLint context_attribs[] = {
		EGL_CONTEXT_CLIENT_VERSION, 2,
		EGL_NONE,
	};
	EGLContext context = eglCreateContext(egl_display, egl_config,
		EGL_NO_CONTEXT, context_attribs);
	if (context == EGL_NO_CONTEXT) {
		wlr_log(WLR_ERROR, "AHB: eglCreateContext failed: 0x%x",
			eglGetError());
		return NULL;
	}

	fx_renderer_set_buffer_egl_image_provider(ahb_egl_image);

	struct wlr_renderer *renderer =
		fx_renderer_create_with_egl(egl_display, context);
	if (renderer == NULL) {
		wlr_log(WLR_ERROR, "AHB: FX renderer creation failed");
		fx_renderer_set_buffer_egl_image_provider(NULL);
		return NULL;
	}

	ahb_active = true;
	return renderer;
}

struct wlr_renderer *termux_ahb_renderer_create(void) {
	struct wlr_renderer *renderer = ahb_renderer_create_internal();
	if (renderer == NULL) {
		ahb_active = false;
	}
	return renderer;
}

bool termux_ahb_active(void) {
	return ahb_active;
}
