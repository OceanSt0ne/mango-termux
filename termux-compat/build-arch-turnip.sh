#!/data/data/com.termux/files/usr/bin/bash
# Build Mesa Turnip with the KGSL backend inside the Arch Linux ARM proot and
# install it as the system Vulkan Freedreno ICD. Arch's stock Turnip is built
# for DRM/MSM only, so Noctalia inside proot falls back to llvmpipe. This build
# adds KGSL, which is what Android/Termux exposes at /dev/kgsl-3d0.
set -euo pipefail

container="${PROOT_DISTRO_NAME:-archlinuxarm}"
jobs="${JOBS:-4}"

exec proot-distro login "$container" -- env JOBS="$jobs" bash -s <<'ARCH_EOF'
set -euo pipefail

jobs="${JOBS:-4}"
work="${MESA_BUILD_DIR:-/root/mesa-turnip-kgsl}"

if ! command -v pacman >/dev/null 2>&1; then
  echo "error: this script must run inside the Arch Linux ARM proot" >&2
  exit 1
fi

echo "==> Installing Mesa build dependencies"
pacman -S --needed --noconfirm \
  meson ninja curl python-mako python-yaml python-packaging \
  python-setuptools glslang libclc pkgconf

mesa_version="$(pacman -Q mesa | awk '{print $2}')"
mesa_version="${mesa_version#*:}"
mesa_version="${mesa_version%%-*}"
echo "==> Arch Mesa version: $mesa_version"

mkdir -p "$work"
cd "$work"
tarball="mesa-$mesa_version.tar.xz"
if [[ ! -f "$tarball" ]]; then
  echo "==> Downloading $tarball"
  curl -L --fail --retry 3 -o "$tarball" "https://archive.mesa3d.org/$tarball"
fi

if [[ ! -d "mesa-$mesa_version" ]]; then
  tar -xf "$tarball"
fi
cd "mesa-$mesa_version"

if [[ ! -d build ]]; then
  echo "==> Configuring Turnip with KGSL"
  meson setup build \
    --prefix=/usr \
    --buildtype=release \
    -Dvulkan-drivers=freedreno \
    -Dfreedreno-kmds=msm,kgsl \
    -Dgallium-drivers= \
    -Dplatforms=wayland,x11 \
    -Dglx=disabled \
    -Degl=disabled \
    -Dgles1=disabled \
    -Dgles2=disabled \
    -Dllvm=disabled \
    -Dlibunwind=disabled \
    -Dvalgrind=disabled \
    -Dvideo-codecs= \
    -Dvulkan-layers= \
    -Dhtml-docs=disabled \
    -Dwerror=false
fi

echo "==> Building libvulkan_freedreno.so"
ninja -C build -j"$jobs" src/freedreno/vulkan/libvulkan_freedreno.so

lib="$PWD/build/src/freedreno/vulkan/libvulkan_freedreno.so"
if ! grep -a -q '/dev/kgsl-3d0' "$lib"; then
  echo "error: built driver has no KGSL support" >&2
  exit 1
fi

echo "==> Installing driver and ICD manifest"
if [[ ! -e /usr/lib/libvulkan_freedreno.so.kgsl-old ]]; then
  cp -p /usr/lib/libvulkan_freedreno.so /usr/lib/libvulkan_freedreno.so.kgsl-old 2>/dev/null || true
fi
install -m755 "$lib" /usr/lib/libvulkan_freedreno.so
install -d /usr/share/vulkan/icd.d
cat > /usr/share/vulkan/icd.d/freedreno_icd.aarch64.json <<'EOF'
{
    "ICD": {
        "api_version": "1.4.354",
        "library_arch": "64",
        "library_path": "/usr/lib/libvulkan_freedreno.so"
    },
    "file_format_version": "1.0.1"
}
EOF

echo "==> Installed: $(grep -a -m1 -o 'Mesa 26[0-9.]*' /usr/lib/libvulkan_freedreno.so || true)"
echo
echo "Now set in ~/.config/mango/start-noctalia.sh:"
echo "  MESA_LOADER_DRIVER_OVERRIDE=zink"
echo "  GALLIUM_DRIVER=zink"
echo "  VK_DRIVER_FILES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
ARCH_EOF
