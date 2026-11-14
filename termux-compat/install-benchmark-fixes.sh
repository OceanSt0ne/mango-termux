#!/data/data/com.termux/files/usr/bin/bash
# Install the Termux/glibc benchmark fixes used by this port:
#   - native glmark2 / glmark2-es2 on the private Mesa 27 KGSL stack
#   - vkmark with a working assimp and the Arch KGSL Turnip ICD
#   - stop glibc-runner from inheriting the bionic Mesa environment
#
# Run as the Termux user, not as root.  Existing files are backed up.
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
GLIBC_BIN="$PREFIX/glibc/bin"
GLIBC_LIB="$PREFIX/glibc/lib"
VKMARK_DIR="$PREFIX/opt/vkmark-kgsl"
VKMARK_LIB="$VKMARK_DIR/lib"
MESA_DIR="$PREFIX/opt/mesa-kgsl"
CONTAINER="${PROOT_DISTRO_NAME:-archlinuxarm}"
ROOTFS="$PREFIX/var/lib/proot-distro/containers/$CONTAINER/rootfs"
MARKER="# installed by termux-compat/install-benchmark-fixes.sh"

die() {
	echo "error: $*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing '$1' (pkg install $2)"
}

patch_native_glmark2() {
	local bin="$1"
	[[ -x "$bin" ]] || {
		echo "warning: $bin not installed; skipping native $(basename "$bin")" >&2
		return 0
	}
	[[ -e "$bin.orig" ]] || cp -a "$bin" "$bin.orig"
	if readelf -d "$bin" 2>/dev/null | grep -q 'Shared library: \[libjpeg\.so\]'; then
		patchelf --replace-needed libjpeg.so libjpeg.so.8 "$bin"
		echo "patched $(basename "$bin"): libjpeg.so -> libjpeg.so.8"
	fi
}

install_glmark2_wrapper() {
	local name="$1"
	local target="$2"
	local wrapper="$GLIBC_BIN/$name"

	[[ -f "$wrapper" ]] && grep -q "$MARKER" "$wrapper" && return 0
	[[ -e "$wrapper" ]] || {
		echo "warning: $wrapper not installed; skipping glibc wrapper" >&2
		return 0
	}
	if [[ ! -e "$wrapper.glibc" ]]; then
		mv "$wrapper" "$wrapper.glibc"
	else
		rm -f "$wrapper"
	fi
	cat >"$wrapper" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
$MARKER
# Use the native Termux glmark2 on the same Mesa 27 KGSL stack as the session.
prefix="$PREFIX"
mesa="\$prefix/opt/mesa-kgsl"
if [[ -d "\$mesa/lib" ]]; then
  export LD_LIBRARY_PATH="\$mesa/lib"
  export LIBGL_DRIVERS_PATH="\$mesa/lib/dri"
  export GBM_BACKENDS_PATH="\$mesa/lib/gbm"
  export MESA_LOADER_DRIVER_OVERRIDE=kgsl
  export GALLIUM_DRIVER=kgsl
  unset VK_DRIVER_FILES VK_ICD_FILENAMES
fi
exec "$target" "\$@"
EOF
	chmod 755 "$wrapper"
	echo "installed glibc wrapper: $wrapper -> $target"
}

copy_arch_lib() {
	local name="$1"
	local src="$2"
	local dst="$VKMARK_LIB/$name"
	[[ -e "$src" ]] || die "Arch library not found: $src"
	cp -L "$src" "$dst"
}

install_vkmark() {
	[[ -x "$GLIBC_BIN/vkmark" ]] || {
		echo "warning: glibc vkmark not installed; skipping" >&2
		return 0
	}
	[[ -d "$ROOTFS" ]] || die "Arch rootfs not found: $ROOTFS (set PROOT_DISTRO_NAME)"
	[[ -f "$ROOTFS/usr/lib/libvulkan_freedreno.so" ]] ||
		die "Arch Turnip missing; run termux-compat/build-arch-turnip.sh first"
	grep -a -q '/dev/kgsl-3d0' "$ROOTFS/usr/lib/libvulkan_freedreno.so" ||
		die "Arch Turnip has no KGSL; run termux-compat/build-arch-turnip.sh first"
	[[ -f "$ROOTFS/usr/lib/libassimp.so.6" ]] ||
		die "Arch assimp missing; run: proot-distro login $CONTAINER -- pacman -S --needed assimp"

	mkdir -p "$VKMARK_LIB"
	local assimp
	assimp="$(readlink -f "$ROOTFS/usr/lib/libassimp.so.6")"
	copy_arch_lib "$(basename "$assimp")" "$assimp"
	ln -sfn "$(basename "$assimp")" "$VKMARK_LIB/libassimp.so.6"
	ln -sfn libassimp.so.6 "$VKMARK_LIB/libassimp.so"
	copy_arch_lib libvulkan_freedreno.so "$ROOTFS/usr/lib/libvulkan_freedreno.so"
	for dep in libwayland-client.so.0 libwayland-server.so.0 \
		libxcb-keysyms.so.1 libdisplay-info.so.3 libSPIRV-Tools.so libudev.so.1; do
		copy_arch_lib "$dep" "$(readlink -f "$ROOTFS/usr/lib/$dep")"
	done
	cat >"$VKMARK_DIR/freedreno_icd.json" <<EOF
{
    "file_format_version": "1.0.1",
    "ICD": {
        "api_version": "1.4.363",
        "library_arch": "64",
        "library_path": "$VKMARK_LIB/libvulkan_freedreno.so"
    }
}
EOF

	local wrapper="$GLIBC_BIN/vkmark"
	if ! grep -q "$MARKER" "$wrapper" 2>/dev/null; then
		if [[ ! -e "$GLIBC_BIN/vkmark.real" ]]; then
			mv "$wrapper" "$GLIBC_BIN/vkmark.real"
		else
			rm -f "$wrapper"
		fi
		cat >"$wrapper" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
$MARKER
# vkmark needs assimp 6 and an Arch Mesa 27 Turnip ICD with KGSL support.
prefix="$PREFIX"
vulkan="$VKMARK_LIB"
exec env \\
  LD_LIBRARY_PATH="\$vulkan" \\
  VK_DRIVER_FILES="$VKMARK_DIR/freedreno_icd.json" \\
  VK_ICD_FILENAMES="$VKMARK_DIR/freedreno_icd.json" \\
  "\$prefix/glibc/bin/vkmark.real" "\$@"
EOF
		chmod 755 "$wrapper"
		echo "installed glibc wrapper: $wrapper"
	fi

	local real="$GLIBC_BIN/vkmark.real"
	[[ -x "$real" ]] || die "missing $real"
	if readelf -d "$real" 2>/dev/null | grep -q 'Shared library: \[libassimp\.so\.5\]'; then
		patchelf --replace-needed libassimp.so.5 libassimp.so.6 "$real"
		echo "patched vkmark: libassimp.so.5 -> libassimp.so.6"
	fi
}

fix_glibc_runner() {
	local runner="$PREFIX/opt/glibc-runner/glibc-runner.sh"
	[[ -f "$runner" ]] || {
		echo "warning: glibc-runner not installed; skipping" >&2
		return 0
	}
	grep -q 'Mango exports the bionic Mesa 27/KGSL libraries' "$runner" && return 0
	[[ -e "$runner.bak" ]] || cp -a "$runner" "$runner.bak"
	local tmp
	tmp="$(mktemp)"
	awk '
		{ print }
		/^# version: 2\.0$/ {
			print ""
			print "# Mango exports the bionic Mesa 27/KGSL libraries for native clients."
			print "# Do not let those libraries leak into the glibc loader."
			print "if [[ \"${LD_LIBRARY_PATH:-}\" == *\"/opt/mesa-kgsl\"* ]]; then"
			print "\tunset LD_LIBRARY_PATH LIBGL_DRIVERS_PATH GBM_BACKENDS_PATH"
			print "\tunset MESA_LOADER_DRIVER_OVERRIDE GALLIUM_DRIVER"
			print "fi"
			print "if [[ \"${VK_DRIVER_FILES:-}\" == *\"/opt/mesa-kgsl\"* ]]; then"
			print "\tunset VK_DRIVER_FILES VK_ICD_FILENAMES"
			print "fi"
		}
	' "$runner" >"$tmp"
	mv "$tmp" "$runner"
	echo "patched glibc-runner: clears the bionic Mesa/KGSL environment"
}

main() {
	need patchelf patchelf
	need readelf binutils

	[[ -d "$MESA_DIR/lib" ]] || echo "warning: $MESA_DIR/lib not found; native benchmarks may use system Mesa" >&2

	patch_native_glmark2 "$PREFIX/bin/glmark2"
	patch_native_glmark2 "$PREFIX/bin/glmark2-es2"
	install_glmark2_wrapper glmark2 "$PREFIX/bin/glmark2"
	install_glmark2_wrapper glmark2-es2 "$PREFIX/bin/glmark2-es2"
	install_vkmark
	fix_glibc_runner

	echo
	echo "Benchmark fixes installed."
	echo "Reload with Super+R or restart mango, then run: glmark2, glmark2-es2, vkmark"
}

main "$@"
