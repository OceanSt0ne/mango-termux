#!/data/data/com.termux/files/usr/bin/bash
#
# Build mango for Termux (wlroots X11 backend + Termux:X11).
#
#   ./build-termux.sh
#
# The script builds the bundled, pre-patched scenefx 0.5 sources from
# scenefx/ and then mango itself. It installs both into $PREFIX and creates
# the private GPU libraries used by mango-termux for effects.
#
# Environment:
#   PREFIX        Termux prefix (default: /data/data/com.termux/files/usr)
#   SCENEFX_DIR   alternative scenefx source tree (default: <repository>/scenefx)
set -euo pipefail

# Resolve our own path so the script works from any cwd and through symlinks.
self_path="$0"
if command -v readlink >/dev/null 2>&1; then
  self_path="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"
fi
self_dir="$(cd "$(dirname "$self_path")" && pwd)"
: "${PREFIX:=/data/data/com.termux/files/usr}"
: "${TMPDIR:=/tmp}"

missing=""
for cmd in clang pkg-config meson ninja patchelf git; do
  command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
done
for pc in wlroots-0.20 wayland-server wayland-client wayland-protocols \
          xkbcommon pixman-1 libdrm pangocairo libcjson xcb xcb-icccm \
          xcb-randr libpcre2-8 egl glesv2 gbm lcms2 vulkan; do
  pkg-config --exists "$pc" 2>/dev/null || missing="$missing $pc"
done
# Xwayland is launched by wlroots so X11 apps opened inside mango end up in the
# nested session instead of the outer Termux:X11 root window.
command -v Xwayland >/dev/null 2>&1 || missing="$missing xwayland"
[[ -f "$PREFIX/include/wordexp.h" ]] || missing="$missing libandroid-wordexp"
[[ -f "$PREFIX/include/EGL/egl.h" ]] || missing="$missing libglvnd-dev"
[[ -f "$PREFIX/include/GLES2/gl2.h" ]] || missing="$missing libglvnd-dev"
# Termux's mesa package ships gbm.pc/libgbm, but gbm.h lives in mesa-dev.
# Missing it makes scenefx fail with "fatal error: 'gbm.h' file not found".
[[ -f "$PREFIX/include/gbm.h" ]] || missing="$missing mesa-dev"
# Mesa Zink (OpenGL on Vulkan) plus the Freedreno Vulkan ICD (Turnip).
[[ -e "$PREFIX/lib/dri/zink_dri.so" ]] || missing="$missing mesa"
[[ -f "$PREFIX/lib/libvulkan_freedreno.so" ]] || \
  missing="$missing mesa-vulkan-icd-freedreno"
if [[ -n "$missing" ]]; then
  echo "Missing build dependencies:$missing"
  echo "Install e.g.: pkg install clang pkg-config ninja patchelf git python-pip \\"
  echo "  wlroots libwayland libwayland-protocols libxkbcommon libpixman \\"
  echo "  libdrm libxcb xcb-util-wm xcb-util-renderutil xwayland \\"
  echo "  libglvnd-dev mesa mesa-dev mesa-vulkan-icd-freedreno \\"
  echo "  littlecms vulkan-loader pcre2 pango cjson libandroid-wordexp"
  echo "  python -m pip install meson"
  exit 1
fi

# Meson on Termux cannot stat /data/data/com.termux/files/lib (mode 000).
libdir="/data/data/com.termux/files/lib"
if [[ -d "$libdir" ]]; then
  chmod 700 "$libdir"
  trap 'chmod 000 "$libdir" 2>/dev/null || true' EXIT
fi

scenefx_dir="${SCENEFX_DIR:-$self_dir/scenefx}"
if [[ ! -d "$scenefx_dir" ]]; then
  echo "scenefx sources not found: $scenefx_dir" >&2
  exit 1
fi

patch_file="$self_dir/termux-compat/scenefx-termux.patch"
if ! grep -q "fx_renderer_create_with_egl" \
    "$scenefx_dir/include/scenefx/render/fx_renderer/fx_renderer.h"; then
  if [[ -d "$scenefx_dir/.git" ]]; then
    if grep -q "fx_pass = is_fx" "$scenefx_dir/types/scene/wlr_scene.c"; then
      echo "Reverting previous scenefx patch..."
      git -C "$scenefx_dir" checkout -- .
    fi
    echo "Applying scenefx Termux/AHB patch..."
    git -C "$scenefx_dir" apply "$patch_file"
  else
    echo "scenefx sources are not patched: $scenefx_dir" >&2
    echo "Use the bundled scenefx/ tree or apply $patch_file manually." >&2
    exit 1
  fi
fi

echo "Building scenefx..."
if [[ ! -f "$scenefx_dir/build/build.ninja" ]]; then
  meson setup "$scenefx_dir/build" "$scenefx_dir" \
    --prefix="$PREFIX" -Dexamples=false -Dwerror=false
fi
meson compile -C "$scenefx_dir/build"
meson install -C "$scenefx_dir/build"

echo "Building mango..."
mango_meson_args=(--prefix="$PREFIX" -Dtermux=true -Dxwayland=enabled)
if [[ ! -f "$self_dir/build/build.ninja" ]]; then
  meson setup "$self_dir/build" "$self_dir" "${mango_meson_args[@]}"
else
  # Reconfigure existing builds too: older versions of this script disabled
  # Xwayland, which made X11 apps open in the outer Termux:X11 session.
  meson setup --reconfigure "$self_dir/build" "$self_dir" \
    "${mango_meson_args[@]}"
fi
meson compile -C "$self_dir/build"
meson install -C "$self_dir/build"

# Termux's Mesa EGL has no EGL_EXT_image_dma_buf_import and only offers
# llvmpipe. Android's system EGL drives the Adreno GPU and supports
# AHardwareBuffer-backed images, which is how mango gets hardware scenefx
# effects without DRI3. Ship private copies of the libraries whose EGL/GLES
# references we redirect, so the normal Mesa-based build stays untouched.
system_egl=""
system_gles=""
for p in /system/lib64/libEGL.so /system/lib/libEGL.so; do
  [[ -e "$p" ]] && { system_egl="$p"; break; }
done
for p in /system/lib64/libGLESv2.so /system/lib/libGLESv2.so; do
  [[ -e "$p" ]] && { system_gles="$p"; break; }
done

priv_dir="$PREFIX/lib/mango-termux"
if [[ -n "$system_egl" && -n "$system_gles" ]]; then
  echo "Installing GPU/AHardwareBuffer libraries into $priv_dir..."
  rm -rf "$priv_dir"
  mkdir -p "$priv_dir"
  install -m 755 "$PREFIX/bin/mango" "$priv_dir/mango"
  install -m 755 "$PREFIX/lib/libwlroots-0.20.so" \
    "$priv_dir/libwlroots-0.20.so"
  install -m 755 "$PREFIX/lib/libscenefx-0.5.so" \
    "$priv_dir/libscenefx-0.5.so"

  for lib in "$priv_dir/mango" "$priv_dir/libwlroots-0.20.so" \
             "$priv_dir/libscenefx-0.5.so"; do
    patchelf --replace-needed libEGL.so.1 "$system_egl" "$lib" \
      2>/dev/null || true
    patchelf --replace-needed libGLESv2.so.2 "$system_gles" "$lib" \
      2>/dev/null || true
    patchelf --set-rpath "$priv_dir:$PREFIX/lib" "$lib"
  done
else
  echo "Android system EGL/GLES not found; GPU effects unavailable."
fi

mkdir -p "$HOME/.config/mango"
if [[ ! -f "$HOME/.config/mango/config.conf" ]]; then
  cp "$PREFIX/etc/mango/config.conf" "$HOME/.config/mango/config.conf"
  # The GPU path is the default on Termux, so enable the visible effects for
  # new installs. Existing configs are never overwritten.
  sed -i \
    -e 's/^blur=0/blur=1/' \
    -e 's/^blur_layer=0/blur_layer=1/' \
    -e 's/^shadows = 0/shadows = 1/' \
    -e 's/^layer_shadows = 0/layer_shadows = 1/' \
    -e 's/^border_radius=6/border_radius=12/' \
    "$HOME/.config/mango/config.conf"
fi
if [[ ! -f "$HOME/.config/mango/config.toml" ]]; then
  cp "$PREFIX/etc/mango/config.toml" "$HOME/.config/mango/config.toml"
fi

echo
echo "Done. Start mango with:"
echo "  mango-termux"
echo "or:"
echo "  $self_dir/run-mango.sh"
