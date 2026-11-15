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
                      no usable rootfs exists (requires network)
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
bootstrap=0
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

if ((check_only && bootstrap)); then
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

find_lib_paths() {
  local pattern="$1"
  local dir match base seen=""
  for dir in "$ROOTFS/usr/lib" "$ROOTFS/usr/lib/aarch64-linux-gnu"; do
    [[ -d $dir ]] || continue
    for match in "$dir"/$pattern; do
      [[ -e $match ]] || continue
      base="${match##*/}"
      case ":$seen:" in
        *":$base:"*) continue ;;
      esac
      seen="$seen:$base"
      printf '%s\n' "$match"
    done
  done
}

first_lib() {
  local path
  while IFS= read -r path; do
    printf '%s\n' "$path"
    return 0
  done < <(find_lib_paths "$1")
  return 1
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
    die "proot-distro is required by --bootstrap-rootfs"
  info "Installing archlinuxarm with proot-distro..."
  proot-distro install archlinuxarm ||
    die "proot-distro install archlinuxarm failed"
  info "Installing Noctalia in archlinuxarm..."
  proot-distro login archlinuxarm -- \
    bash -lc 'pacman -Syu --noconfirm && pacman -S --needed --noconfirm noctalia' ||
    die "Noctalia installation in archlinuxarm failed"
}

setup_private_runtime() {
  local pattern entry
  local -a matches=()
  local -a missing_required=()

  mkdir -p "$priv_dir" "$libs_dir" "$egl_dir" "$vulkan_dir"

  for pattern in "${runtime_libs[@]}"; do
    matches=()
    mapfile -t matches < <(find_lib_paths "$pattern")
    if ((${#matches[@]} == 0)); then
      if required_lib "$pattern"; then
        missing_required+=("$pattern")
      else
        warn "rootfs does not provide $pattern; skipping private link"
      fi
      continue
    fi
    for entry in "${matches[@]}"; do
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

launcher_template() {
  cat <<'LAUNCHER_EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PREFIX="__PREFIX__"
embedded_rootfs="__ROOTFS__"
HOME="${HOME:-__HOME__}"
TMPDIR="$PREFIX/tmp"
XDG_RUNTIME_DIR="$PREFIX/tmp"
PATH="$PREFIX/bin:/system/bin:/system/xbin"
loader="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"

clear_foreign_env() {
  unset LD_LIBRARY_PATH LD_PRELOAD LIBGL_DRIVERS_PATH GBM_BACKENDS_PATH \
    MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER VK_DRIVER_FILES \
    VK_ICD_FILENAMES __EGL_VENDOR_LIBRARY_DIRS \
    __EGL_VENDOR_LIBRARY_FILENAMES FD_KGSL_DMABUF EGL_PLATFORM
  local name
  while IFS= read -r name; do
    unset "$name"
  done < <(compgen -v PROOT_ || true)
}

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

find_lib_paths() {
  local pattern="$1"
  local dir match base seen=""
  for dir in "$rootfs/usr/lib" "$rootfs/usr/lib/aarch64-linux-gnu"; do
    [[ -d $dir ]] || continue
    for match in "$dir"/$pattern; do
      [[ -e $match ]] || continue
      base="${match##*/}"
      case ":$seen:" in
        *":$base:"*) continue ;;
      esac
      seen="$seen:$base"
      printf '%s\n' "$match"
    done
  done
}

ensure_private_runtime() {
  local native_dir="$PREFIX/libexec/mango-termux"
  local libs_dir="$native_dir/rootfs-libs"
  local egl_dir="$native_dir/egl_vendor.d"
  local vulkan_dir="$native_dir/vulkan/icd.d"
  local pattern match entry target
  local -a matches=()

  mkdir -p "$libs_dir" "$egl_dir" "$vulkan_dir"

  for pattern in \
    libEGL_mesa.so.0 'libgallium-27*' libLLVM.so.23.1 libgbm.so.1 \
    libxml2.so.16 libstdc++.so.6 libgcc_s.so.1 libz.so.1 libzstd.so.1 \
    libffi.so.8 libSPIRV-Tools.so libsensors.so.5 libicuuc.so.78 \
    libicudata.so.78 libedit.so.0 libncursesw.so.6 \
    'libwayland-*.so.0' 'libwayland-*.so.1' libexpat.so.1 libdrm.so.2 \
    libdisplay-info.so.2 libudev.so.1 libvulkan_freedreno.so; do
    matches=()
    mapfile -t matches < <(find_lib_paths "$pattern")
    for entry in ${matches[@]+"${matches[@]}"}; do
      ln -sfn "$entry" "$libs_dir/${entry##*/}"
    done
  done

  target=""
  while IFS= read -r match; do
    target="$match"
    break
  done < <(find_lib_paths libxml2.so.2)
  if [[ -z $target ]]; then
    while IFS= read -r match; do
      target="$match"
      break
    done < <(find_lib_paths libxml2.so.16)
  fi
  if [[ -n $target ]]; then
    ln -sfn "$target" "$libs_dir/libxml2.so.2"
  fi

  target=""
  while IFS= read -r match; do
    target="$match"
    break
  done < <(find_lib_paths libEGL_mesa.so.0)
  if [[ -n $target ]]; then
    printf '{"file_format_version":"1.0.0","ICD":{"library_path":"%s"}}\n' \
      "$target" >"$egl_dir/50_mesa.json"
  fi

  target=""
  while IFS= read -r match; do
    target="$match"
    break
  done < <(find_lib_paths libvulkan_freedreno.so)
  if [[ -n $target ]]; then
    printf '{"file_format_version":"1.0.0","ICD":{"library_path":"%s"}}\n' \
      "$target" >"$vulkan_dir/freedreno_icd.aarch64.json"
  fi
}

extend_paths() {
  local out="$1" dir
  local -a extra
  IFS=: read -ra extra <<< "${2:-}"
  for dir in ${extra[@]+"${extra[@]}"}; do
    [[ -n $dir ]] || continue
    case ":$out:" in
      *":$dir:"*) continue ;;
    esac
    out="$out:$dir"
  done
  printf '%s' "$out"
}

clear_foreign_env

rootfs="${NOCTALIA_ROOTFS:-$embedded_rootfs}"
rootfs="${rootfs%/}"
if [[ -n ${NOCTALIA_ROOTFS:-} ]]; then
  if ! rootfs_usable "$rootfs"; then
    printf 'error: NOCTALIA_ROOTFS=%s lacks usr/bin/noctalia, lib/ld-linux-aarch64.so.1, or usr/lib/libstdc++.so.6\n' \
      "$rootfs" >&2
    exit 1
  fi
elif ! rootfs_usable "$rootfs"; then
  rootfs="$(discover_rootfs || true)"
  if [[ -z $rootfs ]]; then
    printf 'error: no usable Noctalia rootfs found\n' >&2
    printf '  set NOCTALIA_ROOTFS or re-run install-noctalia-termux.sh\n' >&2
    exit 1
  fi
fi

if [[ ! -e $loader ]]; then
  printf 'error: Termux glibc loader not found at %s\n' "$loader" >&2
  exit 1
fi

libstdcpp="$rootfs/usr/lib/libstdc++.so.6"
if [[ ! -e $libstdcpp ]]; then
  printf 'error: rootfs libstdc++ not found at %s\n' "$libstdcpp" >&2
  exit 1
fi
libstdcpp="$(readlink -f "$libstdcpp")"

session="$PREFIX/tmp/mango-session.env"
if [[ -f $session ]]; then
  set -a
  source "$session"
  set +a
fi

export HOME PREFIX TMPDIR XDG_RUNTIME_DIR PATH
SHELL="$PREFIX/bin/fish"
[[ -x $SHELL ]] || SHELL="$PREFIX/bin/bash"
export SHELL

clear_foreign_env
ensure_private_runtime

native_dir="$PREFIX/libexec/mango-termux"
libs_dir="$native_dir/rootfs-libs"
egl_dir="$native_dir/egl_vendor.d"
vulkan_dir="$native_dir/vulkan/icd.d"

rpath="$libs_dir:$PREFIX/glibc/lib:$rootfs/usr/lib:$rootfs/lib"
for dir in "$rootfs/usr/lib/aarch64-linux-gnu" \
           "$rootfs/lib/aarch64-linux-gnu"; do
  [[ -d $dir ]] && rpath="$rpath:$dir"
done

export __EGL_VENDOR_LIBRARY_DIRS="$egl_dir"
unset __EGL_VENDOR_LIBRARY_FILENAMES
export VK_ICD_FILENAMES="$vulkan_dir/freedreno_icd.aarch64.json"
export VK_DRIVER_FILES="$VK_ICD_FILENAMES"
if [[ -d "$rootfs/usr/lib/dri" ]]; then
  export LIBGL_DRIVERS_PATH="$rootfs/usr/lib/dri"
fi
if [[ -d "$rootfs/usr/lib/gbm" ]]; then
  export GBM_BACKENDS_PATH="$rootfs/usr/lib/gbm"
fi

: "${WAYLAND_DISPLAY:=wayland-0}"
: "${DISPLAY:=:0}"
export WAYLAND_DISPLAY DISPLAY
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
XDG_DATA_DIRS="$(extend_paths "$PREFIX/share:$rootfs/usr/share" "${XDG_DATA_DIRS:-}")"
XDG_CONFIG_DIRS="$(extend_paths "$PREFIX/etc/xdg:$rootfs/etc/xdg" "${XDG_CONFIG_DIRS:-}")"
export XDG_DATA_DIRS XDG_CONFIG_DIRS
export NOCTALIA_ASSETS_DIR="$rootfs/usr/share/noctalia/assets"
if [[ -d "$PREFIX/etc/fonts" ]]; then
  export FONTCONFIG_PATH="$PREFIX/etc/fonts"
fi

if [[ -d "$rootfs/usr/lib/qt6/qml" ]]; then
  export QML2_IMPORT_PATH="$rootfs/usr/lib/qt6/qml"
  export QML_IMPORT_PATH="$QML2_IMPORT_PATH"
fi
if [[ -d "$rootfs/usr/lib/qt6/plugins" ]]; then
  export QT_PLUGIN_PATH="$rootfs/usr/lib/qt6/plugins"
fi
if [[ -d "$rootfs/usr/lib/qt6/plugins/platforms" ]]; then
  export QT_QPA_PLATFORM_PLUGIN_PATH="$rootfs/usr/lib/qt6/plugins/platforms"
fi

if [[ -z ${DBUS_SESSION_BUS_ADDRESS:-} && -z ${NOCTALIA_DBUS_WRAPPED:-} ]]; then
  if dbus_run="$(command -v dbus-run-session)"; then
    self="${BASH_SOURCE[0]}"
    if [[ $self != /* ]]; then
      if [[ $self == */* ]]; then
        self="$PWD/$self"
      else
        self="$(command -v -- "$self" || printf '%s' "$PWD/$self")"
      fi
    fi
    export NOCTALIA_DBUS_WRAPPED=1
    exec "$dbus_run" -- "$self" "$@"
  fi
fi

if [[ "${NOCTALIA_DIRECT_LOADER:-1}" != "0" ]]; then
  exec "$loader" --library-path "$rpath" "$rootfs/usr/bin/noctalia" "$@"
fi

native_bin="$native_dir/noctalia-native"
if [[ ! -x $native_bin ]]; then
  printf 'error: patched fallback binary not found: %s\n' "$native_bin" >&2
  printf '  re-run install-noctalia-termux.sh without NOCTALIA_DIRECT_LOADER=0\n' >&2
  exit 1
fi
exec "$native_bin" "$@"
LAUNCHER_EOF
}

install_launchers() {
  local template tmp bin_noctalia bin_mango
  bin_noctalia="$PREFIX/bin/noctalia"
  bin_mango="$PREFIX/bin/mango-noctalia"

  template="$(launcher_template)"
  template="${template//__PREFIX__/$PREFIX}"
  template="${template//__ROOTFS__/$ROOTFS}"
  template="${template//__HOME__/$HOME}"

  mkdir -p "$PREFIX/bin" "$TMPDIR"
  tmp="$(mktemp "$TMPDIR/install-noctalia.XXXXXX")"
  printf '%s\n' "$template" >"$tmp"
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

  cmp -s "$bin_noctalia" "$bin_mango" ||
    die "installed Noctalia launchers differ: $bin_noctalia $bin_mango"
  info "installed launcher: $bin_noctalia"
  info "installed launcher: $bin_mango"
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
  local rpath libstdcpp egl_lib vk_lib pattern entry
  local -a matches=()
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
    matches=()
    mapfile -t matches < <(find_lib_paths "$pattern")
    if ((${#matches[@]} == 0)); then
      if required_lib "$pattern"; then
        check_fail "rootfs library missing: $pattern"
      else
        missing+=("$pattern")
      fi
      continue
    fi
    for entry in "${matches[@]}"; do
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

  libstdcpp="$(readlink -f "$rootfs/usr/lib/libstdc++.so.6" 2>/dev/null || true)"
  rpath="$(runtime_rpath)"
  if [[ -e $loader && -n $libstdcpp && -x $rootfs/usr/bin/noctalia ]]; then
    if command -v timeout >/dev/null 2>&1; then
      if timeout 15 "$loader" --library-path "$rpath" \
           "$rootfs/usr/bin/noctalia" --version >/dev/null 2>&1; then
        check_pass "direct loader --version"
      else
        check_fail "direct loader --version failed or timed out"
      fi
    elif "$loader" --library-path "$rpath" \
         "$rootfs/usr/bin/noctalia" --version >/dev/null 2>&1; then
      check_pass "direct loader --version"
    else
      check_fail "direct loader --version failed"
    fi
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
  if ((bootstrap)); then
    bootstrap_rootfs
    if ! resolve_runtime_rootfs; then
      die "no usable Noctalia rootfs found after bootstrap"
    fi
  else
    die "no usable Noctalia rootfs found; use --rootfs PATH or --bootstrap-rootfs"
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

if ((do_integrate)); then
  run_mango_integrate
fi

migrate_noctalia_dirs
migrate_walls_and_settings
patch_start_shim
patch_mics_config
install_launchers

info "Noctalia is installed natively. Start it with: noctalia"
info "Set NOCTALIA_DIRECT_LOADER=0 to use the patched fallback cache."
