#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

self_path="$0"
if command -v readlink >/dev/null 2>&1; then
  self_path="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"
fi
self_dir="$(cd "$(dirname "$self_path")" && pwd)"

: "${PREFIX:=/data/data/com.termux/files/usr}"
if [[ -z ${HOME:-} ]]; then
  HOME="$(dirname "$PREFIX")/home"
fi
if [[ -z ${TMPDIR:-} || $TMPDIR == "/tmp" ]]; then
  TMPDIR="$PREFIX/tmp"
fi
export PREFIX HOME TMPDIR

usage() {
  cat <<'EOF'
Install the native Termux Noctalia launcher from an existing Linux rootfs.

Usage:
  ./install-noctalia-termux.sh [options]

Options:
  --rootfs PATH       Use this rootfs instead of auto-detecting one
  --force             Rebuild the private runtime and replace both launchers
  --check             Read-only validation; no files are created or changed
  --no-integrate      Do not run mango-integrate
  --bootstrap-rootfs  Install archlinuxarm and Noctalia with proot-distro when
                      no usable rootfs exists (requires network). This is the
                      default when no rootfs is found.
  --no-bootstrap      Fail instead of bootstrapping when no rootfs is found
  --quiet             Suppress normal output
  -h, --help          Show this help

The rootfs is discovered from --rootfs, NOCTALIA_ROOTFS,
$PREFIX/var/lib/proot-distro/installed-rootfs/*, then
$PREFIX/var/lib/proot-distro/containers/*/rootfs.

Noctalia runs natively in Termux. proot-distro is only used for optional
rootfs setup and package installation.
EOF
}

quiet=0
force=0
check_only=0
do_integrate=1
bootstrap=auto
rootfs_arg=""

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

info() {
  if ((!quiet)); then
    printf '%s\n' "$*"
  fi
}

while (($#)); do
  case "$1" in
    --rootfs)
      (($# >= 2)) || die "--rootfs requires a path"
      rootfs_arg="$2"
      shift 2
      ;;
    --rootfs=*)
      rootfs_arg="${1#--rootfs=}"
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    --check)
      check_only=1
      shift
      ;;
    --no-integrate)
      do_integrate=0
      shift
      ;;
    --bootstrap-rootfs)
      bootstrap=1
      shift
      ;;
    --no-bootstrap)
      bootstrap=0
      shift
      ;;
    --quiet)
      quiet=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if (($#)); then
  die "unexpected argument: $1"
fi

if ((check_only)) && [[ $bootstrap == 1 ]]; then
  die "--check cannot be combined with --bootstrap-rootfs"
fi

if ! command -v proot-distro >/dev/null 2>&1; then
  info "proot-distro not found (optional unless --bootstrap-rootfs is used)"
fi
if ! command -v curl >/dev/null 2>&1 &&
   ! command -v wget >/dev/null 2>&1; then
  warn "neither curl nor wget is installed (optional for manual downloads)"
fi

priv_dir="$PREFIX/libexec/mango-termux"
libs_dir="$priv_dir/rootfs-libs"
egl_dir="$priv_dir/egl_vendor.d"
vulkan_dir="$priv_dir/vulkan/icd.d"
native_bin="$priv_dir/noctalia-native"
native_stamp="$native_bin.rootfs"
loader="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"

runtime_libs=(
  "libEGL_mesa.so.0"
  "libgallium-27*"
  "libLLVM.so.23.1"
  "libgbm.so.1"
  "libxml2.so.16"
  "libstdc++.so.6"
  "libgcc_s.so.1"
  "libz.so.1"
  "libzstd.so.1"
  "libffi.so.8"
  "libSPIRV-Tools.so"
  "libsensors.so.5"
  "libicuuc.so.78"
  "libicudata.so.78"
  "libedit.so.0"
  "libncursesw.so.6"
  "libwayland-*.so.0"
  "libwayland-*.so.1"
  "libexpat.so.1"
  "libdrm.so.2"
  "libdisplay-info.so.2"
  "libudev.so.1"
  "libvulkan_freedreno.so"
)

required_lib() {
  case "$1" in
    libEGL_mesa.so.0|libgallium-27*|libLLVM.so.23.1|libgbm.so.1|libstdc++.so.6|libgcc_s.so.1)
      return 0
      ;;
  esac
  return 1
}

declare -gA lib_paths_cache=()
declare -ga rootfs_lib_files=()
declare -ga FOUND_LIB_PATHS=()
rootfs_libs_scanned=""

rootfs_usable() {
  local rootfs="${1%/}"
  [[ -n $rootfs &&
     -x "$rootfs/usr/bin/noctalia" &&
     -e "$rootfs/lib/ld-linux-aarch64.so.1" &&
     -e "$rootfs/usr/lib/libstdc++.so.6" ]]
}

discover_rootfs() {
  local candidate
  for candidate in \
    "$PREFIX"/var/lib/proot-distro/installed-rootfs/* \
    "$PREFIX"/var/lib/proot-distro/containers/*/rootfs; do
    [[ -d $candidate ]] || continue
    if rootfs_usable "$candidate"; then
      printf '%s\n' "${candidate%/}"
      return 0
    fi
  done
  return 1
}

scan_rootfs_libs() {
  if [[ $rootfs_libs_scanned == "$ROOTFS" ]]; then
    return 0
  fi
  local dir file
  rootfs_lib_files=()
  lib_paths_cache=()
  for dir in "$ROOTFS/usr/lib" "$ROOTFS/usr/lib/aarch64-linux-gnu"; do
    [[ -d $dir ]] || continue
    for file in "$dir"/*; do
      [[ -e $file ]] || continue
      rootfs_lib_files+=("$file")
    done
  done
  rootfs_libs_scanned="$ROOTFS"
}

find_lib_paths() {
  local pattern="$1"
  local file base seen=":" out=""
  FOUND_LIB_PATHS=()
  if [[ -n ${lib_paths_cache[$pattern]+x} ]]; then
    if [[ -n ${lib_paths_cache[$pattern]} ]]; then
      mapfile -t FOUND_LIB_PATHS <<< "${lib_paths_cache[$pattern]%$'\n'}"
    fi
    return 0
  fi
  scan_rootfs_libs
  for file in ${rootfs_lib_files[@]+"${rootfs_lib_files[@]}"}; do
    base="${file##*/}"
    [[ $base == $pattern ]] || continue
    case "$seen" in
      *":$base:"*) continue ;;
    esac
    seen+="$base:"
    FOUND_LIB_PATHS+=("$file")
  done
  if ((${#FOUND_LIB_PATHS[@]})); then
    printf -v out '%s\n' "${FOUND_LIB_PATHS[@]}"
  fi
  lib_paths_cache[$pattern]="$out"
}

first_lib() {
  find_lib_paths "$1"
  ((${#FOUND_LIB_PATHS[@]})) || return 1
  printf '%s\n' "${FOUND_LIB_PATHS[0]}"
}

resolve_runtime_rootfs() {
  local discovered=""
  if [[ -n $rootfs_arg ]]; then
    ROOTFS="${rootfs_arg%/}"
    if ! rootfs_usable "$ROOTFS"; then
      if ((check_only)); then
        printf 'FAIL: rootfs is not usable: %s\n' "$ROOTFS" >&2
        return 1
      fi
      die "rootfs is not usable: $ROOTFS (need usr/bin/noctalia, lib/ld-linux-aarch64.so.1, usr/lib/libstdc++.so.6)"
    fi
    return 0
  fi

  if [[ -n ${NOCTALIA_ROOTFS:-} ]]; then
    ROOTFS="${NOCTALIA_ROOTFS%/}"
    if ! rootfs_usable "$ROOTFS"; then
      if ((check_only)); then
        printf 'FAIL: NOCTALIA_ROOTFS is not usable: %s\n' "$ROOTFS" >&2
        return 1
      fi
      die "NOCTALIA_ROOTFS is not usable: $ROOTFS"
    fi
    return 0
  fi

  discovered="$(discover_rootfs || true)"
  if [[ -z $discovered ]]; then
    if ((check_only)); then
      printf 'FAIL: no usable Noctalia rootfs found\n' >&2
      return 1
    fi
    return 1
  fi
  ROOTFS="$discovered"
  return 0
}

bootstrap_rootfs() {
  command -v proot-distro >/dev/null 2>&1 ||
    die "proot-distro is required for automatic rootfs bootstrap"
  local installed=0
  if [[ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/archlinuxarm" ||
        -d "$PREFIX/var/lib/proot-distro/containers/archlinuxarm" ]]; then
    installed=1
  fi
  if ((installed)); then
    info "archlinuxarm rootfs already exists; repairing Noctalia package..."
  else
    info "Installing archlinuxarm with proot-distro..."
    proot-distro install archlinuxarm ||
      die "proot-distro install archlinuxarm failed"
  fi
  info "Installing Noctalia in archlinuxarm..."
  proot-distro login archlinuxarm -- \
    bash -lc 'pacman -Syu --noconfirm && pacman -S --needed --noconfirm noctalia' ||
    die "Noctalia installation in archlinuxarm failed"
}

setup_private_runtime() {
  local pattern entry
  local -a missing_required=()

  mkdir -p "$priv_dir" "$libs_dir" "$egl_dir" "$vulkan_dir"

  for pattern in "${runtime_libs[@]}"; do
    find_lib_paths "$pattern"
    if ((${#FOUND_LIB_PATHS[@]} == 0)); then
      if required_lib "$pattern"; then
        missing_required+=("$pattern")
      else
        warn "rootfs does not provide $pattern; skipping private link"
      fi
      continue
    fi
    for entry in "${FOUND_LIB_PATHS[@]}"; do
      ln -sfn "$entry" "$libs_dir/${entry##*/}"
    done
  done

  if ((${#missing_required[@]})); then
    die "rootfs lacks required Mesa/runtime libraries: ${missing_required[*]}"
  fi

  local xml2=""
  xml2="$(first_lib 'libxml2.so.2' || true)"
  if [[ -z $xml2 ]]; then
    xml2="$(first_lib 'libxml2.so.16' || true)"
    if [[ -n $xml2 ]]; then
      info "private libxml2.so.2 compatibility: $xml2 (not global)"
    fi
  fi
  if [[ -n $xml2 ]]; then
    ln -sfn "$xml2" "$libs_dir/libxml2.so.2"
  else
    warn "rootfs has neither libxml2.so.2 nor libxml2.so.16"
  fi

  local egl_lib="" vk_lib=""
  egl_lib="$(first_lib 'libEGL_mesa.so.0' || true)"
  vk_lib="$(first_lib 'libvulkan_freedreno.so' || true)"
  if [[ -n $egl_lib ]]; then
    printf '{"file_format_version":"1.0.0","ICD":{"library_path":"%s"}}\n' \
      "$egl_lib" >"$egl_dir/50_mesa.json"
  else
    warn "rootfs does not provide libEGL_mesa.so.0; EGL manifest not written"
  fi
  if [[ -n $vk_lib ]]; then
    printf '{"file_format_version":"1.0.0","ICD":{"library_path":"%s"}}\n' \
      "$vk_lib" >"$vulkan_dir/freedreno_icd.aarch64.json"
  else
    warn "rootfs does not provide libvulkan_freedreno.so; Vulkan ICD not written"
  fi
}

runtime_rpath() {
  local rpath="$libs_dir:$PREFIX/glibc/lib:$ROOTFS/usr/lib:$ROOTFS/lib"
  local dir
  for dir in "$ROOTFS/usr/lib/aarch64-linux-gnu" \
             "$ROOTFS/lib/aarch64-linux-gnu"; do
    [[ -d $dir ]] && rpath="$rpath:$dir"
  done
  printf '%s\n' "$rpath"
}

write_runtime_env() {
  local runtime_env="$priv_dir/runtime.env"
  local tmp has_qt=0 libgl="" gbm=""
  local qml="" qt_plugin="" qt_platform=""

  if command -v readelf >/dev/null 2>&1 &&
     readelf -d "$ROOTFS/usr/bin/noctalia" 2>/dev/null |
       grep -q 'NEEDED.*libQt6'; then
    has_qt=1
  fi
  if [[ -d "$ROOTFS/usr/lib/dri" ]]; then
    libgl="$ROOTFS/usr/lib/dri"
  fi
  if [[ -d "$ROOTFS/usr/lib/gbm" ]]; then
    gbm="$ROOTFS/usr/lib/gbm"
  fi
  if ((has_qt)); then
    if [[ -d "$ROOTFS/usr/lib/qt6/qml" ]]; then
      qml="$ROOTFS/usr/lib/qt6/qml"
    fi
    if [[ -d "$ROOTFS/usr/lib/qt6/plugins" ]]; then
      qt_plugin="$ROOTFS/usr/lib/qt6/plugins"
    fi
    if [[ -d "$ROOTFS/usr/lib/qt6/plugins/platforms" ]]; then
      qt_platform="$ROOTFS/usr/lib/qt6/plugins/platforms"
    fi
  fi

  tmp="$(mktemp "$TMPDIR/.runtime.env.XXXXXX")"
  {
    printf 'NOCTALIA_ROOTFS=%q\n' "$ROOTFS"
    printf 'NOCTALIA_LOADER=%q\n' "$loader"
    printf 'NOCTALIA_RPATH=%q\n' "$(runtime_rpath)"
    printf 'NOCTALIA_NATIVE_BIN=%q\n' "$native_bin"
    printf 'NOCTALIA_ASSETS_DIR=%q\n' "$ROOTFS/usr/share/noctalia/assets"
    printf 'NOCTALIA_EGL_DIR=%q\n' "$egl_dir"
    printf 'NOCTALIA_LIBGL_DRIVERS=%q\n' "$libgl"
    printf 'NOCTALIA_GBM_BACKENDS=%q\n' "$gbm"
    printf 'NOCTALIA_HAS_QT=%d\n' "$has_qt"
    if ((has_qt)); then
      if [[ -n $qml ]]; then
        printf 'NOCTALIA_QML_IMPORT=%q\n' "$qml"
      fi
      if [[ -n $qt_plugin ]]; then
        printf 'NOCTALIA_QT_PLUGIN=%q\n' "$qt_plugin"
      fi
      if [[ -n $qt_platform ]]; then
        printf 'NOCTALIA_QT_PLATFORM_PLUGIN=%q\n' "$qt_platform"
      fi
      printf 'NOCTALIA_QML_CACHE=%q\n' "$HOME/.cache/noctalia/qmlcache"
      printf 'NOCTALIA_QT_LOGGING=%q\n' '*.debug=false'
    fi
  } >"$tmp"
  chmod 0644 "$tmp"
  if [[ -f $runtime_env ]] && cmp -s "$tmp" "$runtime_env"; then
    rm -f "$tmp"
    chmod 0644 "$runtime_env" 2>/dev/null || true
    info "runtime env is up to date: $runtime_env"
    return 0
  fi
  mv -f "$tmp" "$runtime_env"
  info "wrote runtime env: $runtime_env"
}

build_patched_cache() {
  local libstdcpp rpath tmp
  if ! command -v patchelf >/dev/null 2>&1; then
    warn "patchelf not found; patched fallback cache was not built"
    warn "  install it with: pkg install patchelf"
    return 0
  fi

  libstdcpp="$(readlink -f "$ROOTFS/usr/lib/libstdc++.so.6")"
  rpath="$(runtime_rpath)"

  if [[ -x $native_bin && -f $native_stamp ]] &&
     [[ "$(<"$native_stamp")" == "$ROOTFS" ]] &&
     [[ $native_bin -nt $ROOTFS/usr/bin/noctalia ]] &&
     [[ $native_bin -nt $libstdcpp ]] &&
     [[ $native_bin -nt $loader ]]; then
    info "patched fallback cache is up to date"
    return 0
  fi

  mkdir -p "$priv_dir"
  tmp="$(mktemp "$priv_dir/.noctalia-native.XXXXXX")"
  if ! cp "$ROOTFS/usr/bin/noctalia" "$tmp"; then
    rm -f "$tmp"
    warn "cannot copy $ROOTFS/usr/bin/noctalia; patched fallback not built"
    return 0
  fi
  chmod 0755 "$tmp"
  if ! patchelf --set-interpreter "$loader" --force-rpath \
       --set-rpath "$rpath" "$tmp"; then
    rm -f "$tmp"
    warn "patchelf failed to patch the fallback binary"
    return 0
  fi
  if ! patchelf --replace-needed libstdc++.so.6 "$libstdcpp" "$tmp"; then
    rm -f "$tmp"
    warn "patchelf failed to pin rootfs libstdc++"
    return 0
  fi
  mv -f "$tmp" "$native_bin"
  printf '%s\n' "$ROOTFS" >"$native_stamp"
  info "built patched fallback cache: $native_bin"
}

emit_launcher() {
  local out="$1"
  local launcher_shell="$PREFIX/bin/fish"
  if [[ ! -x $launcher_shell ]]; then
    launcher_shell="$PREFIX/bin/bash"
  fi
  {
    cat <<'LAUNCHER_HEAD'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

LAUNCHER_HEAD
    printf 'PREFIX=%q\n' "$PREFIX"
    printf 'HOME=%q\n' "${HOME:-$PREFIX/home}"
    printf 'SHELL=%q\n' "$launcher_shell"
    cat <<'LAUNCHER_BODY'
TMPDIR="$PREFIX/tmp"
XDG_RUNTIME_DIR="$PREFIX/tmp"
PATH="$PREFIX/bin:/system/bin:/system/xbin"

clear_foreign_env() {
  unset LD_LIBRARY_PATH LD_PRELOAD LIBGL_DRIVERS_PATH GBM_BACKENDS_PATH \
    MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER VK_DRIVER_FILES \
    VK_ICD_FILENAMES __EGL_VENDOR_LIBRARY_DIRS \
    __EGL_VENDOR_LIBRARY_FILENAMES FD_KGSL_DMABUF EGL_PLATFORM \
    MESA_DEBUG LIBGL_ALWAYS_SOFTWARE MESA_GL_VERSION_OVERRIDE \
    vblank_mode ZINK_DEBUG QML2_IMPORT_PATH QML_IMPORT_PATH \
    QML_DISK_CACHE_PATH QSG_RHI_BACKEND QT_QUICK_BACKEND \
    QT_PLUGIN_PATH QT_QPA_PLATFORM_PLUGIN_PATH QT_LOGGING_RULES \
    GTK_IM_MODULE GTK_IM_MODULES QT_IM_MODULE QT_IM_MODULES \
    SDL_IM_MODULE GLFW_IM_MODULE XMODIFIERS INPUT_METHOD \
    XKB_CONFIG_EXTRA_PATH XKB_DEFAULT_LAYOUT XKB_DEFAULT_VARIANT \
    XKB_DEFAULT_OPTIONS XKB_DEFAULT_RULES XKB_DEFAULT_MODEL \
    XKB_CONFIG_ROOT
  local name
  while IFS= read -r name; do
    unset "$name"
  done < <(compgen -v PROOT_ || true)
}

inherit_wayland="${WAYLAND_DISPLAY-}"
inherit_signature="${MANGO_INSTANCE_SIGNATURE-}"
requested_rootfs="${NOCTALIA_ROOTFS-}"

fixed_prefix="$PREFIX"
fixed_home="$HOME"
fixed_shell="$SHELL"

session="$PREFIX/tmp/mango-session.env"
if [[ -f $session ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$session"
  set +a
fi

if [[ -n $inherit_wayland ]]; then
  export WAYLAND_DISPLAY="$inherit_wayland"
fi
if [[ -n $inherit_signature ]]; then
  export MANGO_INSTANCE_SIGNATURE="$inherit_signature"
fi

PREFIX="$fixed_prefix"
HOME="$fixed_home"
SHELL="$fixed_shell"
TMPDIR="$PREFIX/tmp"
XDG_RUNTIME_DIR="$PREFIX/tmp"
PATH="$PREFIX/bin:/system/bin:/system/xbin"

# Noctalia runs with rootfs/glibc XKB paths; native clients must use the
# Termux xkeyboard-config tree and the layout exported by run-mango.sh.
export_native_xkb() {
  if [[ -d $PREFIX/share/X11/xkb ]]; then
    export XKB_CONFIG_ROOT="$PREFIX/share/X11/xkb"
  fi
  export XKB_DEFAULT_LAYOUT="${XKB_DEFAULT_LAYOUT:-us,ru}"
  export XKB_DEFAULT_OPTIONS="${XKB_DEFAULT_OPTIONS:-grp:win_space_toggle}"
  export XKB_DEFAULT_RULES="${XKB_DEFAULT_RULES:-evdev}"
  export XKB_DEFAULT_MODEL="${XKB_DEFAULT_MODEL:-pc105}"
}
export_native_xkb

# Noctalia resolves $TERMINAL first. Keep an existing usable value; otherwise
# fall back to a terminal that is actually installed in the Termux prefix.
if [[ -z ${TERMINAL:-} || ! -x ${TERMINAL:-} ]]; then
  unset TERMINAL
  for candidate in "$PREFIX/bin/noctalia-terminal" foot kitty ghostty \
    alacritty wezterm xterm; do
    if [[ $candidate == /* ]]; then
      if [[ -x $candidate ]]; then
        TERMINAL="$candidate"
        break
      fi
    elif found="$(command -v "$candidate" 2>/dev/null)" && [[ -n $found ]]; then
      TERMINAL="$found"
      break
    fi
  done
fi
if [[ -n ${TERMINAL:-} && -x ${TERMINAL:-} ]]; then
  export TERMINAL
else
  unset TERMINAL
fi

export HOME PREFIX TMPDIR XDG_RUNTIME_DIR PATH SHELL TERMINAL

runtime_env="$PREFIX/libexec/mango-termux/runtime.env"
if [[ ! -f $runtime_env ]]; then
  printf 'error: missing runtime env: %s\n' "$runtime_env" >&2
  printf '  re-run install-noctalia-termux.sh\n' >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$runtime_env"

if [[ -n $requested_rootfs && ${requested_rootfs%/} != "$NOCTALIA_ROOTFS" ]]; then
  printf 'error: NOCTALIA_ROOTFS=%s does not match installed rootfs %s\n' \
    "$requested_rootfs" "$NOCTALIA_ROOTFS" >&2
  printf '  re-run install-noctalia-termux.sh to change the rootfs\n' >&2
  exit 1
fi

if [[ ! -d $NOCTALIA_ROOTFS || ! -x $NOCTALIA_ROOTFS/usr/bin/noctalia ]]; then
  printf 'error: installed rootfs is not usable: %s\n' "$NOCTALIA_ROOTFS" >&2
  printf '  re-run install-noctalia-termux.sh\n' >&2
  exit 1
fi
if [[ ! -e $NOCTALIA_LOADER ]]; then
  printf 'error: Termux glibc loader not found at %s\n' "$NOCTALIA_LOADER" >&2
  printf '  re-run install-noctalia-termux.sh\n' >&2
  exit 1
fi

clear_foreign_env

# clear_foreign_env drops rootfs XKB state; restore the native values again.
export_native_xkb

export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
unset MESA_SHADER_CACHE_DISABLE MESA_GLSL_CACHE_DISABLE MESA_GLSL_VERSION_OVERRIDE
export MESA_SHADER_CACHE_DIR="$XDG_CACHE_HOME/mesa_shader_cache_noctalia"
export MESA_SHADER_CACHE_MAX_SIZE=256M

if [[ ${NOCTALIA_HAS_QT:-0} == 1 ]]; then
  export QT_LOGGING_RULES="${NOCTALIA_QT_LOGGING:-*.debug=false}"
  if [[ -n ${NOCTALIA_QML_CACHE:-} ]]; then
    export QML_DISK_CACHE_PATH="$NOCTALIA_QML_CACHE"
  fi
  if [[ -n ${NOCTALIA_QML_IMPORT:-} ]]; then
    export QML2_IMPORT_PATH="$NOCTALIA_QML_IMPORT"
    export QML_IMPORT_PATH="$NOCTALIA_QML_IMPORT"
  fi
  if [[ -n ${NOCTALIA_QT_PLUGIN:-} ]]; then
    export QT_PLUGIN_PATH="$NOCTALIA_QT_PLUGIN"
  fi
  if [[ -n ${NOCTALIA_QT_PLATFORM_PLUGIN:-} ]]; then
    export QT_QPA_PLATFORM_PLUGIN_PATH="$NOCTALIA_QT_PLATFORM_PLUGIN"
  fi
fi

if [[ -d $PREFIX/etc/fonts ]]; then
  export FONTCONFIG_PATH="$PREFIX/etc/fonts"
fi

export XDG_DATA_DIRS="$PREFIX/share"
export XDG_CONFIG_DIRS="$PREFIX/etc/xdg"
export NOCTALIA_ASSETS_DIR

if [[ -z ${TERM:-} || $TERM == dumb ]]; then
  TERM=xterm-256color
fi
export TERM
if [[ -d $PREFIX/share/terminfo ]]; then
  export TERMINFO="$PREFIX/share/terminfo"
fi
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-wayland}"

# These point inside the rootfs and are required by Noctalia itself.  Child
# applications are started through noctalia-exec, which drops them again.

export __EGL_VENDOR_LIBRARY_DIRS="$NOCTALIA_EGL_DIR"
unset __EGL_VENDOR_LIBRARY_FILENAMES
if [[ -n ${NOCTALIA_LIBGL_DRIVERS:-} ]]; then
  export LIBGL_DRIVERS_PATH="$NOCTALIA_LIBGL_DRIVERS"
fi
if [[ -n ${NOCTALIA_GBM_BACKENDS:-} ]]; then
  export GBM_BACKENDS_PATH="$NOCTALIA_GBM_BACKENDS"
fi

: "${WAYLAND_DISPLAY:=wayland-0}"
: "${DISPLAY:=:0}"
export WAYLAND_DISPLAY DISPLAY

dbus_required=1
case "${1:-}" in
  --version|-v|--help|-h|msg) dbus_required=0 ;;
esac
if ((dbus_required)) &&
   [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} && -z ${NOCTALIA_DBUS_WRAPPED:-} ]]; then
  if dbus_run="$(command -v dbus-run-session)"; then
    self="$0"
    case "$self" in
      /*) ;;
      */*) self="$PWD/$self" ;;
      *) self="$PREFIX/bin/$self" ;;
    esac
    export NOCTALIA_DBUS_WRAPPED=1
    exec "$dbus_run" -- "$self" "$@"
  fi
fi

launch_noctalia() {
  if [[ "${NOCTALIA_DIRECT_LOADER:-1}" != "0" ]]; then
    exec "$NOCTALIA_LOADER" --library-path "$NOCTALIA_RPATH" \
      "$NOCTALIA_ROOTFS/usr/bin/noctalia" "$@"
  fi
  if [[ ! -x $NOCTALIA_NATIVE_BIN ]]; then
    printf 'error: patched fallback binary not found: %s\n' "$NOCTALIA_NATIVE_BIN" >&2
    printf '  re-run install-noctalia-termux.sh\n' >&2
    exit 1
  fi
  exec "$NOCTALIA_NATIVE_BIN" "$@"
}

if [[ $# -eq 0 ]] && command -v flock >/dev/null 2>&1; then
  signature="${MANGO_INSTANCE_SIGNATURE:-}"
  lock_file="$XDG_RUNTIME_DIR/noctalia-${signature##*/}.lock"
  if [[ -d $XDG_RUNTIME_DIR && -w $XDG_RUNTIME_DIR ]] &&
     [[ ! -d $lock_file ]] &&
     ( : >>"$lock_file" ) 2>/dev/null; then
    lock_launch() {
      if ! flock -n 9; then
        printf 'noctalia: another instance is already running\n'
        exit 0
      fi
      launch_noctalia
    }
    if lock_launch 9>"$lock_file"; then
      :
    fi
  fi
fi

launch_noctalia "$@"
LAUNCHER_BODY
  } >"$out"
}

emit_noctalia_exec() {
  local out="$1"
  local src="$self_dir/termux-compat/noctalia-exec"
  if [[ ! -f $src ]]; then
    die "missing child-environment wrapper: $src"
  fi
  install -m 0755 "$src" "$out"
}

install_launchers() {
  local tmp bin_noctalia bin_mango bin_exec bin_terminal
  bin_noctalia="$PREFIX/bin/noctalia"
  bin_mango="$PREFIX/bin/mango-noctalia"
  bin_exec="$PREFIX/bin/noctalia-exec"
  bin_terminal="$PREFIX/bin/noctalia-terminal"

  mkdir -p "$PREFIX/bin" "$TMPDIR"
  tmp="$(mktemp "$TMPDIR/install-noctalia.XXXXXX")"
  emit_launcher "$tmp"
  chmod 0755 "$tmp"

  if [[ (-e $bin_noctalia || -L $bin_noctalia) &&
        ! -e $bin_noctalia.proot-bak &&
        ! -L $bin_noctalia.proot-bak ]] &&
     ! cmp -s "$tmp" "$bin_noctalia"; then
    cp -a "$bin_noctalia" "$bin_noctalia.proot-bak" ||
      warn "cannot back up $bin_noctalia"
  fi
  if [[ (-e $bin_mango || -L $bin_mango) &&
        ! -e $bin_mango.mango-bak &&
        ! -L $bin_mango.mango-bak ]] &&
     ! cmp -s "$tmp" "$bin_mango"; then
    cp -a "$bin_mango" "$bin_mango.mango-bak" ||
      warn "cannot back up $bin_mango"
  fi

  install -m 0755 "$tmp" "$bin_noctalia"
  install -m 0755 "$tmp" "$bin_mango"
  rm -f "$tmp"
  emit_noctalia_exec "$bin_exec"

  local terminal_src="$self_dir/termux-compat/noctalia-terminal"
  if [[ ! -f $terminal_src ]]; then
    die "missing terminal wrapper: $terminal_src"
  fi
  install -m 0755 "$terminal_src" "$bin_terminal"

  cmp -s "$bin_noctalia" "$bin_mango" ||
    die "installed Noctalia launchers differ: $bin_noctalia $bin_mango"
  info "installed launcher: $bin_noctalia"
  info "installed launcher: $bin_mango"
  info "installed child wrapper: $bin_exec"
  info "installed terminal wrapper: $bin_terminal"
}

ensure_noctalia_child_command() {
  local wrapper="$PREFIX/bin/noctalia-exec"
  local file tmp
  local command='launch_apps_custom_command = "noctalia-exec $CMD"'

  [[ -x $wrapper ]] || return 0

  for file in "$HOME/.local/state/noctalia/settings.toml" \
              "$HOME/.config/noctalia/settings.toml"; do
    [[ -f $file ]] || continue
    grep -Fqx "$command" "$file" && continue

    tmp="$(mktemp "${file}.tmp.XXXXXX" 2>/dev/null)" || {
      warn "cannot create temporary file for: $file"
      continue
    }
    if ! awk -v cmd="$command" '
      BEGIN { in_shell = 0; wrote = 0 }
      /^\[shell\][[:space:]]*$/ {
        in_shell = 1
        print
        if (!wrote) { print cmd; wrote = 1 }
        next
      }
      /^\[/ { in_shell = 0 }
      in_shell && /^[[:space:]]*launch_apps_custom_command[[:space:]]*=/ { next }
      { print }
      END {
        if (!wrote) {
          print ""
          print "[shell]"
          print cmd
        }
      }
    ' "$file" >"$tmp" 2>/dev/null; then
      rm -f "$tmp"
      warn "cannot rewrite Noctalia settings: $file"
      continue
    fi

    if cmp -s "$file" "$tmp"; then
      rm -f "$tmp"
      continue
    fi
    chmod --reference="$file" "$tmp" 2>/dev/null || true
    backup_once "$file" || {
      rm -f "$tmp"
      continue
    }
    if ! mv "$tmp" "$file" 2>/dev/null; then
      rm -f "$tmp"
      warn "cannot replace: $file"
      continue
    fi
    info "routed Noctalia app launches through noctalia-exec: $file"
  done
}

# The bar is a layer-shell surface.  Without reserve_space the compositor does
# not shrink the usable area and client titlebars are drawn underneath it.
ensure_noctalia_bar_reserve() {
  local file tmp

  for file in "$HOME/.local/state/noctalia/settings.toml" \
              "$HOME/.config/noctalia/settings.toml"; do
    [[ -f $file ]] || continue

    tmp="$(mktemp "${file}.tmp.XXXXXX" 2>/dev/null)" || {
      warn "cannot create temporary file for: $file"
      continue
    }
    if ! awk '
      /^\[bar\.[^.]]+\][[:space:]]*$/ { in_bar = 1; print; next }
      /^\[/ { in_bar = 0 }
      in_bar && /^[[:space:]]*reserve_space[[:space:]]*=/ {
        if ($0 !~ /=[[:space:]]*true[[:space:]]*$/) {
          match($0, /^[[:space:]]*/)
          print substr($0, 1, RLENGTH) "reserve_space = true"
          next
        }
      }
      { print }
    ' "$file" >"$tmp" 2>/dev/null; then
      rm -f "$tmp"
      warn "cannot rewrite Noctalia settings: $file"
      continue
    fi

    if cmp -s "$file" "$tmp"; then
      rm -f "$tmp"
      continue
    fi
    chmod --reference="$file" "$tmp" 2>/dev/null || true
    backup_once "$file" || {
      rm -f "$tmp"
      continue
    }
    if ! mv "$tmp" "$file" 2>/dev/null; then
      rm -f "$tmp"
      warn "cannot replace: $file"
      continue
    fi
    info "reserved space for Noctalia bars: $file"
  done
}

warm_caches() {
  mkdir -p "$HOME/.cache/mesa_shader_cache_noctalia" \
    "$HOME/.cache/noctalia/qmlcache" \
    "$PREFIX/var/cache/noctalia" 2>/dev/null || true
  if command -v fc-cache >/dev/null 2>&1; then
    fc-cache -s >/dev/null 2>&1 || true
  fi
}

backup_once() {
  local file="$1"
  local backup="$file.mango-bak"
  if [[ -e $backup || -L $backup ]]; then
    return 0
  fi
  cp -a "$file" "$backup" 2>/dev/null || {
    warn "cannot create backup: $backup"
    return 1
  }
}

migrate_noctalia_dirs() {
  local rel src dst
  for rel in .config/noctalia .local/state/noctalia .local/share/noctalia; do
    src="$ROOTFS/root/$rel"
    dst="$HOME/$rel"
    [[ -e $src || -L $src ]] || continue
    if [[ -e $dst || -L $dst ]]; then
      info "native Noctalia path exists, not overwriting: $dst"
      continue
    fi
    mkdir -p "${dst%/*}" 2>/dev/null || {
      warn "cannot create directory: ${dst%/*}"
      continue
    }
    if ! mv "$src" "$dst" 2>/dev/null; then
      warn "cannot migrate Noctalia path: $src"
    else
      info "migrated Noctalia path: $dst"
    fi
  done
}

migrate_walls_and_settings() {
  local src="$ROOTFS/root/Walls"
  local dst="$HOME/Walls"
  local file base tmp

  if [[ -d $src ]]; then
    mkdir -p "$dst"
    while IFS= read -r -d '' file; do
      base="${file##*/}"
      [[ -e $dst/$base ]] && continue
      if ! cp -a "$file" "$dst/$base" 2>/dev/null; then
        warn "cannot copy wallpaper: $file"
      else
        info "copied wallpaper: $dst/$base"
      fi
    done < <(find "$src" -maxdepth 1 -type f -print0 2>/dev/null)
  fi

  for file in "$HOME/.local/state/noctalia/settings.toml" \
              "$HOME/.config/noctalia/settings.toml"; do
    [[ -f $file ]] || continue
    grep -q '/root/' "$file" || continue
    tmp="$(mktemp "${file}.tmp.XXXXXX" 2>/dev/null)" || {
      warn "cannot create temporary file for: $file"
      continue
    }
    if ! sed "s|/root/|$HOME/|g" "$file" >"$tmp" 2>/dev/null; then
      rm -f "$tmp"
      warn "cannot rewrite Noctalia paths: $file"
      continue
    fi
    if cmp -s "$file" "$tmp"; then
      rm -f "$tmp"
      continue
    fi
    chmod --reference="$file" "$tmp" 2>/dev/null || true
    backup_once "$file" || {
      rm -f "$tmp"
      continue
    }
    if ! mv "$tmp" "$file" 2>/dev/null; then
      rm -f "$tmp"
      warn "cannot replace: $file"
      continue
    fi
    info "rewrote /root/ paths: $file"
  done
}

patch_start_shim() {
  local file="$HOME/.config/mango/start-noctalia.sh"
  local tmp
  [[ -f $file ]] || return 0
  grep -q 'proot-distro' "$file" || return 0

  tmp="$(mktemp "${file}.tmp.XXXXXX" 2>/dev/null)" || {
    warn "cannot create temporary file for: $file"
    return 0
  }
  {
    printf '#!/data/data/com.termux/files/usr/bin/bash\n'
    printf 'exec "%s/bin/noctalia" "$@"\n' "$PREFIX"
  } >"$tmp" 2>/dev/null || {
    rm -f "$tmp"
    warn "cannot write native Noctalia shim: $tmp"
    return 0
  }
  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  if ! backup_once "$file"; then
    rm -f "$tmp"
    return 0
  fi
  chmod 0755 "$tmp"
  if ! mv "$tmp" "$file" 2>/dev/null; then
    rm -f "$tmp"
    warn "cannot replace: $file"
    return 0
  fi
  info "rewrote native Noctalia shim: $file"
}

patch_mics_config() {
  local file="$HOME/.config/mango/mics.conf"
  local tmp

  if [[ ! -f $file ]]; then
    mkdir -p "${file%/*}"
    printf 'exec=noctalia\n' >"$file"
    info "created Noctalia autostart: $file"
    return 0
  fi

  tmp="$(mktemp "${file}.tmp.XXXXXX" 2>/dev/null)" || {
    warn "cannot create temporary file for: $file"
    return 0
  }
  if ! awk '
    /^[[:space:]]*exec[[:space:]]*=[[:space:]]*.*(start-noctalia\.sh|proot-distro|\/usr\/bin\/noctalia)/ {
      print "exec=noctalia"
      seen = 1
      next
    }
    /^[[:space:]]*exec[[:space:]]*=/ { seen = 1 }
    { print }
    END { if (!seen) print "exec=noctalia" }
  ' "$file" >"$tmp" 2>/dev/null; then
    rm -f "$tmp"
    warn "cannot rewrite: $file"
    return 0
  fi
  if cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  chmod --reference="$file" "$tmp" 2>/dev/null || true
  if ! backup_once "$file"; then
    rm -f "$tmp"
    return 0
  fi
  if ! mv "$tmp" "$file" 2>/dev/null; then
    rm -f "$tmp"
    warn "cannot replace: $file"
    return 0
  fi
  info "updated Noctalia autostart: $file"
}

run_mango_integrate() {
  local integrate=""
  if [[ -x "$PREFIX/bin/mango-integrate" ]]; then
    integrate="$PREFIX/bin/mango-integrate"
  elif [[ -x "$self_dir/termux-compat/mango-integrate" ]]; then
    integrate="$self_dir/termux-compat/mango-integrate"
  fi
  if [[ -z $integrate ]]; then
    return 0
  fi
  if ! "$integrate" --quiet; then
    warn "mango-integrate failed; continuing"
  fi
}

check_pass() {
  printf 'OK: %s\n' "$*"
}

check_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  check_failed=1
}

run_check() {
  check_failed=0
  local rootfs="$ROOTFS"
  local runtime_env egl_lib vk_lib pattern entry
  local -a missing=()

  check_pass "rootfs: $rootfs"

  if command -v patchelf >/dev/null 2>&1; then
    check_pass "patchelf: $(command -v patchelf)"
  else
    check_fail "patchelf not found (patched fallback unavailable)"
  fi

  if command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1; then
    check_pass "download tool available (curl or wget)"
  else
    info "optional download tool not found (curl/wget)"
  fi

  if command -v proot-distro >/dev/null 2>&1; then
    check_pass "proot-distro available for --bootstrap-rootfs"
  else
    info "optional proot-distro not found"
  fi

  if [[ -e $loader ]]; then
    check_pass "Termux loader: $loader"
  else
    check_fail "Termux loader missing: $loader"
  fi

  if [[ -e $rootfs/usr/lib/libstdc++.so.6 ]]; then
    check_pass "rootfs libstdc++: $rootfs/usr/lib/libstdc++.so.6"
  else
    check_fail "rootfs libstdc++ missing: $rootfs/usr/lib/libstdc++.so.6"
  fi

  for entry in "$priv_dir" "$libs_dir" "$egl_dir" "$vulkan_dir"; do
    if [[ -d $entry ]]; then
      check_pass "private directory: $entry"
    else
      check_fail "private directory missing: $entry"
    fi
  done

  for pattern in "${runtime_libs[@]}"; do
    find_lib_paths "$pattern"
    if ((${#FOUND_LIB_PATHS[@]} == 0)); then
      if required_lib "$pattern"; then
        check_fail "rootfs library missing: $pattern"
      else
        missing+=("$pattern")
      fi
      continue
    fi
    for entry in "${FOUND_LIB_PATHS[@]}"; do
      if [[ -e "$libs_dir/${entry##*/}" ]]; then
        check_pass "private link: ${entry##*/}"
      else
        check_fail "private link missing: $libs_dir/${entry##*/}"
      fi
    done
  done

  egl_lib="$(first_lib 'libEGL_mesa.so.0' || true)"
  vk_lib="$(first_lib 'libvulkan_freedreno.so' || true)"
  if [[ -z $egl_lib ]]; then
    check_fail "rootfs library missing: libEGL_mesa.so.0"
  fi
  if [[ -z $vk_lib ]]; then
    check_fail "rootfs library missing: libvulkan_freedreno.so"
  fi

  if [[ -n $egl_lib && -f $egl_dir/50_mesa.json ]] &&
     grep -Fq "\"library_path\":\"$egl_lib\"" "$egl_dir/50_mesa.json"; then
    check_pass "EGL manifest: $egl_dir/50_mesa.json"
  else
    check_fail "EGL manifest missing or incorrect: $egl_dir/50_mesa.json"
  fi

  if [[ -n $vk_lib && -f $vulkan_dir/freedreno_icd.aarch64.json ]] &&
     grep -Fq "\"library_path\":\"$vk_lib\"" \
       "$vulkan_dir/freedreno_icd.aarch64.json"; then
    check_pass "Vulkan ICD: $vulkan_dir/freedreno_icd.aarch64.json"
  else
    check_fail "Vulkan ICD missing or incorrect: $vulkan_dir/freedreno_icd.aarch64.json"
  fi

  if [[ -n $egl_lib ]]; then
    if [[ -e $libs_dir/libxml2.so.2 ]]; then
      check_pass "private libxml2.so.2 compatibility: $libs_dir/libxml2.so.2"
    else
      check_fail "private libxml2.so.2 compatibility missing: $libs_dir/libxml2.so.2"
    fi
  fi

  if [[ -f $PREFIX/bin/noctalia && ! -L $PREFIX/bin/noctalia &&
        -x $PREFIX/bin/noctalia ]]; then
    check_pass "launcher executable: $PREFIX/bin/noctalia"
  else
    check_fail "launcher missing, not a regular file, or not executable: $PREFIX/bin/noctalia"
  fi

  if [[ -f $PREFIX/bin/mango-noctalia && ! -L $PREFIX/bin/mango-noctalia &&
        -x $PREFIX/bin/mango-noctalia ]]; then
    check_pass "launcher executable: $PREFIX/bin/mango-noctalia"
  else
    check_fail "launcher missing, not a regular file, or not executable: $PREFIX/bin/mango-noctalia"
  fi

  if [[ -f $PREFIX/bin/noctalia && ! -L $PREFIX/bin/noctalia &&
        -f $PREFIX/bin/mango-noctalia && ! -L $PREFIX/bin/mango-noctalia ]] &&
     cmp -s "$PREFIX/bin/noctalia" "$PREFIX/bin/mango-noctalia"; then
    check_pass "launchers are byte-identical"
  else
    check_fail "launchers are not byte-identical"
  fi

  if [[ -x $PREFIX/bin/noctalia-exec ]]; then
    check_pass "child wrapper executable: $PREFIX/bin/noctalia-exec"
  else
    check_fail "child wrapper missing or not executable: $PREFIX/bin/noctalia-exec"
  fi

  if [[ -f $PREFIX/bin/noctalia ]] &&
     grep -Fq 'export XDG_DATA_DIRS="$PREFIX/share"' "$PREFIX/bin/noctalia" &&
     ! grep -Fq 'XDG_DATA_DIRS="$PREFIX/share:$NOCTALIA_ROOTFS' "$PREFIX/bin/noctalia"; then
    check_pass "launcher keeps rootfs paths out of XDG_DATA_DIRS"
  else
    check_fail "launcher still exports rootfs paths in XDG_DATA_DIRS"
  fi

  runtime_env="$priv_dir/runtime.env"
  if [[ -f $runtime_env ]] &&
     ( set +u; source "$runtime_env" 2>/dev/null;
       [[ ${NOCTALIA_ROOTFS:-} == "$rootfs" ]] ); then
    check_pass "runtime env matches rootfs: $runtime_env"
  else
    check_fail "runtime env missing or stale: $runtime_env"
  fi

  if [[ -f $PREFIX/bin/noctalia ]] &&
     grep -Fq 'libexec/mango-termux/runtime.env' "$PREFIX/bin/noctalia"; then
    check_pass "launcher sources precomputed runtime env"
  else
    check_fail "launcher does not use precomputed runtime env"
  fi

  if [[ -x $PREFIX/bin/mango-integrate ]]; then
    if "$PREFIX/bin/mango-integrate" --check >/dev/null 2>&1; then
      check_pass "mango-integrate --check"
    else
      check_fail "mango-integrate --check"
    fi
  fi

  if ((${#missing[@]})); then
    info "optional rootfs libraries not present: ${missing[*]}"
  fi

  return "$check_failed"
}

if ! resolve_runtime_rootfs; then
  if ((check_only)); then
    exit 1
  fi
  if [[ $bootstrap == 0 ]]; then
    die "no usable Noctalia rootfs found; use --rootfs PATH or --bootstrap-rootfs"
  fi
  if [[ -n $rootfs_arg || -n ${NOCTALIA_ROOTFS:-} ]]; then
    die "the requested rootfs is not usable; refusing automatic bootstrap"
  fi
  info "No usable rootfs found; starting automatic bootstrap."
  bootstrap_rootfs
  if ! resolve_runtime_rootfs; then
    die "no usable Noctalia rootfs found after bootstrap"
  fi
fi

if ((check_only)); then
  run_check
  exit $?
fi

info "Noctalia rootfs: $ROOTFS"

if ((force)); then
  info "rebuilding private runtime: $priv_dir"
  rm -rf "$priv_dir"
fi

setup_private_runtime
build_patched_cache
write_runtime_env

if ((do_integrate)); then
  run_mango_integrate
fi

migrate_noctalia_dirs
migrate_walls_and_settings
patch_start_shim
patch_mics_config
install_launchers
ensure_noctalia_child_command
ensure_noctalia_bar_reserve
warm_caches

info "Noctalia is installed natively. Start it with: noctalia"
info "Set NOCTALIA_DIRECT_LOADER=0 to use the patched fallback cache."
