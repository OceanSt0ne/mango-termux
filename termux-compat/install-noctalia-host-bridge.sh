#!/data/data/com.termux/files/usr/bin/bash
#
# Install mango-host-run and point Noctalia terminal .desktop entries at it.
#
# Usage:
#   ./termux-compat/install-noctalia-host-bridge.sh [--check]
set -euo pipefail

self_path="$0"
if command -v readlink >/dev/null 2>&1; then
	self_path="$(readlink -f "$0" 2>/dev/null || printf '%s\n' "$0")"
fi
self_dir="$(cd "$(dirname "$self_path")" && pwd)"

prefix="${PREFIX:-/data/data/com.termux/files/usr}"
bin="$prefix/bin"
wrapper_src="$self_dir/mango-host-run"
check_only=0
patched=0
skipped=0

die() {
	echo "error: $*" >&2
	exit 1
}

need() {
	command -v "$1" >/dev/null 2>&1 || die "missing '$1'"
}

usage() {
	cat <<'EOF'
Install the Noctalia host bridge.

Usage:
  ./termux-compat/install-noctalia-host-bridge.sh [--check]

Options:
  --check     Verify the installed wrapper and patched desktop entries.
  -h, --help  Show this help.
EOF
}

while (($#)); do
	case "$1" in
		--check) check_only=1 ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1" ;;
	esac
	shift
done

match_terminal() {
	local base="${1##*/}"
	case "$base" in
		kitty.desktop) printf 'kitty\n' ;;
		foot.desktop) printf 'foot\n' ;;
		*ghostty*.desktop) printf 'ghostty\n' ;;
		*) return 1 ;;
	esac
}

desktop_files() {
	local file
	for file in "$prefix/share/applications/"*.desktop; do
		[[ -f "$file" ]] || continue
		match_terminal "$file" >/dev/null && printf '%s\n' "$file"
	done
	if [[ -d "$prefix/var/lib/proot-distro/containers" ]]; then
		find "$prefix/var/lib/proot-distro/containers" -type f \
			-path '*/rootfs/*' -path '*/applications/*.desktop' -print0 2>/dev/null |
			while IFS= read -r -d '' file; do
				match_terminal "$file" >/dev/null && printf '%s\n' "$file"
			done
	fi
}

patch_desktop() {
	local file="$1"
	local term backup tmp
	term="$(match_terminal "$file")" || {
		skipped=$((skipped + 1))
		return 0
	}
	if grep -q 'mango-host-run' "$file"; then
		echo "already patched: $file"
		skipped=$((skipped + 1))
		return 0
	fi
	tmp="$(mktemp "${file}.tmp.XXXXXX")"
	sed -E "s#^(Exec=)([^[:space:]]*/)?${term}([[:space:]]|\$)#\1/usr/bin/env -u LD_PRELOAD -u LD_LIBRARY_PATH ${prefix}/bin/mango-host-run ${term}\3#" \
		"$file" >"$tmp"
	if cmp -s "$file" "$tmp"; then
		rm -f "$tmp"
		echo "skipped, no Exec match: $file"
		skipped=$((skipped + 1))
		return 0
	fi
	chmod --reference="$file" "$tmp" 2>/dev/null ||
		chmod "$(stat -c '%a' "$file")" "$tmp"
	backup="$file.mango-bak"
	[[ -e "$backup" ]] || cp -a "$file" "$backup"
	mv "$tmp" "$file"
	echo "patched: $file"
	patched=$((patched + 1))
}

check_installation() {
	local failed=0 file
	if [[ -x "$bin/mango-host-run" ]]; then
		echo "OK: wrapper installed: $bin/mango-host-run"
	else
		echo "FAIL: missing wrapper: $bin/mango-host-run" >&2
		failed=1
	fi
	if [[ -f "$wrapper_src" ]]; then
		echo "OK: wrapper source: $wrapper_src"
	else
		echo "FAIL: missing wrapper source: $wrapper_src" >&2
		failed=1
	fi
	while IFS= read -r file; do
		[[ -n "$file" ]] || continue
		if grep -q 'mango-host-run' "$file"; then
			echo "OK: patched: $file"
		else
			echo "FAIL: not patched: $file" >&2
			failed=1
		fi
	done < <(desktop_files)
	if ((failed)); then
		echo "check failed" >&2
		return 1
	fi
	echo "check passed"
}

if ((check_only)); then
	if check_installation; then
		exit 0
	fi
	exit 1
fi

[[ -f "$wrapper_src" ]] || die "missing wrapper source: $wrapper_src"

need install
need sed
need grep
need find
need mktemp
need cmp
need chmod

mkdir -p "$bin"
install -m 755 "$wrapper_src" "$bin/mango-host-run"
echo "installed wrapper: $bin/mango-host-run"

if [[ -x "$self_dir/mango-integrate" ]]; then
	"$self_dir/mango-integrate" --no-firefox --quiet || true
fi

while IFS= read -r file; do
	[[ -n "$file" ]] || continue
	patch_desktop "$file"
done < <(desktop_files)

if command -v update-desktop-database >/dev/null 2>&1; then
	update-desktop-database "$prefix/share/applications" >/dev/null 2>&1 || true
fi

echo
echo "Installed wrapper: $bin/mango-host-run"
echo "Patched: $patched file(s)"
echo "Skipped: $skipped file(s)"
