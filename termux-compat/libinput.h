/*
 * Minimal libinput compatibility shim for Termux/Android builds.
 *
 * The Termux wlroots package does not ship the libinput backend, so mango is
 * built without libinput support. These stubs keep the libinput-specific code
 * paths compiling: every device is reported as non-libinput, therefore none of
 * these functions is ever called at runtime.
 */
#ifndef MANGO_TERMUX_FAKE_LIBINPUT_H
#define MANGO_TERMUX_FAKE_LIBINPUT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

struct libinput_device;
struct libinput_device_group;

enum libinput_config_status {
	LIBINPUT_CONFIG_STATUS_SUCCESS = 0,
	LIBINPUT_CONFIG_STATUS_UNSUPPORTED,
	LIBINPUT_CONFIG_STATUS_INVALID,
};

enum libinput_config_tap_button_map {
	LIBINPUT_CONFIG_TAP_MAP_LRM = 1,
	LIBINPUT_CONFIG_TAP_MAP_LMR = 2,
};

enum libinput_config_accel_profile {
	LIBINPUT_CONFIG_ACCEL_PROFILE_NONE = 0,
	LIBINPUT_CONFIG_ACCEL_PROFILE_FLAT = 1,
	LIBINPUT_CONFIG_ACCEL_PROFILE_ADAPTIVE = 2,
	LIBINPUT_CONFIG_ACCEL_PROFILE_CUSTOM = 3,
};

enum libinput_config_click_method {
	LIBINPUT_CONFIG_CLICK_METHOD_NONE = 0,
	LIBINPUT_CONFIG_CLICK_METHOD_BUTTON_AREAS = 1,
	LIBINPUT_CONFIG_CLICK_METHOD_CLICKFINGER = 2,
};

enum libinput_config_scroll_method {
	LIBINPUT_CONFIG_SCROLL_NO_SCROLL = 0,
	LIBINPUT_CONFIG_SCROLL_2FG = 1,
	LIBINPUT_CONFIG_SCROLL_EDGE = 2,
	LIBINPUT_CONFIG_SCROLL_ON_BUTTON_DOWN = 3,
};

enum libinput_config_send_events_mode {
	LIBINPUT_CONFIG_SEND_EVENTS_ENABLED = 0,
	LIBINPUT_CONFIG_SEND_EVENTS_DISABLED_ON_EXTERNAL_MOUSE = 1,
	LIBINPUT_CONFIG_SEND_EVENTS_DISABLED = 2,
};

static inline int
libinput_device_config_accel_is_available(struct libinput_device *device) {
	(void)device;
	return 0;
}

static inline enum libinput_config_status
libinput_device_config_accel_set_profile(struct libinput_device *device,
										 enum libinput_config_accel_profile profile) {
	(void)device;
	(void)profile;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline enum libinput_config_status
libinput_device_config_accel_set_speed(struct libinput_device *device,
									   double speed) {
	(void)device;
	(void)speed;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline uint32_t
libinput_device_config_click_get_methods(struct libinput_device *device) {
	(void)device;
	return LIBINPUT_CONFIG_CLICK_METHOD_NONE;
}

static inline enum libinput_config_status
libinput_device_config_click_set_method(struct libinput_device *device,
										enum libinput_config_click_method method) {
	(void)device;
	(void)method;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline int
libinput_device_config_dwt_is_available(struct libinput_device *device) {
	(void)device;
	return 0;
}

static inline enum libinput_config_status
libinput_device_config_dwt_set_enabled(struct libinput_device *device,
									   int enabled) {
	(void)device;
	(void)enabled;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline int
libinput_device_config_left_handed_is_available(struct libinput_device *device) {
	(void)device;
	return 0;
}

static inline enum libinput_config_status
libinput_device_config_left_handed_set(struct libinput_device *device,
									   int left_handed) {
	(void)device;
	(void)left_handed;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline int libinput_device_config_middle_emulation_is_available(
	struct libinput_device *device) {
	(void)device;
	return 0;
}

static inline enum libinput_config_status
libinput_device_config_middle_emulation_set_enabled(struct libinput_device *device,
													int enabled) {
	(void)device;
	(void)enabled;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline uint32_t
libinput_device_config_scroll_get_methods(struct libinput_device *device) {
	(void)device;
	return LIBINPUT_CONFIG_SCROLL_NO_SCROLL;
}

static inline enum libinput_config_status
libinput_device_config_scroll_set_button(struct libinput_device *device,
										 uint32_t button) {
	(void)device;
	(void)button;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline enum libinput_config_status
libinput_device_config_scroll_set_method(struct libinput_device *device,
										 enum libinput_config_scroll_method method) {
	(void)device;
	(void)method;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline enum libinput_config_status
libinput_device_config_scroll_set_natural_scroll_enabled(
	struct libinput_device *device, int enabled) {
	(void)device;
	(void)enabled;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline uint32_t
libinput_device_config_send_events_get_modes(struct libinput_device *device) {
	(void)device;
	return 0;
}

static inline enum libinput_config_status
libinput_device_config_send_events_set_mode(struct libinput_device *device,
											enum libinput_config_send_events_mode mode) {
	(void)device;
	(void)mode;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline int
libinput_device_config_tap_get_finger_count(struct libinput_device *device) {
	(void)device;
	return 0;
}

static inline enum libinput_config_status
libinput_device_config_tap_set_button_map(struct libinput_device *device,
										  enum libinput_config_tap_button_map map) {
	(void)device;
	(void)map;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline enum libinput_config_status
libinput_device_config_tap_set_drag_enabled(struct libinput_device *device,
											int enabled) {
	(void)device;
	(void)enabled;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline enum libinput_config_status
libinput_device_config_tap_set_drag_lock_enabled(struct libinput_device *device,
												 int enabled) {
	(void)device;
	(void)enabled;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline enum libinput_config_status
libinput_device_config_tap_set_enabled(struct libinput_device *device,
									   int enabled) {
	(void)device;
	(void)enabled;
	return LIBINPUT_CONFIG_STATUS_SUCCESS;
}

static inline struct libinput_device_group *
libinput_device_get_device_group(struct libinput_device *device) {
	(void)device;
	return 0;
}

static inline unsigned int
libinput_device_get_id_product(struct libinput_device *device) {
	(void)device;
	return 0;
}

static inline unsigned int
libinput_device_get_id_vendor(struct libinput_device *device) {
	(void)device;
	return 0;
}

#ifdef __cplusplus
}
#endif

#endif
