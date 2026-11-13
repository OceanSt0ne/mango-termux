#ifndef MANGO_TERMUX_AHB_H
#define MANGO_TERMUX_AHB_H

#include <stdbool.h>

struct wlr_allocator;
struct wlr_buffer;
struct wlr_dmabuf_attributes;
struct wlr_renderer;

/*
 * Android/Termux GPU path.
 *
 * wlroots' X11 backend cannot use DMA-BUF without DRI3, and Termux:X11 does
 * not implement DRI3Open. Instead we allocate Android AHardwareBuffers (which
 * are CPU-mappable and can be rendered into by the Adreno GPU through the
 * system EGL implementation), render scenefx effects with an FX renderer built
 * on top of that EGL context, and present the buffers to Termux:X11 through
 * the SHM transport.
 */

/* Try to create the FX renderer backed by an Android EGL context. */
struct wlr_renderer *termux_ahb_renderer_create(void);

/* Allocator producing AHardwareBuffer-backed wlr_buffers. */
struct wlr_allocator *termux_ahb_allocator_create(void);

/* True once the Android EGL/FX renderer was created successfully. */
bool termux_ahb_active(void);

/*
 * Export an AHardwareBuffer-backed wlr_buffer as DMA-BUF attributes. This is
 * used by the Mesa Turnip/Zink renderer, which imports the buffer through
 * EGL_EXT_image_dma_buf_import instead of the Android EGL native-buffer path.
 */
bool termux_ahb_buffer_get_dmabuf(struct wlr_buffer *buffer,
	struct wlr_dmabuf_attributes *attribs);

#endif
