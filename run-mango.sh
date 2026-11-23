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
#   MANGO_XWAYLAND_GLAMOR  1 = opt into the DRI3/glamor Xwayland server; default
#                          0 = stable no-glamor server with indirect GLX
#   MANGO_X11_INPUT_PREFS  Termux:X11 input preferences applied at startup
#                          (default: "touchMode:1 tapToMove:false", empty skips)
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

# Universal session defaults. Keep caller overrides when they are non-empty,
# but never inherit the PRoot /bin/bash as SHELL.
export PREFIX="$prefix"
export TMPDIR="$prefix/tmp"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$TMPDIR}"
case "$XDG_RUNTIME_DIR" in
  "$prefix"/*) ;;
  *) XDG_RUNTIME_DIR="$TMPDIR" ;;
esac

if [[ -x "$prefix/bin/fish" ]]; then
  native_shell="$prefix/bin/fish"
elif [[ -x "$prefix/bin/bash" ]]; then
  native_shell="$prefix/bin/bash"
elif [[ -n "${SHELL:-}" && "$SHELL" != "/bin/bash" ]]; then
  native_shell="$SHELL"
elif [[ -x /system/bin/sh ]]; then
  native_shell="/system/bin/sh"
else
  native_shell="$prefix/bin/sh"
fi
SHELL="$native_shell"
export SHELL

: "${MOZ_ENABLE_WAYLAND:=1}"
: "${GDK_BACKEND:=wayland,x11}"
: "${QT_QPA_PLATFORM:=wayland;xcb}"
: "${SDL_VIDEODRIVER:=wayland}"
: "${ELECTRON_OZONE_PLATFORM_HINT:=auto}"
: "${XDG_CURRENT_DESKTOP:=mango}"
: "${XDG_SESSION_TYPE:=wayland}"
export MOZ_ENABLE_WAYLAND GDK_BACKEND QT_QPA_PLATFORM SDL_VIDEODRIVER
export ELECTRON_OZONE_PLATFORM_HINT XDG_CURRENT_DESKTOP XDG_SESSION_TYPE

# Make sure the Termux prefix is searchable even when the caller inherited a
# minimal PATH, so the terminal probe below sees the installed binaries.
case ":$PATH:" in
  *":$prefix/bin:"*) ;;
  *) PATH="$prefix/bin${PATH:+:$PATH}" ;;
esac
export PATH

# Noctalia and other launchers resolve $TERMINAL first.  Prefer the clean
# native wrapper (it routes through noctalia-exec and prefers Wayland-native
# foot), then the terminals shipped by Termux.
if [[ -z ${TERMINAL:-} ]]; then
  if [[ -x $prefix/bin/noctalia-terminal ]]; then
    TERMINAL=$prefix/bin/noctalia-terminal
  else
    for candidate in foot kitty ghostty alacritty wezterm xterm; do
      if command -v "$candidate" >/dev/null 2>&1; then
        TERMINAL="$(command -v "$candidate")"
        break
      fi
    done
  fi
fi
if [[ -n ${TERMINAL:-} ]]; then
  export TERMINAL
fi

# Native XKB data and defaults.  MangoWM itself reads input.conf, but
# libxkbcommon clients and XWayland also consult these variables; never let a
# rootfs/glibc xkeyboard-config tree leak into the session.
if [[ -d $prefix/share/X11/xkb ]]; then
  XKB_CONFIG_ROOT=$prefix/share/X11/xkb
  export XKB_CONFIG_ROOT
fi
: "${XKB_DEFAULT_LAYOUT:=us,ru}"
: "${XKB_DEFAULT_OPTIONS:=grp:win_space_toggle}"
: "${XKB_DEFAULT_RULES:=evdev}"
: "${XKB_DEFAULT_MODEL:=pc105}"
export XKB_DEFAULT_LAYOUT XKB_DEFAULT_OPTIONS XKB_DEFAULT_RULES XKB_DEFAULT_MODEL

priv_bin="$prefix/lib/mango-termux/mango"

# Xwayland on Android: DRI3/DRM ioctls can abort the X socket with
# "fatal IO error 25" when an X11 GL client probes the patched KGSL server.
# Default to a stable no-glamor server with indirect GLX and DRI3 disabled for
# clients. Set MANGO_XWAYLAND_GLAMOR=1 to opt back into the DRI3 server.
xwayland_glamor="${MANGO_XWAYLAND_GLAMOR:-0}"
export MANGO_XWAYLAND_GLAMOR="$xwayland_glamor"
if [[ "$xwayland_glamor" == "1" ]]; then
  unset XWAYLAND_NO_GLAMOR
  export LIBGL_DRI3_DISABLE=0
  if [[ -z "${WLR_XWAYLAND:-}" && -x "$prefix/opt/xwayland-kgsl/bin/Xwayland" ]]; then
    export WLR_XWAYLAND="$prefix/opt/xwayland-kgsl/bin/Xwayland"
  fi
else
  export XWAYLAND_NO_GLAMOR=1
  : "${LIBGL_DRI3_DISABLE:=1}"
  export LIBGL_DRI3_DISABLE

  xwayland_wrapper="$prefix/tmp/mango-xwayland"
  xwayland_real="${WLR_XWAYLAND:-}"
  if [[ -z "$xwayland_real" ]]; then
    if [[ -x "$prefix/opt/xwayland-kgsl/bin/Xwayland.real" ]]; then
      xwayland_real="$prefix/opt/xwayland-kgsl/bin/Xwayland.real"
    elif [[ -x "$prefix/opt/xwayland-kgsl/bin/Xwayland" ]]; then
      xwayland_real="$prefix/opt/xwayland-kgsl/bin/Xwayland"
    elif [[ -x "$prefix/bin/Xwayland" ]]; then
      xwayland_real="$prefix/bin/Xwayland"
    else
      xwayland_real="$(command -v Xwayland 2>/dev/null || true)"
    fi
  fi
  if [[ -n "$xwayland_real" && "$xwayland_real" != "$xwayland_wrapper" ]]; then
    mkdir -p "$prefix/tmp"
    xwayland_tmp="$(mktemp "$prefix/tmp/.mango-xwayland.XXXXXX")"
    {
      printf '#!/data/data/com.termux/files/usr/bin/bash\n'
      printf 'real=%q\n' "$xwayland_real"
      printf 'export XWAYLAND_NO_GLAMOR=1\n'
      printf 'export LIBGL_DRI3_DISABLE=1\n'
      printf 'exec "$real" "$@" +iglx -shm\n'
    } >"$xwayland_tmp"
    chmod 0755 "$xwayland_tmp"
    if [[ -f "$xwayland_wrapper" ]] && cmp -s "$xwayland_tmp" "$xwayland_wrapper"; then
      rm -f "$xwayland_tmp"
    else
      mv -f "$xwayland_tmp" "$xwayland_wrapper"
      chmod 0755 "$xwayland_wrapper"
    fi
    export WLR_XWAYLAND="$xwayland_wrapper"
  fi
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
  kgsl_root=""
  if [[ -f "$mesa/lib/dri/kgsl_dri.so" ]]; then
    kgsl_root="$mesa"
  elif [[ -f "$prefix/lib/dri/kgsl_dri.so" ]]; then
    kgsl_root="$prefix"
  fi

  if [[ -n "$kgsl_root" ]]; then
    export LD_LIBRARY_PATH="$kgsl_root/lib"
    export LIBGL_DRIVERS_PATH="$kgsl_root/lib/dri"
    export GBM_BACKENDS_PATH="$kgsl_root/lib/gbm"
    export MESA_LOADER_DRIVER_OVERRIDE=kgsl
    export GALLIUM_DRIVER=kgsl

    egl_vendor="$kgsl_root/share/glvnd/egl_vendor.d/50_mesa.json"
    if [[ -f "$egl_vendor" ]]; then
      export __EGL_VENDOR_LIBRARY_FILENAMES="$egl_vendor"
    else
      unset __EGL_VENDOR_LIBRARY_FILENAMES
    fi

    icd=""
    if [[ -f "$mesa/share/vulkan/icd.d/freedreno_icd.aarch64.json" ]]; then
      icd="$mesa/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    elif [[ -f "$prefix/share/vulkan/icd.d/freedreno_icd.aarch64.json" ]]; then
      icd="$prefix/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    fi
    if [[ -n "$icd" ]]; then
      export VK_DRIVER_FILES="$icd"
      export VK_ICD_FILENAMES="$icd"
    else
      unset VK_DRIVER_FILES VK_ICD_FILENAMES
    fi
  else
    # No KGSL DRI driver: clear stale Mesa/KGSL overrides. A Freedreno/Turnip
    # Vulkan ICD is still usable with stock Mesa.
    unset LD_LIBRARY_PATH LIBGL_DRIVERS_PATH GBM_BACKENDS_PATH
    unset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER
    unset __EGL_VENDOR_LIBRARY_FILENAMES

    icd=""
    if [[ -f "$mesa/share/vulkan/icd.d/freedreno_icd.aarch64.json" ]]; then
      icd="$mesa/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    elif [[ -f "$prefix/share/vulkan/icd.d/freedreno_icd.aarch64.json" ]]; then
      icd="$prefix/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    fi
    if [[ -n "$icd" ]]; then
      export VK_DRIVER_FILES="$icd"
      export VK_ICD_FILENAMES="$icd"
      echo "warning: turnip-kgsl is not installed; clients use stock Mesa." >&2
      echo "  Install it with termux-compat/install-freedreno-kgsl.sh." >&2
    else
      unset VK_DRIVER_FILES VK_ICD_FILENAMES
      echo "warning: no Freedreno/KGSL Mesa or Vulkan ICD found; using stock Mesa." >&2
    fi
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

: "${XDG_RUNTIME_DIR:=${TMPDIR:-$prefix/tmp}}"
export XDG_RUNTIME_DIR
chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

persist_session_env() {
  local dir="$prefix/tmp"
  local out="$dir/mango-session.env"
  local tmp var
  if ! mkdir -p "$dir" 2>/dev/null; then
    echo "warning: cannot create $dir; skipping session env file." >&2
    return 0
  fi
  if ! tmp="$(mktemp "$dir/.mango-session.env.XXXXXX" 2>/dev/null)"; then
    echo "warning: cannot create a temp file in $dir; skipping session env file." >&2
    return 0
  fi
  {
    printf 'export WAYLAND_DISPLAY=%q\n' "${WAYLAND_DISPLAY:-wayland-0}" &&
    printf 'export DISPLAY=%q\n' "${DISPLAY:-}" &&
    printf 'export XDG_RUNTIME_DIR=%q\n' "${XDG_RUNTIME_DIR:-}" &&
    for var in \
      PREFIX \
      TMPDIR \
      SHELL \
      TERMINAL \
      XKB_CONFIG_ROOT \
      XKB_DEFAULT_LAYOUT \
      XKB_DEFAULT_OPTIONS \
      XKB_DEFAULT_RULES \
      XKB_DEFAULT_MODEL \
      XDG_CURRENT_DESKTOP \
      XDG_SESSION_TYPE \
      MOZ_ENABLE_WAYLAND \
      GDK_BACKEND \
      QT_QPA_PLATFORM \
      SDL_VIDEODRIVER \
      ELECTRON_OZONE_PLATFORM_HINT; do
      printf 'export %s=%q\n' "$var" "${!var:-}"
    done &&
    for var in \
      DBUS_SESSION_BUS_ADDRESS \
      XCURSOR_THEME \
      XCURSOR_SIZE \
      MANGO_TERMUX_RENDERER \
      MANGO_TERMUX_GPU \
      LD_LIBRARY_PATH \
      LIBGL_DRIVERS_PATH \
      GBM_BACKENDS_PATH \
      MESA_LOADER_DRIVER_OVERRIDE \
      GALLIUM_DRIVER \
      __EGL_VENDOR_LIBRARY_FILENAMES \
      VK_DRIVER_FILES \
      VK_ICD_FILENAMES \
      FD_KGSL_DMABUF \
      MANGO_XWAYLAND_GLAMOR \
      XWAYLAND_NO_GLAMOR \
      LIBGL_DRI3_DISABLE \
      LANG \
      LC_CTYPE; do
      if [[ -n "${!var:-}" ]]; then
        printf 'export %s=%q\n' "$var" "${!var}"
      fi
    done
  } >"$tmp" 2>/dev/null || {
    rm -f "$tmp"
    echo "warning: cannot write $out; skipping session env file." >&2
    return 0
  }
  chmod 0600 "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$out" 2>/dev/null; then
    rm -f "$tmp"
    echo "warning: cannot install $out; skipping session env file." >&2
    return 0
  fi
  chmod 0600 "$out" 2>/dev/null || true
}

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

# Kill Noctalia instances left behind by a replaced compositor. Match the
# process arguments (not the executable name) so both the rootfs binary and the
# patched native fallback are caught; pkill -x would miss the loader wrapper.
kill_leftover_noctalia() {
  local pid
  ps -eo pid=,args= 2>/dev/null |
    grep -E '([/]usr/bin/noctalia|libexec[/]mango-termux/noctalia-native)' |
    awk '{print $1}' |
    while read -r pid; do
      [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null || true
    done || true
  for _ in $(seq 1 20); do
    if ! ps -eo args= 2>/dev/null |
       grep -Eq '([/]usr/bin/noctalia|libexec[/]mango-termux/noctalia-native)'; then
      return 0
    fi
    sleep 0.1
  done
  ps -eo pid=,args= 2>/dev/null |
    grep -E '([/]usr/bin/noctalia|libexec[/]mango-termux/noctalia-native)' |
    awk '{print $1}' |
    while read -r pid; do
      [[ "$pid" =~ ^[0-9]+$ ]] && kill -9 "$pid" 2>/dev/null || true
    done || true
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

# Integration stamp: skip the full Termux integration scan when its inputs are
# unchanged. Keyed on mtime+size of the helpers and mics.conf, plus the mtime of
# the applications directory.
integration_stamp="$prefix/tmp/mango-integrate.stamp"

integrate_fingerprint() {
  local f meta
  if ! command -v stat >/dev/null 2>&1; then
    return 1
  fi
  for f in \
    "$prefix/bin/mango-integrate" \
    "$prefix/bin/mango-noctalia" \
    "$prefix/bin/mango-firefox" \
    "$HOME/.config/mango/mics.conf"; do
    if [[ -e "$f" ]]; then
      meta="$(stat -c '%Y:%s' "$f" 2>/dev/null || true)"
      printf '%s %s\n' "$f" "${meta:-?}"
    else
      printf '%s missing\n' "$f"
    fi
  done
  if [[ -d "$prefix/share/applications" ]]; then
    meta="$(stat -c '%Y' "$prefix/share/applications" 2>/dev/null || true)"
    printf '%s %s\n' "$prefix/share/applications" "${meta:-?}"
  else
    printf '%s missing\n' "$prefix/share/applications"
  fi
}

# Refresh Termux integration helpers non-fatally. mango-integrate also
# installs/migrates the native Noctalia launcher; Noctalia runs directly in
# Termux and never needs proot or a host bridge. Called only for a new session,
# and skipped when the stamp matches unchanged inputs or integrations are off.
run_integration() {
  local integrate current stored
  integrate=""
  if [[ -x "$prefix/bin/mango-integrate" ]]; then
    integrate="$prefix/bin/mango-integrate"
  elif [[ -x "$script_dir/termux-compat/mango-integrate" ]]; then
    integrate="$script_dir/termux-compat/mango-integrate"
  fi
  [[ -n "$integrate" ]] || return 0
  if [[ "${MANGO_SKIP_INTEGRATIONS:-0}" == "1" ]]; then
    return 0
  fi

  current="$(integrate_fingerprint 2>/dev/null || true)"
  stored=""
  if [[ -r "$integration_stamp" ]]; then
    stored="$(cat "$integration_stamp" 2>/dev/null || true)"
  fi
  if [[ -n "$current" && "$current" == "$stored" ]]; then
    return 0
  fi

  if [[ -x "$prefix/bin/mango-noctalia" ]]; then
    echo "Refreshing Termux integrations (native Noctalia, no proot) ..." >&2
  fi
  if ! "$integrate" --quiet; then
    echo "warning: $integrate failed; continuing with existing integration." >&2
    return 0
  fi

  current="$(integrate_fingerprint 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    mkdir -p "$prefix/tmp" 2>/dev/null || true
    printf '%s\n' "$current" >"$integration_stamp" 2>/dev/null || true
  fi
}

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

# On --restart, clear any Noctalia left over from the replaced compositor
# before starting a new session, so panels do not duplicate.
if [[ "${MANGO_RESTART:-0}" == "1" ]]; then
  kill_leftover_noctalia
fi

# Integrate before starting a new session. On --restart this runs after the old
# compositor has exited; an already-running mango returns above.
run_integration

display="${MANGO_X11_DISPLAY:-${DISPLAY:-:0}}"
export DISPLAY="$display"
num="${display#:}"
num="${num%%.*}"
sockdir="${TMPDIR:-$prefix/tmp}/.X11-unix"
sock="$sockdir/X${num}"
lockdir="${TMPDIR:-$prefix/tmp}"
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

# Termux:X11 delivers touch input as absolute coordinates unless trackpad mode
# is used. Trackpad mode (1) produces true relative deltas for pointer-locked
# applications, and disabling tap-to-move prevents a tap from teleporting the
# pointer across the screen. Both settings are applied live and can be
# overridden or disabled with MANGO_X11_INPUT_PREFS.
apply_termux_x11_input_prefs() {
  [[ "$backend" == "x11" ]] || return 0
  command -v termux-x11-preference >/dev/null 2>&1 || return 0
  local prefs="${MANGO_X11_INPUT_PREFS-touchMode:1 tapToMove:false}"
  [[ -n "$prefs" ]] || return 0
  # shellcheck disable=SC2086
  if termux-x11-preference $prefs >/dev/null 2>&1; then
    echo "Applied Termux:X11 input preferences: $prefs" >&2
  fi
  return 0
}

start_termux_x11() {
  if ! command -v termux-x11 >/dev/null 2>&1; then
    echo "termux-x11 not found. Install the X11 server:" >&2
    echo "  pkg install x11-repo && pkg update && pkg install termux-x11-nightly" >&2
    return 1
  fi
  : >"$x11_log"
  # Start Termux:X11 with its own renderer environment. The private Mesa/KGSL
  # variables above belong to mango; leaking them into the X server changes
  # how it selects its GL/Vulkan stack.
  nohup env \
    -u LD_LIBRARY_PATH \
    -u LIBGL_DRIVERS_PATH \
    -u GBM_BACKENDS_PATH \
    -u MESA_LOADER_DRIVER_OVERRIDE \
    -u GALLIUM_DRIVER \
    -u FD_KGSL_DMABUF \
    -u VK_DRIVER_FILES \
    -u VK_ICD_FILENAMES \
    -u EGL_PLATFORM \
    -u __EGL_VENDOR_LIBRARY_FILENAMES \
    -u WAYLAND_DISPLAY \
    -u XDG_CURRENT_DESKTOP \
    -u XDG_SESSION_TYPE \
    -u MOZ_ENABLE_WAYLAND \
    -u GDK_BACKEND \
    -u QT_QPA_PLATFORM \
    -u SDL_VIDEODRIVER \
    -u ELECTRON_OZONE_PLATFORM_HINT \
    -u SHELL \
    termux-x11 "$display" -ac -noreset >>"$x11_log" 2>&1 &
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

  # Trackpad mode keeps 3D games from receiving absolute-position jumps.
  apply_termux_x11_input_prefs
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
persist_session_env
exec "$bin" "$@"
