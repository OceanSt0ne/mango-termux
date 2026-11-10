/*
 * Minimal wlroots libinput backend compatibility shim for Termux/Android.
 *
 * The Termux wlroots build does not include the libinput backend. Mango treats
 * every input device as non-libinput, which makes it skip all libinput-specific
 * configuration paths while still using the generic wlr input interfaces.
 */
#ifndef MANGO_TERMUX_FAKE_WLR_BACKEND_LIBINPUT_H
#define MANGO_TERMUX_FAKE_WLR_BACKEND_LIBINPUT_H

#include <libinput.h>
#include <stdbool.h>
#include <wlr/types/wlr_input_device.h>

static inline bool
wlr_input_device_is_libinput(struct wlr_input_device *device) {
	(void)device;
	return false;
}

static inline struct libinput_device *
wlr_libinput_get_device_handle(struct wlr_input_device *device) {
	(void)device;
	return 0;
}

#endif
