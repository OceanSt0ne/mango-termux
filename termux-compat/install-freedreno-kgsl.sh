#!/data/data/com.termux/files/usr/bin/bash
#
# Install an isolated Freedreno/KGSL Mesa 27 stack for mango-termux.
#
# Termux's stock Mesa provides Zink/Turnip, but its Gallium driver has no
# /dev/kgsl-3d0 support. Without this private stack, session clients fall back
# to llvmpipe even when mango itself renders through Zink/Turnip.
#
# The packages are extracted under $PREFIX/opt/mesa-kgsl and never replace the
# system Mesa. The launcher exports them only for mango's session.
#
# Usage:
#   ./termux-compat/install-freedreno-kgsl.sh [--force] [--check]
#
# Environment:
#   PREFIX              Termux prefix (default: /data/data/com.termux/files/usr)
#   MESA_KGSL_DIR       install directory (default: $PREFIX/opt/mesa-kgsl)
#   MESA_KGSL_RELEASE   lfdevs release tag
#   MESA_KGSL_VERSION   package version inside that release
#   MESA_KGSL_SKIP_CHECKSUM  1 disables pinned SHA-256 checks
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
DEST="${MESA_KGSL_DIR:-$PREFIX/opt/mesa-kgsl}"
RELEASE="${MESA_KGSL_RELEASE:-freedreno-27.0.0-devel-20261025-r2}"
REPO="${MESA_KGSL_REPO:-lfdevs/termux-packages}"
MESA_VERSION="${MESA_KGSL_VERSION:-27.0.0-92}"
MESA_DEB="mesa_${MESA_VERSION}_aarch64.deb"
VULKAN_DEB="mesa-vulkan-icd-freedreno_${MESA_VERSION}_aarch64.deb"
MESA_SHA256="5ee95d32b6030227d3cda52fa14cfa4628a7b3ff5d991f7221fba7cd4fb4b378"
VULKAN_SHA256="9d8968db6ca9013fdd8ab4018b3cb6695dd4920630205690f1084445b6c26f20"
FORCE=0
CHECK_ONLY=0

usage() {
	sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
	echo "error: $*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing '$1' (pkg install $2)"
}

case "$DEST" in
	/*) ;;
	*) DEST="$PWD/$DEST" ;;
esac

is_installed() {
	local manifest="$DEST/share/vulkan/icd.d/freedreno_icd.aarch64.json"
	[[ -f "$DEST/lib/dri/kgsl_dri.so" ]] &&
	[[ -f "$DEST/lib/libgallium-27.0.0-devel.so" ]] &&
	[[ -f "$DEST/lib/libvulkan_freedreno.so" ]] &&
	[[ -f "$manifest" ]] &&
	grep -Fq "$DEST/lib/libvulkan_freedreno.so" "$manifest"
}

verify_tree() {
	local dir="$1"
	local manifest_lib="${2:-$dir/lib/libvulkan_freedreno.so}"
	local manifest="$dir/share/vulkan/icd.d/freedreno_icd.aarch64.json"
	local gallium="$dir/lib/libgallium-27.0.0-devel.so"
	local vulkan="$dir/lib/libvulkan_freedreno.so"

	[[ -f "$dir/lib/dri/kgsl_dri.so" ]] ||
		die "KGSL Gallium driver is missing from $dir"
	[[ -f "$gallium" ]] || die "Mesa Gallium library is missing from $dir"
	[[ -f "$vulkan" ]] || die "Freedreno Vulkan driver is missing from $dir"
	[[ -f "$manifest" ]] || die "Freedreno Vulkan manifest is missing from $dir"
	grep -aq '/dev/kgsl-3d0' "$gallium" ||
		die "Gallium library has no KGSL support"
	grep -aq '/dev/kgsl-3d0' "$vulkan" ||
		die "Vulkan driver has no KGSL support"
	grep -Fq "$manifest_lib" "$manifest" ||
		die "Vulkan manifest does not point at the private driver"
}

download() {
	local url="$1"
	local out="$2"

	if command -v curl >/dev/null 2>&1; then
		curl --fail --location --retry 3 --silent --show-error \
			--output "$out" "$url"
	elif command -v wget >/dev/null 2>&1; then
		wget --no-verbose --output-document="$out" "$url"
	else
		die "curl or wget is required"
	fi
}

while (($#)); do
	case "$1" in
		--force) FORCE=1 ;;
		--check) CHECK_ONLY=1 ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
	shift
done

if is_installed && (( ! FORCE )); then
	echo "Freedreno/KGSL Mesa 27 already installed: $DEST"
	exit 0
fi
if (( CHECK_ONLY )); then
	die "Freedreno/KGSL Mesa 27 is not installed in $DEST"
fi

need dpkg-deb dpkg
need sha256sum coreutils

work="$(mktemp -d "${TMPDIR:-/tmp}/mango-kgsl.XXXXXX")"
trap 'rm -rf "$work"' EXIT

base="https://github.com/$REPO/releases/download/$RELEASE"
echo "Downloading Freedreno/KGSL Mesa $MESA_VERSION from $REPO ($RELEASE)..."
download "$base/$MESA_DEB" "$work/$MESA_DEB"
download "$base/$VULKAN_DEB" "$work/$VULKAN_DEB"

if [[ "${MESA_KGSL_SKIP_CHECKSUM:-0}" != "1" ]]; then
	printf '%s  %s\n' "$MESA_SHA256" "$work/$MESA_DEB" |
		(cd "$work" && sha256sum --check --status -) ||
		die "checksum mismatch for $MESA_DEB"
	printf '%s  %s\n' "$VULKAN_SHA256" "$work/$VULKAN_DEB" |
		(cd "$work" && sha256sum --check --status -) ||
		die "checksum mismatch for $VULKAN_DEB"
fi

dpkg-deb -x "$work/$MESA_DEB" "$work/root"
dpkg-deb -x "$work/$VULKAN_DEB" "$work/root"
src="$work/root/data/data/com.termux/files/usr"
[[ -d "$src/lib" ]] || die "unexpected package layout: $src/lib is missing"

staging="$DEST.new.$$"
rm -rf "$staging"
mkdir -p "$staging"
cp -a "$src/." "$staging/"

manifest="$staging/share/vulkan/icd.d/freedreno_icd.aarch64.json"
fixed="$(mktemp)"
sed "s#/data/data/com.termux/files/usr/lib/libvulkan_freedreno.so#$DEST/lib/libvulkan_freedreno.so#" \
	"$manifest" >"$fixed"
mv "$fixed" "$manifest"
verify_tree "$staging" "$DEST/lib/libvulkan_freedreno.so"

backup=""
if [[ -e "$DEST" ]]; then
	backup="$DEST.bak.$(date +%Y%m%d-%H%M%S)"
	mv "$DEST" "$backup"
fi
if ! mv "$staging" "$DEST"; then
	[[ -n "$backup" ]] && mv "$backup" "$DEST"
	die "failed to install $DEST"
fi
verify_tree "$DEST"

echo "Installed Freedreno/KGSL Mesa 27 in $DEST"
echo "  Gallium: $(grep -a -m1 -o 'Mesa [0-9][0-9.]*' "$DEST/lib/libgallium-27.0.0-devel.so" || echo unknown)"
echo "  Vulkan:  $(grep -a -m1 -o 'Mesa [0-9][0-9.]*' "$DEST/lib/libvulkan_freedreno.so" || echo unknown)"
[[ -n "$backup" ]] && echo "  Previous installation: $backup"
echo
echo "Restart mango to use the native KGSL path:"
echo "  mango-termux --restart"
