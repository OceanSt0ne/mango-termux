/*
 * Minimal DRM lease protocol compatibility shim for Termux/Android.
 *
 * The Termux wlroots build has no DRM backend, so the lease protocol isn't
 * available. Every function is a no-op and the manager is always NULL.
 */
#ifndef MANGO_TERMUX_FAKE_WLR_DRM_LEASE_V1_H
#define MANGO_TERMUX_FAKE_WLR_DRM_LEASE_V1_H

#include <stdbool.h>
#include <wayland-server-core.h>
#include <wlr/types/wlr_output.h>

struct wlr_backend;
struct wlr_drm_lease_v1;
struct wlr_drm_lease_request_v1;

struct wlr_drm_lease_v1_manager {
	struct {
		struct wl_signal request;
		struct wl_signal destroy;
	} events;
};

static inline struct wlr_drm_lease_v1_manager *
wlr_drm_lease_v1_manager_create(struct wl_display *display,
								struct wlr_backend *backend) {
	(void)display;
	(void)backend;
	return 0;
}

static inline void
wlr_drm_lease_v1_manager_offer_output(struct wlr_drm_lease_v1_manager *manager,
									  struct wlr_output *output) {
	(void)manager;
	(void)output;
}

static inline struct wlr_drm_lease_v1 *
wlr_drm_lease_request_v1_grant(struct wlr_drm_lease_request_v1 *request) {
	(void)request;
	return 0;
}

static inline void
wlr_drm_lease_request_v1_reject(struct wlr_drm_lease_request_v1 *request) {
	(void)request;
}

static inline void wlr_drm_lease_v1_destroy(struct wlr_drm_lease_v1 *lease) {
	(void)lease;
}

#endif
