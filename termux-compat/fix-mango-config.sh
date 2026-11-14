#!/data/data/com.termux/files/usr/bin/bash
# Migrate mango 0.18 config key names in ~/.config/mango/*.conf.
#
# The old names are kept by older mango releases but are reported as unknown
# keywords by 0.18.x.  The script only rewrites the active .conf files, makes a
# timestamped backup, and then validates the result with `mango -p`.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: fix-mango-config.sh [options] [CONFIG_DIR]

Migrate old mango .conf key names to the current 0.18 names.

Options:
  -n, --dry-run       show what would change, do not write files
      --no-validate   skip the final `mango -p` check
  -h, --help          show this help

CONFIG_DIR defaults to ${XDG_CONFIG_HOME:-$HOME/.config}/mango.
A timestamped backup is created in CONFIG_DIR before any file is changed.
EOF
}

config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mango"
dry_run=0
validate=1

while (($#)); do
	case "$1" in
		-n|--dry-run)
			dry_run=1
			;;
		--no-validate)
			validate=0
			;;
		-h|--help)
			usage
			exit 0
			;;
		--config-dir)
			if (($# < 2)); then
				echo "error: --config-dir needs an argument" >&2
				exit 2
			fi
			config_dir="$2"
			shift
			;;
		-*)
			echo "error: unknown option: $1" >&2
			usage >&2
			exit 2
			;;
		*)
			config_dir="$1"
			;;
	esac
	shift
done

if [[ ! -d "$config_dir" ]]; then
	echo "error: config directory not found: $config_dir" >&2
	exit 1
fi

shopt -s nullglob
files=("$config_dir"/*.conf)
if ((${#files[@]} == 0)); then
	echo "error: no .conf files in $config_dir" >&2
	exit 1
fi

declare -A rename=(
	[middle_button_emulation]=trackpad_middle_button_emulation
	[default_mfact]=default_master_factor
	[default_nmaster]=default_master_count
	[smartgaps]=smart_gaps
	[dwindle_hsplit]=dwindle_horizontal_split
	[dwindle_vsplit]=dwindle_vertical_split
	[overviewgappi]=overview_gap_inner
	[overviewgappo]=overview_gap_outer
	[idleinhibit_ignore_visible]=idle_inhibit_ignore_visible
	[sloppyfocus]=sloppy_focus
	[warpcursor]=warp_cursor
	[tagrule]=tag_rule
	[shadowscolor]=shadows_color
	[gappih]=gap_inner_horizontal
	[gappiv]=gap_inner_vertical
	[gappoh]=gap_outer_horizontal
	[gappov]=gap_outer_vertical
	[borderpx]=border_px
	[rootcolor]=root_color
	[bordercolor]=border_color
	[dropcolor]=drop_color
	[splitcolor]=split_color
	[focuscolor]=focus_color
	[maximizescreencolor]=maximized_screen_color
	[urgentcolor]=urgent_color
	[scratchpadcolor]=scratchpad_color
	[globalcolor]=global_color
	[overlaycolor]=overlay_color
)

# These options were removed; keep the old lines as comments instead of
# silently deleting user values.
obsolete=(ov_tab_mode ov_no_resize)

needs_update=0
for file in "${files[@]}"; do
	for old in "${!rename[@]}"; do
		if grep -qE "^[[:space:]]*${old}[[:space:]]*=" "$file"; then
			needs_update=1
			break
		fi
	done
	if ((${#obsolete[@]})); then
		for old in "${obsolete[@]}"; do
			if grep -qE "^[[:space:]]*${old}[[:space:]]*=" "$file"; then
				needs_update=1
				break
			fi
		done
	fi
done

if ((needs_update == 0)); then
	echo "Config is already current: $config_dir"
	exit 0
fi

if ((dry_run)); then
	echo "Would update:"
	for file in "${files[@]}"; do
		for old in "${!rename[@]}"; do
			if grep -qE "^[[:space:]]*${old}[[:space:]]*=" "$file"; then
				printf '  %s: %s -> %s\n' "$file" "$old" "${rename[$old]}"
			fi
		done
		for old in "${obsolete[@]}"; do
			if grep -qE "^[[:space:]]*${old}[[:space:]]*=" "$file"; then
				printf '  %s: remove/comment %s\n' "$file" "$old"
			fi
		done
	done
	exit 0
fi

backup_dir="$(mktemp -d "$config_dir/backup-mango-config.XXXXXX")"
for file in "${files[@]}"; do
	cp -a "$file" "$backup_dir/"
done

for file in "${files[@]}"; do
	for old in "${!rename[@]}"; do
		sed -i -E \
			"s/^([[:space:]]*)${old}[[:space:]]*=/\\1${rename[$old]}=/" \
			"$file"
	done
	for old in "${obsolete[@]}"; do
		sed -i -E \
			"s/^([[:space:]]*)${old}[[:space:]]*=/# \\1${old}=/" \
			"$file"
	done
done

echo "Updated ${#files[@]} config file(s)."
echo "Backup: $backup_dir"

if ((validate)) && command -v mango >/dev/null 2>&1; then
	if [[ -f "$config_dir/config.conf" ]]; then
		check="$(mango -p -c "$config_dir/config.conf" 2>&1 || true)"
		if printf '%s\n' "$check" | grep -qE 'Unknown keyword|ERROR'; then
			printf '%s\n' "$check" >&2
			echo "error: mango still reports config errors; backup is in $backup_dir" >&2
			exit 1
		fi
		echo "mango -p: OK"
	fi
fi

echo "Reload with Super+R or restart mango to apply the changes."
