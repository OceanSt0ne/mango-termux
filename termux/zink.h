#ifndef MANGO_TERMUX_ZINK_H
#define MANGO_TERMUX_ZINK_H

#include <stdbool.h>

struct wlr_renderer;

/*
 * Mesa Turnip path.
 *
 * Termux's Mesa build provides the Zink Gallium driver on top of the Freedreno
 * Vulkan driver (Turnip). Rendering happens on the Adreno GPU while output
 * buffers stay CPU-mappable AHardwareBuffers so the X11 backend can present
 * them over SHM without DRI3.
 */

/* Try to create the FX renderer backed by Mesa Zink + Turnip. */
struct wlr_renderer *termux_zink_renderer_create(void);

/* True once the Zink/Turnip FX renderer was created successfully. */
bool termux_zink_active(void);

#endif
