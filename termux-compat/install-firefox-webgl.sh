#!/data/data/com.termux/files/usr/bin/bash
#
# Install a Firefox WebGL wrapper for MangoWM sessions.
#
# Firefox needs EGL DMA-BUF support, which the session's native KGSL Gallium
# driver does not provide. The wrapper launches Firefox with the private Mesa 27
# Zink/Turnip stack instead, while leaving the rest of the session on KGSL.
#
# The installer:
#   - installs $PREFIX/bin/mango-gpu-run
#   - installs $PREFIX/bin/mango-firefox
#   - replaces $PREFIX/bin/firefox with the wrapper (original kept as
#     firefox.mango-bak)
#   - points Firefox .desktop entries, including Arch proot entries, at
#     mango-firefox
#
# Usage:
#   ./termux-compat/install-firefox-webgl.sh [--check]
set -euo pipefail

self_path="$0"
if command -v readlink >/dev/null 2>&1; then
	self_path="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"
fi
self_dir="$(cd "$(dirname "$self_path")" && pwd)"

prefix="${PREFIX:-/data/data/com.termux/files/usr}"
bin="$prefix/bin"
gpu_run_src="$self_dir/mango-gpu-run"
firefox_src="$self_dir/mango-firefox"
check_only=0

die() {
	echo "error: $*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing '$1'"
}

usage() {
	sed -n '3,23p' "$0" | sed 's/^# \{0,1\}//'
}

while (($#)); do
	case "$1" in
		--check) check_only=1 ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
	shift
done

[[ -f "$gpu_run_src" ]] || die "missing $gpu_run_src"
[[ -f "$firefox_src" ]] || die "missing $firefox_src"

is_wrapper() {
	local file="$1"
	[[ -f "$file" ]] && grep -q 'mango-gpu-run' "$file"
}

is_firefox_installed() {
	[[ -x "$prefix/lib/firefox/firefox" ]]
}

desktop_files() {
	local file
	for file in "$prefix/share/applications/"*.desktop; do
		[[ -f "$file" ]] || continue
		grep -qi 'firefox' "$file" && printf '%s\n' "$file"
	done
	if [[ -d "$prefix/var/lib/proot-distro/containers" ]]; then
		find "$prefix/var/lib/proot-distro/containers" -type f \
			-path '*/applications/*.desktop' -print0 2>/dev/null |
			while IFS= read -r -d '' file; do
				grep -qi 'firefox' "$file" && printf '%s\n' "$file"
			done
	fi
}

patch_desktop() {
	local file="$1"
	local backup="$file.mango-bak"
	local tmp

	[[ -f "$file" ]] || return 0
	grep -qi 'firefox' "$file" || return 0
	if grep -q 'mango-firefox' "$file"; then
		echo "already patched: $file"
		return 0
	fi

	[[ -e "$backup" ]] || cp -a "$file" "$backup"
	tmp="$(mktemp "${file}.tmp.XXXXXX")"
	sed -E "s#^(Exec=)([^ ]*/)?firefox([[:space:]]|\$)#\1$prefix/bin/mango-firefox\3#" \
		"$file" >"$tmp"
	if cmp -s "$file" "$tmp"; then
		rm -f "$tmp"
		return 0
	fi
	mv "$tmp" "$file"
	echo "patched: $file"
}

install_wrappers() {
	mkdir -p "$bin"
	install -m 755 "$gpu_run_src" "$bin/mango-gpu-run"
	install -m 755 "$firefox_src" "$bin/mango-firefox"

	if is_wrapper "$bin/firefox"; then
		echo "Firefox wrapper already installed: $bin/firefox"
	elif [[ -e "$bin/firefox" || -L "$bin/firefox" ]]; then
		backup="$bin/firefox.mango-bak"
		if [[ ! -e "$backup" && ! -L "$backup" ]]; then
			mv "$bin/firefox" "$backup"
			echo "backed up original Firefox launcher: $backup"
		else
			rm -f "$bin/firefox"
		fi
		install -m 755 "$firefox_src" "$bin/firefox"
		echo "installed Firefox wrapper: $bin/firefox"
	else
		install -m 755 "$firefox_src" "$bin/firefox"
		echo "installed Firefox wrapper: $bin/firefox"
	fi
}

check_installation() {
	[[ -x "$bin/mango-gpu-run" ]] || die "missing $bin/mango-gpu-run"
	[[ -x "$bin/mango-firefox" ]] || die "missing $bin/mango-firefox"
	is_wrapper "$bin/firefox" || die "$bin/firefox is not the MangoWM wrapper"
	if is_firefox_installed; then
		echo "Firefox wrapper is installed: $bin/firefox"
	else
		echo "Firefox wrapper is installed, but Firefox is not present"
	fi
	local file
	while IFS= read -r file; do
		[[ -n "$file" ]] || continue
		grep -q 'mango-firefox' "$file" ||
			die "desktop entry is not patched: $file"
	done < <(desktop_files)
}

if ((check_only)); then
	check_installation
	exit 0
fi

need install
need sed
need grep
need find
need mktemp

install_wrappers

if is_firefox_installed; then
	while IFS= read -r file; do
		[[ -n "$file" ]] || continue
		patch_desktop "$file"
	done < <(desktop_files)
	if command -v update-desktop-database >/dev/null 2>&1; then
		update-desktop-database "$prefix/share/applications" 2>/dev/null || true
	fi
else
	echo "warning: Firefox is not installed; desktop entries were not patched" >&2
fi

echo
echo "Firefox WebGL setup installed."
echo "Restart Firefox and Noctalia, then test WebGL Aquarium."
echo "Original launcher backup: $bin/firefox.mango-bak"
