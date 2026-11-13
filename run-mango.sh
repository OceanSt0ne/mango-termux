#!/data/data/com.termux/files/usr/bin/bash
#
# Launch mango in Termux using the wlroots X11 backend and Termux:X11.
#
# Usage:
#   run-mango.sh [--restart] [mango options...]
#
# This script is safe to run again after closing/reopening the Termux app.
# It detects an already running mango instance, recreates stale wayland
# sockets and can tell a live Termux:X11 server from a leftover socket.
#
# Environment:
#   MANGO_BACKEND          x11 (default) | wayland | headless
#   MANGO_X11_DISPLAY      X display to use (default: $DISPLAY or :0)
#   MANGO_BIN              path to the mango binary (default: installed mango,
#                          private GPU build, or ./build/mango)
#   MANGO_TERMUX_RENDERER  turnip (default) = Mesa Zink + Turnip,
#                          ahb = Android EGL/AHardwareBuffer, pixman = software
#   MANGO_TERMUX_GPU       compatibility: 1 = ahb, 0 = pixman, turnip/zink = turnip
#   MANGO_RESTART          1 = stop a running mango before starting a new one
set -euo pipefail

# Resolve the script location so dev fallbacks work from any cwd and through
# symlinks. The installed copy normally uses the private GPU binary below.
self_path="$0"
if command -v readlink >/dev/null 2>&1; then
  self_path="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"
fi
script_dir="$(cd "$(dirname "$self_path")" && pwd)"

prefix="${PREFIX:-/data/data/com.termux/files/usr}"
priv_bin="$prefix/lib/mango-termux/mango"

# Xwayland on the KGSL GPU: use the patched server when it is installed.
# Its wrapper selects the private Mesa build (Zink on Turnip) and DRI3 over
# /dev/kgsl-3d0; the stock Termux Xwayland has no DRI3 and falls back to
# llvmpipe for every X11 client.
if [[ -z "${WLR_XWAYLAND:-}" && -x "$prefix/opt/xwayland-kgsl/bin/Xwayland" ]]; then
  export WLR_XWAYLAND="$prefix/opt/xwayland-kgsl/bin/Xwayland"
fi

# Pick the renderer before the binary: the Turnip path needs Termux Mesa
# (Zink), while the AHB path needs the private binary patched to Android's
# system EGL/GLES.
renderer="${MANGO_TERMUX_RENDERER:-}"
if [[ -z "$renderer" ]]; then
  case "${MANGO_TERMUX_GPU:-}" in
    0) renderer=pixman ;;
    1|ahb) renderer=ahb ;;
    *) renderer=turnip ;;
  esac
fi
export MANGO_TERMUX_RENDERER="$renderer"

if [[ "$renderer" == "turnip" || "$renderer" == "zink" ]]; then
  # The compositor itself uses Zink+Turnip, but Zink is a bad default for all
  # child processes: GTK4/Ghostty renders incorrectly with a global zink
  # override.  Give the session Mesa's native Freedreno/KGSL build instead.
  # termux/zink.c saves/restores these variables around mango's own renderer,
  # so mango still creates its Zink/Turnip context.
  mesa="$prefix/opt/mesa-kgsl"
  if [[ -d "$mesa/lib" ]]; then
    export LD_LIBRARY_PATH="$mesa/lib"
    export LIBGL_DRIVERS_PATH="$mesa/lib/dri"
    export GBM_BACKENDS_PATH="$mesa/lib/gbm"
    export MESA_LOADER_DRIVER_OVERRIDE=kgsl
    export GALLIUM_DRIVER=kgsl
    unset VK_DRIVER_FILES VK_ICD_FILENAMES
  else
    # Fallback: let host Mesa choose; do not leak a stale zink override.
    unset LD_LIBRARY_PATH LIBGL_DRIVERS_PATH GBM_BACKENDS_PATH
    unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER
    unset VK_DRIVER_FILES VK_ICD_FILENAMES
  fi
  # Mesa Zink on top of the Freedreno Vulkan driver (Turnip). The private
  # Mesa 27 build supplies both Zink and the native KGSL driver; termux/zink.c
  # sets the Zink variables only while creating mango's own renderer and then
  # restores the native KGSL session environment.
  if [[ -z "${MANGO_BIN:-}" ]]; then
    if [[ -x "$prefix/bin/mango" ]]; then
      MANGO_BIN="$prefix/bin/mango"
    elif [[ -x "$script_dir/build/mango" ]]; then
      MANGO_BIN="$script_dir/build/mango"
    fi
  fi
elif [[ "$renderer" == "ahb" ]]; then
  if [[ -z "${MANGO_BIN:-}" && -x "$priv_bin" ]]; then
    MANGO_BIN="$priv_bin"
  fi
  export MANGO_TERMUX_GPU="${MANGO_TERMUX_GPU:-1}"
else
  # pixman: use the normal Mesa binary and force software rendering.
  export MANGO_TERMUX_GPU=0
fi

if [[ "${1:-}" == "--restart" ]]; then
  MANGO_RESTART=1
  shift
fi

: "${XDG_RUNTIME_DIR:=${TMPDIR:-/tmp}}"
export XDG_RUNTIME_DIR
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

# Remove wayland-N sockets/locks left behind by a killed compositor, so mango
# gets a predictable socket name (wayland-0) again. A live compositor holds an
# exclusive flock on its lock file, which is how we distinguish the two cases.
cleanup_stale_wayland() {
  local lock pid alive
  for lock in "$XDG_RUNTIME_DIR"/wayland-*.lock; do
    [[ -e "$lock" ]] || continue
    if command -v flock >/dev/null 2>&1; then
      if flock -n "$lock" true 2>/dev/null; then
        rm -f "$lock" "${lock%.lock}"
      fi
      continue
    fi
    pid="$(cat "$lock" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    alive=false
    [[ -d "/proc/$pid" ]] && alive=true
    kill -0 "$pid" 2>/dev/null && alive=true
    if [[ "$alive" == false ]]; then
      rm -f "$lock" "${lock%.lock}"
    fi
  done
}
cleanup_stale_wayland

# Return the IPC socket of a healthy running mango, if any. Dead sockets from
# a previous Termux session are removed on the way.
find_running_mango() {
  local sock pid
  for sock in "$XDG_RUNTIME_DIR"/mango-*.sock; do
    [[ -S "$sock" ]] || continue
    pid="${sock##*-}"
    pid="${pid%.sock}"
    if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
      if ! command -v mmsg >/dev/null 2>&1 ||
         MANGO_INSTANCE_SIGNATURE="$sock" timeout 2 mmsg get version >/dev/null 2>&1; then
        echo "$sock"
        return 0
      fi
    fi
    rm -f "$sock"
  done
  return 1
}

backend="${MANGO_BACKEND:-x11}"
export WLR_BACKENDS="${WLR_BACKENDS:-$backend}"

# Reuse a compositor that survived the Termux app restart instead of starting
# a second instance on the same X display.
if ipc="$(find_running_mango)"; then
  if [[ "${MANGO_RESTART:-0}" == "1" ]]; then
    pid="${ipc##*-}"
    pid="${pid%.sock}"
    echo "Restarting mango (pid $pid) ..." >&2
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 30); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -9 "$pid" 2>/dev/null || true
    rm -f "$ipc"
    cleanup_stale_wayland
  else
    echo "mango is already running (IPC socket: $ipc)." >&2
    echo "Use '$0 --restart' to replace it." >&2
    exit 0
  fi
fi

display="${MANGO_X11_DISPLAY:-${DISPLAY:-:0}}"
export DISPLAY="$display"
num="${display#:}"
num="${num%%.*}"
sockdir="${TMPDIR:-/tmp}/.X11-unix"
sock="$sockdir/X${num}"
lockdir="${TMPDIR:-/tmp}"
lock="$lockdir/.X${num}-lock"
x11_log="$lockdir/termux-x11.log"

# Drop a lock left by a server that no longer exists. The pid inside the lock
# is the only trustworthy part after the Termux app is reopened.
if [[ -f "$lock" ]]; then
  lock_pid="$(cat "$lock" 2>/dev/null || true)"
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
    rm -f "$lock" "$sock" 2>/dev/null || true
  fi
fi

# A real X11 handshake is the only reliable "is the server usable?" test
# after the Termux app restarts: a socket may exist with no server behind it,
# and the process may live outside the current ps namespace.
x11_connected() {
  if command -v mango-x11-check >/dev/null 2>&1; then
    timeout 3 mango-x11-check >/dev/null 2>&1
  elif [[ -x "$script_dir/build/mango-x11-check" ]]; then
    timeout 3 "$script_dir/build/mango-x11-check" >/dev/null 2>&1
  else
    [[ -S "$sock" ]]
  fi
}

x11_server_alive() {
  ps -eo args= 2>/dev/null |
    grep -qE "termux-x11 .*${display}([[:space:]]|$)"
}

start_termux_x11() {
  if ! command -v termux-x11 >/dev/null 2>&1; then
    echo "termux-x11 not found. Install the X11 server:" >&2
    echo "  pkg install x11-repo && pkg update && pkg install termux-x11-nightly" >&2
    return 1
  fi
  : >"$x11_log"
  nohup termux-x11 "$display" -ac -noreset >>"$x11_log" 2>&1 &
  local i
  for i in $(seq 1 60); do
    x11_connected && return 0
    sleep 0.2
  done
  return 1
}

if [[ "$backend" == "x11" ]]; then
  if ! x11_connected; then
    echo "Starting Termux:X11 on $display ..." >&2
    mkdir -p "$sockdir"
    if ! start_termux_x11; then
      # A first launch can lose the race with an X server that is still
      # starting. If the log says the display is busy, give it more time.
      if grep -qiE "already (running|active)|server is already" "$x11_log" 2>/dev/null; then
        echo "Termux:X11 is already active on $display, waiting for it ..." >&2
        for _ in $(seq 1 30); do
          x11_connected && break
          sleep 0.2
        done
      fi
      # Otherwise the socket/lock is almost certainly stale (Termux was
      # killed). Drop it and try once more.
      if ! x11_connected; then
        echo "Removing stale X11 socket/lock on $display and retrying ..." >&2
        rm -f "$sock" "$lock"
        start_termux_x11 || true
      fi
    fi
  fi

  if ! x11_connected; then
    echo "Failed to connect to Termux:X11 on $display." >&2
    echo "Open the Termux:X11 app; server log: $x11_log" >&2
    exit 1
  fi
else
  # Nested/headless modes keep the caller's DISPLAY/WAYLAND_DISPLAY.
  :
fi

if [[ -n "${MANGO_BIN:-}" ]]; then
  bin="$MANGO_BIN"
elif command -v mango >/dev/null 2>&1; then
  bin="$(command -v mango)"
elif [[ -x "$script_dir/build/mango" ]]; then
  bin="$script_dir/build/mango"
else
  echo "mango binary not found; run: meson compile -C build" >&2
  exit 1
fi

if [[ "$bin" == "$priv_bin" ]]; then
  # The private libraries use absolute NEEDED entries for Android EGL/GLES.
  # An inherited LD_LIBRARY_PATH can make the linker resolve those system
  # dependencies in the Termux namespace; RUNPATH is sufficient here.
  unset LD_LIBRARY_PATH
fi
exec "$bin" "$@"
