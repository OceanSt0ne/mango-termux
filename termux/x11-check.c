/*
 * Small helper used by run-mango.sh to test whether the X server from
 * Termux:X11 is reachable on $DISPLAY. Exit status 0 means "connected".
 */
#include <xcb/xcb.h>

int main(void) {
	xcb_connection_t *conn = xcb_connect(NULL, NULL);
	int error = xcb_connection_has_error(conn);
	xcb_disconnect(conn);
	return error ? 1 : 0;
}
