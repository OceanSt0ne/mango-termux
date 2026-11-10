/*
 * Minimal wlroots session compatibility shim for Termux/Android.
 *
 * The Termux wlroots build has no session/DRM backend, hence no session.h.
 * Mango only reads session->active and changes the VT for the (unavailable)
 * chvt binding, so provide a minimal definition and a no-op implementation.
 */
#ifndef MANGO_TERMUX_FAKE_WLR_BACKEND_SESSION_H
#define MANGO_TERMUX_FAKE_WLR_BACKEND_SESSION_H

#include <stdbool.h>

struct wlr_session {
	bool active;
};

static inline bool wlr_session_change_vt(struct wlr_session *session,
										 unsigned int vt) {
	(void)session;
	(void)vt;
	return false;
}

#endif
