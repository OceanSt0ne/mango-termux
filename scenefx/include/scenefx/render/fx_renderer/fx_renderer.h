#ifndef SCENEFX_FX_OPENGL_H
#define SCENEFX_FX_OPENGL_H

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <wlr/backend.h>
#include <wlr/render/interface.h>
#include <wlr/types/wlr_buffer.h>

struct fx_renderer;

struct wlr_renderer *fx_renderer_create_with_drm_fd(int drm_fd);
struct wlr_renderer *fx_renderer_create(struct wlr_backend *backend);

/*
 * Termux/Android fallback: create the FX renderer from an existing EGL
 * display/context (e.g. an Android EGL context) instead of a DRM render node.
 */
struct wlr_renderer *fx_renderer_create_with_egl(EGLDisplay display,
	EGLContext context);

/*
 * Allows the embedding application to provide an EGLImage for custom buffers
 * (e.g. Android AHardwareBuffer) that cannot be imported through
 * EGL_EXT_image_dma_buf_import. Return EGL_NO_IMAGE_KHR for other buffers.
 */
typedef EGLImageKHR (*fx_buffer_egl_image_provider_t)(
	struct wlr_buffer *buffer);
void fx_renderer_set_buffer_egl_image_provider(
	fx_buffer_egl_image_provider_t provider);

struct fx_renderer *fx_get_renderer(struct wlr_renderer *wlr_renderer);

bool fx_renderer_check_ext(struct wlr_renderer *renderer, const char *ext);
GLuint fx_renderer_get_buffer_fbo(struct wlr_renderer *renderer, struct wlr_buffer *buffer);

//
// fx_texture
//

struct fx_texture_attribs {
	GLenum target; /* either GL_TEXTURE_2D or GL_TEXTURE_EXTERNAL_OES */
	GLuint tex;

	bool has_alpha;
};

struct wlr_texture *fx_texture_from_buffer(struct wlr_renderer *wlr_renderer,
		struct wlr_buffer *buffer);

void fx_texture_get_attribs(struct wlr_texture *texture,
	struct fx_texture_attribs *attribs);

#endif
