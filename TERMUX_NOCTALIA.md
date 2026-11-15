[English](TERMUX_NOCTALIA.md) | [Русский](TERMUX_NOCTALIA_ru.md)

# Noctalia in Termux + MangoWM (native, no proot)

## 0. Quick start

### 0.1 What this guide sets up

This guide configures Noctalia 5.4.1 as a native Termux process and as a
Wayland client of a nested MangoWM session. MangoWM itself runs inside
Termux:X11; Noctalia is a client inside that nested Wayland compositor.

The Arch Linux ARM rootfs is used only as the source of the Noctalia ELF and
its resource files. At runtime the launcher starts no `proot` or
`proot-distro` process. The rootfs is not a jail and the Noctalia process does
not run inside one. `proot-distro` is used only to install or update the rootfs
in sections 2 and 10.

The resulting session provides:

- native execution of the Noctalia ELF with the Termux glibc loader;
- private rootfs Mesa 27, EGL, Vulkan, and DRI paths without global
  `libxml2.so.2` links;
- native MangoWM IPC through `MANGO_INSTANCE_SIGNATURE`, so the workspace
  backend is `mango-ipc`;
- layer-shell panels and bars without extra MangoWM configuration;
- autostart through `~/.config/mango/mics.conf`;
- native Termux child applications such as terminals and Firefox.

### 0.2 Fast path

If MangoWM, the Arch rootfs, Noctalia, and the native launcher are already
installed, restart the session:

```sh
mango-termux --restart
```

MangoWM starts Noctalia from `mics.conf`. Use sections 6 and 7 when
integration or verification is required.

## 1. Prerequisites

### 1.1 Termux and MangoWM

Termux must be installed from a current APT build. Install the Termux:X11
package:

```sh
pkg update
pkg install x11-repo
pkg update
pkg install termux-x11-nightly
```

Build and install MangoWM for Termux:

```sh
git clone https://github.com/OceanSt0ne/mango-termux.git
cd mango-termux
./build-termux.sh
```

`build-termux.sh` installs MangoWM, `mango-termux`, `mmsg`, and the native
`mango-noctalia` launcher. It also runs `mango-integrate` unless
`MANGO_SKIP_INTEGRATIONS=1` is set. A rootfs is not required at build time; the
next MangoWM start applies Noctalia integration when a usable rootfs is
present.

MangoWM runs as a nested Wayland compositor over Termux:X11. Its runtime
directory is `$PREFIX/tmp`, and its Wayland socket is `wayland-0`.

### 1.2 Arch rootfs and Noctalia

The Arch Linux ARM rootfs supplies several files at runtime:

- `usr/bin/noctalia` — the Noctalia ELF;
- `lib/ld-linux-aarch64.so.1` — the rootfs loader; it is required for
  validation but is not executed directly;
- `usr/lib/libstdc++.so.6` — the C++ runtime pinned into the native copy.

The launcher auto-detects a rootfs under
`$PREFIX/var/lib/proot-distro/installed-rootfs/*` and
`$PREFIX/var/lib/proot-distro/containers/*/rootfs`. Set `NOCTALIA_ROOTFS` to
override discovery. For the rest of this guide, `ROOTFS` denotes the selected
tree:

```sh
ROOTFS="${NOCTALIA_ROOTFS:-$PREFIX/var/lib/proot-distro/containers/archlinuxarm/rootfs}"
ls -l "$ROOTFS/usr/bin/noctalia"
```

The launcher validates `usr/bin/noctalia`, `lib/ld-linux-aarch64.so.1`, and
`usr/lib/libstdc++.so.6` before it prepares anything. The rootfs loader is
never used as the process interpreter; section 3.2 explains why.

### 1.3 Native tools

Install the native tools used by the launcher:

```sh
pkg install patchelf dbus
```

`patchelf` is required. It sets the interpreter and RPATH on the private
Noctalia copy and pins the rootfs `libstdc++.so.6`. Without `patchelf` the
launcher exits with an error.

`dbus` is the Termux session-bus implementation. Noctalia uses the native
Termux D-Bus, not the Arch D-Bus. If a session bus is already present, Noctalia
inherits `DBUS_SESSION_BUS_ADDRESS`; otherwise the launcher re-executes itself
under `dbus-run-session`.

## 2. Install Noctalia in the rootfs

### 2.1 Rootfs setup

Install the Arch Linux ARM container and open a shell in it:

```sh
proot-distro install archlinuxarm
proot-distro login archlinuxarm
```

Rootfs installation and updates are the only phases that use `proot-distro`.
The installed rootfs normally appears at
`$PREFIX/var/lib/proot-distro/containers/archlinuxarm/rootfs`; older layouts may
place it under `installed-rootfs/archlinuxarm`.

### 2.2 Noctalia package

Inside the container, update the package database and install Noctalia:

```sh
pacman -Syu --noconfirm
pacman -S --needed --noconfirm noctalia
exit
```

Noctalia 5.4.1 is available from the Arch Linux ARM `extra` repository. The
package provides one ELF at `/usr/bin/noctalia`. It does not provide a separate
quickshell, `qs`, or QML process, and the binary has no Qt `NEEDED` libraries.
The package is only a payload for the native launcher.

Do not install Arch `dbus` for the session bus. The launcher uses the native
Termux D-Bus.

### 2.3 Mesa 27 and KGSL

The rootfs must provide the Mesa 27 stack with the KGSL Freedreno driver. The
relevant files are `libEGL_mesa.so.0`, `libgallium-27...`, `libLLVM.so.23.1`,
`libxml2.so.16`, and `dri/kgsl_dri.so`. Verify them:

```sh
ls -l "$ROOTFS/usr/lib/libEGL_mesa.so.0" "$ROOTFS/usr/lib"/libgallium-27* "$ROOTFS/usr/lib/dri/kgsl_dri.so"
```

The launcher uses this rootfs Mesa 27 stack and maps its libraries through a
private directory. It never uses the stale Termux-glibc Mesa 24.2.6 library
chain. The launcher also does not set `NOCTALIA_GPU`; that selector has been
removed. Rendering relies on the rootfs Mesa/KGSL stack and the private EGL
manifest described in section 4.

## 3. Native launch architecture

### 3.1 Rootfs discovery

Discovery is automatic. The launcher searches both rootfs layouts:

```sh
find "$PREFIX/var/lib/proot-distro/installed-rootfs" "$PREFIX/var/lib/proot-distro/containers" -path '*/usr/bin/noctalia' -type f 2>/dev/null
```

For each candidate it requires `usr/bin/noctalia`,
`lib/ld-linux-aarch64.so.1`, and `usr/lib/libstdc++.so.6`. The first complete
candidate is selected. Set `NOCTALIA_ROOTFS` to a rootfs path to bypass the
search; an override that lacks any required file is rejected.

The rootfs is a binary and resource source only. The launcher does not invoke
`proot` or `proot-distro` to run Noctalia, and no rootfs process is started at
runtime.

### 3.2 Patched native binary

The launcher copies the rootfs ELF to
`$PREFIX/libexec/mango-termux/noctalia-native` and patches that copy with
`patchelf`:

- interpreter: `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`;
- RPATH:
  `$PREFIX/libexec/mango-termux/rootfs-libs:$PREFIX/glibc/lib:$ROOTFS/usr/lib:$ROOTFS/lib`;
- additional RPATH entries when present:
  `$ROOTFS/usr/lib/aarch64-linux-gnu` and
  `$ROOTFS/lib/aarch64-linux-gnu`;
- `NEEDED` entry `libstdc++.so.6` replaced with the absolute rootfs
  `libstdc++.so.6` path.

The result is the persistent equivalent of running the ELF under
`ld-linux --library-path`. Inspect the installed copy:

```sh
patchelf --print-interpreter "$PREFIX/libexec/mango-termux/noctalia-native"
patchelf --print-rpath "$PREFIX/libexec/mango-termux/noctalia-native"
```

Direct execution through the rootfs loader is not used. Android seccomp kills
the Arch glibc startup with `SIGSYS` on `set_robust_list`. The patched copy uses
the Termux glibc loader and also survives Noctalia self-reexec.

The private copy is cached. It is rebuilt when the rootfs `noctalia` binary,
the rootfs `libstdc++.so.6`, the Termux loader, or the `mango-noctalia` wrapper
is newer than the cached binary, or when the selected rootfs changes.

Noctalia 5.4.1 is a single ELF. There is no separate quickshell, `qs`, or QML
process, and the binary has no Qt `NEEDED` libraries. The launcher therefore
starts one process, `noctalia-native`, not a QML runtime tree.

### 3.3 Runtime environment

After the native copy is ready, the launcher executes it with a controlled
environment. Read the environment of the running process:

```sh
pid=$(pgrep -f 'libexec/mango-termux/noctalia-native' | head -1)
tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(HOME|PREFIX|PATH|SHELL|XDG_|WAYLAND|DBUS|MANGO|LD_|__EGL|VK_|LIBGL|GBM)'
```

The launcher sources `$PREFIX/tmp/mango-session.env` when it exists, so Wayland,
D-Bus, GPU, and session values from `mango-termux` are available. It then calls
`clear_foreign_env`, which removes `LD_*`, Mesa, EGL, Vulkan, and `PROOT_*`
variables, and applies the private rootfs paths.

`LD_LIBRARY_PATH` and `LD_PRELOAD` are not exported. Noctalia locates its
libraries through the patched RPATH and private rootfs symlinks. The launcher
also does not start a proot process, so no `PROOT_*` variables are present in
the Noctalia environment.

Native children inherit `HOME`, `PREFIX`,
`PATH=$PREFIX/bin:/system/bin:/system/xbin`, `SHELL=$PREFIX/bin/fish` with a
bash fallback, and native XDG config, state, and data paths. Bionic Termux
children ignore the glibc EGL and Vulkan variables.

## 4. Graphics and resources

### 4.1 Mesa 27 and EGL vendor

The launcher writes a private EGL vendor manifest at
`$PREFIX/libexec/mango-termux/egl_vendor.d/50_mesa.json`. Its `library_path`
is an absolute path to the rootfs `libEGL_mesa.so.0`:

```sh
cat "$PREFIX/libexec/mango-termux/egl_vendor.d/50_mesa.json"
```

`__EGL_VENDOR_LIBRARY_DIRS` points at that private directory. The private
`rootfs-libs` directory also precedes the Termux glibc directories in the
Noctalia RPATH, so the rootfs Mesa 27 libraries win before any Termux-glibc
Mesa is considered.

The original failure was a stale Termux-glibc Mesa 24.2.6 that required
`libxml2.so.2`, while the current rootfs provides only `libxml2.so.16`. Do not
create a global `libxml2.so.2` and do not modify the rootfs. The absolute EGL
manifest plus the private RPATH resolve the mismatch without global changes.

### 4.2 libxml2 and multiarch

`rootfs-libs` is a private symlink farm. It covers `libgbm`, `libgallium`,
`libLLVM`, `libxml2.so.16`, `libstdc++`, Wayland client and server libraries,
`libdrm`, `libexpat`, and the other rootfs dependencies used by Noctalia.
Inspect two representative links:

```sh
readlink -f "$PREFIX/libexec/mango-termux/rootfs-libs/libgbm.so.1"
readlink -f "$PREFIX/libexec/mango-termux/rootfs-libs/libxml2.so.16"
```

Both must resolve inside `$ROOTFS`. The launcher links each name from
`$ROOTFS/usr/lib` or `$ROOTFS/usr/lib/aarch64-linux-gnu` when the file exists.
It also appends existing multiarch directories to the RPATH, so a rootfs that
uses the Debian-style multiarch layout is supported.

This is why no global `libxml2.so.2` is needed. The Termux-glibc Mesa chain is
not loaded, and the rootfs `libxml2.so.16` is resolved from the private
directory before the Termux glibc paths.

### 4.3 Vulkan and DRI

The launcher writes a private Freedreno Vulkan ICD whose `library_path` is the
absolute rootfs `libvulkan_freedreno.so`:

```sh
cat "$PREFIX/libexec/mango-termux/vulkan/icd.d/freedreno_icd.aarch64.json"
```

Both `VK_ICD_FILENAMES` and `VK_DRIVER_FILES` point at that manifest.
`LIBGL_DRIVERS_PATH` points at `$ROOTFS/usr/lib/dri`, which contains the KGSL
Gallium driver. `GBM_BACKENDS_PATH` is set to `$ROOTFS/usr/lib/gbm` when that
directory exists.

These variables are scoped to the Noctalia process and its native children.
Bionic Termux children ignore the glibc EGL and Vulkan variables.

### 4.4 QML and Qt note

The current launcher sets no QML or Qt variables because Noctalia 5.4.1 has no
Qt or QML component. There is no `quickshell`, `qs`, or QML process to launch,
and the ELF has no Qt `NEEDED` libraries. No `QML2_IMPORT_PATH`,
`QML_IMPORT_PATH`, `QT_PLUGIN_PATH`, or `QT_QPA_PLATFORM_PLUGIN_PATH` is
exported.

If a future Noctalia or Quickshell build uses Qt, the relevant values would be
`QML2_IMPORT_PATH="$ROOTFS/usr/lib/qt6/qml"`, `QML_IMPORT_PATH` with the same
value, `QT_PLUGIN_PATH="$ROOTFS/usr/lib/qt6/plugins"`, and
`QT_QPA_PLATFORM_PLUGIN_PATH="$ROOTFS/usr/lib/qt6/plugins/platforms"`. These
are hypothetical values for a future build, not variables set by the current
launcher.

### 4.5 Fonts, assets, and XDG paths

The native launcher assigns the resource paths directly. Inspect the relevant
assignments:

```sh
grep -n 'XDG_DATA_DIRS\|XDG_CONFIG_DIRS\|NOCTALIA_ASSETS_DIR\|FONTCONFIG_PATH' "$PREFIX/bin/mango-noctalia"
```

The effective values are:

- `XDG_DATA_DIRS="$PREFIX/share:$ROOTFS/usr/share"` — native Termux desktop
  entries first, then rootfs data;
- `XDG_CONFIG_DIRS="$PREFIX/etc/xdg:$ROOTFS/etc/xdg"` — native XDG config
  first, then rootfs config;
- `NOCTALIA_ASSETS_DIR="$ROOTFS/usr/share/noctalia/assets"` — Noctalia assets;
- `FONTCONFIG_PATH=$PREFIX/etc/fonts` — native Termux fontconfig, when that
  directory exists.

Noctalia also uses native `XDG_CONFIG_HOME=$HOME/.config`,
`XDG_STATE_HOME=$HOME/.local/state`, and
`XDG_DATA_HOME=$HOME/.local/share`. Configuration and state therefore live in
the Termux home directory, not in the rootfs.

## 5. MangoWM integration

### 5.1 mango-ipc

MangoWM creates an IPC socket at `$XDG_RUNTIME_DIR/mango-<pid>.sock` and sets
`MANGO_INSTANCE_SIGNATURE` inside its own process. Because Noctalia is started
by MangoWM, it inherits that variable and connects the workspace backend to
`mango-ipc`, not only to the generic `ext-workspace` protocol.

List the socket:

```sh
ls -l "$PREFIX/tmp"/mango-*.sock
```

`XDG_RUNTIME_DIR` is `$PREFIX/tmp`, so the socket path is under the Termux
prefix. `MANGO_INSTANCE_SIGNATURE` is an inherited environment value; it is not
a proot bind and does not depend on a bind mount.

When a shell command must talk to MangoWM outside the autostart context, export
the signature explicitly with
`MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"`.

### 5.2 Layer-shell and panels

Noctalia uses `wlr-layer-shell` for its panels and bars. MangoWM supports the
layer-shell protocol, so panels are placed by the compositor without extra
MangoWM configuration. No `mics.conf` entry, output rule, or special surface
setting is required for layer-shell panels.

Noctalia is an ordinary Wayland client of the nested MangoWM compositor. It
does not create a second compositor and does not run inside a proot jail.

### 5.3 Autostart and keybindings

`~/.config/mango/mics.conf` must contain one native autostart line:

```ini
exec=noctalia
```

`mango-integrate` rewrites an old `exec=...start-noctalia.sh` line to
`exec=noctalia` and replaces a proot `start-noctalia.sh` with a native shim
that executes `$PREFIX/bin/noctalia`. Backups use the `.mango-bak` suffix.

Keybindings invoke the native `noctalia` command. Typical entries include
`noctalia msg panel-toggle launcher`, `noctalia msg panel-toggle wallpaper`, and
volume or brightness commands. The host `noctalia` executable is the native
launcher, not a proot proxy. Check the configured bindings:

```sh
grep -n 'noctalia msg' ~/.config/mango/binds.conf
```

## 6. Configuration and migration

### 6.1 Build and integrate

A rebuild installs the current native launcher and re-applies integrations:

```sh
./build-termux.sh
"$PREFIX/bin/mango-integrate" --check
```

`build-termux.sh` installs `mango-noctalia` and runs `mango-integrate`.
`MANGO_SKIP_INTEGRATIONS=1` skips the integration step.
`MANGO_SKIP_FIREFOX_FIX=1` passes `--no-firefox` to the integration helper. A
rootfs is optional at build time; the next MangoWM start applies Noctalia
integration when a rootfs becomes available.

`mango-integrate --check` is read-only. It returns zero when the wrappers,
native Noctalia launcher, Firefox entries, Firefox launcher, and terminal
entries are consistent. A nonzero result identifies the missing item.

### 6.2 Config, state, and wallpapers

Apply the integrations idempotently and check for stale root paths:

```sh
"$PREFIX/bin/mango-integrate"
grep -R '/root/' ~/.local/state/noctalia ~/.config/noctalia 2>/dev/null || true
```

`mango-integrate` performs the following native migration:

- installs `$PREFIX/bin/noctalia` as a copy of `$PREFIX/bin/mango-noctalia`;
- saves an existing old proxy as `$PREFIX/bin/noctalia.proot-bak`;
- moves rootfs `root/.config/noctalia`, `root/.local/state/noctalia`, and
  `root/.local/share/noctalia` to the native `$HOME/...` paths only when the
  native path does not already exist;
- copies missing files from rootfs `root/Walls` to `$HOME/Walls`;
- rewrites `/root/` to the native home in native `settings.toml` files and
  creates `.mango-bak` backups;
- restores terminal desktop entries to direct `Exec=kitty` or `Exec=foot`;
- points Firefox entries at `$PREFIX/bin/mango-firefox`;
- removes the old host bridge.

`mango-host-run` and `install-noctalia-host-bridge.sh` are no longer installed.
There is no wrapper or bridge for Noctalia.

### 6.3 Manual launcher check

Check the installed launcher directly:

```sh
"$PREFIX/bin/noctalia" --version
```

The expected output is `noctalia v5.4.1`. The command prepares or reuses the
private native binary and reports the Noctalia version. IPC commands such as
`noctalia msg` require a running session and the correct `XDG_RUNTIME_DIR` and
`WAYLAND_DISPLAY`.

## 7. Verification

### 7.1 Process tree and environment

Inspect the relevant processes:

```sh
ps -A -o pid,stat,comm,args | grep -E 'mango|noctalia|proot'
```

The expected tree is `mango -> dbus-run-session -> noctalia-native`. The
`dbus-run-session` stage appears when no session bus was inherited. No `proot`
or `proot-distro` process is present.

The Noctalia process name is `noctalia-native`. Stop it with
`pkill -f 'libexec/mango-termux/noctalia-native'`. Do not use
`pkill -x noctalia`; the exact process name is `noctalia-native`.

Read `/proc/<pid>/environ` for the running process. It must not contain
`LD_LIBRARY_PATH` or `LD_PRELOAD`. Section 3.3 shows the environment query.

### 7.2 EGL and renderer

Restart with logging and filter the important lines:

```sh
mango-termux --restart > "$PREFIX/tmp/mango.log" 2>&1
grep -E 'gl initialized|connected compositor|workspace backend|connected to session bus|fatal|ERR' "$PREFIX/tmp/mango.log"
```

A working start reports `gl initialized EGL`, `connected compositor`,
`workspace backend=mango-ipc`, and `connected to session bus`. The filtered
output must not contain `fatal` or `ERR`.

Also check that the log has no `eglGetDisplay failed`, no `libxml2.so.2`
request, and no `/root/Walls` warning. A Freedreno renderer indicates the rootfs
Mesa/KGSL path; `llvmpipe` indicates the software fallback described in section
9.6.

### 7.3 IPC and workspaces

With the session running, exercise the native IPC path:

```sh
export MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"
mmsg get version
noctalia msg color-scheme-get
noctalia msg workspace-switch next
mmsg get tags X11-1
```

`mmsg get version` confirms MangoWM IPC. `noctalia msg color-scheme-get`
returns the built-in Noctalia scheme. `workspace-switch next` changes the
current workspace, and the `mmsg get tags X11-1` result reflects the change.

## 8. Native child applications

### 8.1 Desktop entries

Noctalia sees both native Termux desktop entries and rootfs entries through
`XDG_DATA_DIRS`. Inspect the effective terminal and Firefox commands:

```sh
grep -H '^Exec=' "$PREFIX/share/applications/kitty.desktop" "$PREFIX/share/applications/foot.desktop" "$PREFIX/share/applications/com.mitchellh.ghostty.desktop" "$PREFIX/share/applications/firefox.desktop"
```

Terminal entries should invoke `kitty`, `foot`, or `ghostty` directly.
`mango-integrate` restores entries that were previously routed through the old
host bridge. Firefox entries should invoke `$PREFIX/bin/mango-firefox` directly.

Native child applications are Termux (bionic) processes. They connect to the
nested session through `wayland-0` and inherit the native session environment.

### 8.2 fish and terminals

The native launcher sets `SHELL=$PREFIX/bin/fish` and falls back to
`$PREFIX/bin/bash` when fish is not executable. It also sets
`PATH=$PREFIX/bin:/system/bin:/system/xbin`. Check the active shell and the
terminal shell configuration:

```sh
printf '%s\n' "$SHELL"
grep -R '^shell' ~/.config/kitty ~/.config/foot 2>/dev/null || true
```

`mango-integrate` creates missing terminal configs that use the same shell:
`~/.config/kitty/kitty.conf`, `~/.config/foot/foot.ini`, and
`~/.config/ghostty/config.ghostty`. When those files are created by integration,
that terminal starts with fish, or bash when fish is unavailable.

### 8.3 Firefox

Firefox uses the native Termux wrapper. Check the desktop entry:

```sh
grep -n 'mango-firefox' "$PREFIX/share/applications/firefox.desktop"
```

The `Exec=` value must point directly at `$PREFIX/bin/mango-firefox`, not at a
proot bridge. Firefox is a bionic application and ignores the glibc EGL and
Vulkan variables used by Noctalia.

## 9. Troubleshooting

### 9.1 Noctalia does not start

Check the installed pieces first:

```sh
"$PREFIX/bin/noctalia" --version
"$PREFIX/bin/mango-integrate" --check
ls -l "$PREFIX/bin/noctalia" "$PREFIX/bin/mango-noctalia" "$PREFIX/libexec/mango-termux/noctalia-native"
```

Common causes:

- no usable rootfs: install an Arch rootfs with `usr/bin/noctalia`, or set
  `NOCTALIA_ROOTFS`;
- `patchelf` missing: run `pkg install patchelf`;
- Termux glibc loader missing: verify
  `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`;
- rootfs `libstdc++.so.6` missing: the rootfs is incomplete.

The message `noctalia: already running` means an existing Noctalia instance
owns the IPC endpoint. Stop the native process with
`pkill -f 'libexec/mango-termux/noctalia-native'` and restart the session.

### 9.2 EGL, libxml2, and eglGetDisplay

Verify the private EGL manifest and rootfs GBM link:

```sh
cat "$PREFIX/libexec/mango-termux/egl_vendor.d/50_mesa.json"
readlink -f "$PREFIX/libexec/mango-termux/rootfs-libs/libgbm.so.1"
rm -rf "$PREFIX/libexec/mango-termux"
"$PREFIX/bin/noctalia" --version
```

The manifest must point at the absolute rootfs `libEGL_mesa.so.0`, and the GBM
link must resolve inside the rootfs. Removing `$PREFIX/libexec/mango-termux`
deletes the cached native binary, symlinks, and manifests; the next
`noctalia` run rebuilds them.

Do not create a global `libxml2.so.2` and do not modify the rootfs. If the log
still reports `eglGetDisplay failed` or requests `libxml2.so.2`, the private
cache is stale or the rootfs lacks Mesa 27; rebuild the cache and verify section
2.3.

### 9.3 /root/Walls wallpaper warning

Re-apply the native migration and inspect the result:

```sh
"$PREFIX/bin/mango-integrate"
grep -R '/root/' ~/.local/state/noctalia ~/.config/noctalia 2>/dev/null || true
ls -l ~/Walls
```

`mango-integrate` copies missing wallpapers from rootfs `root/Walls` to
`$HOME/Walls` and rewrites `/root/` paths in the native `settings.toml` files.
Backups use the `.mango-bak` suffix. A remaining `/root/` reference may mean
the native config was not migrated because a native path already existed;
inspect the file and the backup instead of deleting the rootfs data.

### 9.4 mango-ipc is not used

Check whether the running process inherited the MangoWM signature:

```sh
pid=$(pgrep -f 'libexec/mango-termux/noctalia-native' | head -1)
tr '\0' '\n' < "/proc/$pid/environ" | grep MANGO_INSTANCE_SIGNATURE
```

If the variable is absent, Noctalia was started outside the MangoWM autostart
context. For a manual launch, export
`MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"` first.
With autostart, MangoWM provides the value directly. `MANGO_INSTANCE_SIGNATURE`
is not a proot bind; it is an inherited environment variable.

A log line `workspace backend=ext-workspace` instead of
`workspace backend=mango-ipc` confirms that the signature was missing.

### 9.5 Wayland and D-Bus

Check the Wayland socket and the native D-Bus helper:

```sh
ls -l "$PREFIX/tmp"/wayland-*
command -v dbus-run-session
```

`XDG_RUNTIME_DIR` must be `$PREFIX/tmp` and `WAYLAND_DISPLAY` must be
`wayland-0`. If `DBUS_SESSION_BUS_ADDRESS` is already set, Noctalia inherits it.
Otherwise the launcher re-executes itself under the native Termux
`dbus-run-session` when that command exists.

Use native Termux D-Bus, not Arch D-Bus. System D-Bus services such as upower,
NetworkManager, logind, and polkit are not available in this Termux session.
PipeWire audio and Secret Service keyring integration are optional and depend
on separate native services.

### 9.6 llvmpipe or black screen

Check the KGSL device and the rootfs KGSL driver:

```sh
ls -l /dev/kgsl-3d0 "$ROOTFS/usr/lib/dri/kgsl_dri.so"
```

Both must exist. The launcher does not set `NOCTALIA_GPU`; that selector has
been removed. Rendering uses the rootfs Mesa 27 stack and the private EGL
manifest. If `/dev/kgsl-3d0` is unavailable or the rootfs lacks
`dri/kgsl_dri.so`, Noctalia cannot use KGSL and may fall back to llvmpipe or
render a black surface.

### 9.7 Native applications do not appear

Check that the native applications are installed in Termux:

```sh
command -v kitty foot ghostty firefox
```

Noctalia finds desktop entries through
`XDG_DATA_DIRS="$PREFIX/share:$ROOTFS/usr/share"`. Missing Termux applications
cannot appear in the launcher. If the applications exist but their entries are
missing, run `mango-integrate`; it restores terminal entries and the Firefox
launcher.

### 9.8 Manual repair

Rebuild the native runtime, re-apply integrations, and restart:

```sh
rm -rf "$PREFIX/libexec/mango-termux"
"$PREFIX/bin/mango-integrate"
mango-termux --restart
```

This removes the cached native binary, private libraries, EGL manifest, and
Vulkan ICD. The next launch recreates them from the detected rootfs. Keep the
rootfs intact; it remains the source for the ELF and resources.

## 10. Update and removal

### 10.1 Update

Update the rootfs package, re-apply integrations, and restart:

```sh
proot-distro login archlinuxarm -- pacman -Syu --noconfirm
"$PREFIX/bin/mango-integrate"
mango-termux --restart
```

`proot-distro` is used only for the package update. The restart still runs
Noctalia natively. A newer rootfs `noctalia` binary or `libstdc++.so.6`
invalidates the private native copy, so the launcher rebuilds it before
starting.

### 10.2 Reset native state

Reset the native Noctalia configuration and state while keeping backups:

```sh
mv ~/.config/noctalia ~/.config/noctalia.bak 2>/dev/null || true
mv ~/.local/state/noctalia ~/.local/state/noctalia.bak 2>/dev/null || true
mango-termux --restart
```

The next start creates a fresh native configuration. Wallpapers under
`$HOME/Walls` are not removed by this reset.

### 10.3 Removal

Remove the native launcher and its private runtime:

```sh
rm -f "$PREFIX/bin/noctalia" "$PREFIX/bin/mango-noctalia"
rm -rf "$PREFIX/libexec/mango-termux"
```

Then remove the `exec=noctalia` line from `~/.config/mango/mics.conf`. To remove
the rootfs package as well, use
`proot-distro login archlinuxarm -- pacman -Rns noctalia`.

Do not restore the old proot proxy. A `$PREFIX/bin/noctalia.proot-bak` file, if
present, is only a stale backup of the removed proxy.

## 11. Environment reference

The native launcher and the autostart path use the following values. Paths in
this list are the effective values after `mango-noctalia` applies its
environment.

- `NOCTALIA_ROOTFS` — optional explicit rootfs override. When unset, the
  launcher searches `installed-rootfs/*` and `containers/*/rootfs`.
- `ROOTFS` — the selected rootfs for the current shell or guide session; it is
  not exported by the launcher itself.
- `HOME` — native Termux home, normally
  `/data/data/com.termux/files/home`.
- `PREFIX` — native Termux prefix, normally
  `/data/data/com.termux/files/usr`.
- `PATH` — `$PREFIX/bin:/system/bin:/system/xbin`.
- `SHELL` — `$PREFIX/bin/fish`, with `$PREFIX/bin/bash` as the fallback.
- `TMPDIR` — `$PREFIX/tmp`.
- `XDG_RUNTIME_DIR` — `$PREFIX/tmp`.
- `WAYLAND_DISPLAY` — `wayland-0` by default.
- `DISPLAY` — `:0` by default for nested Xwayland children.
- `XDG_CONFIG_HOME` — `$HOME/.config`.
- `XDG_STATE_HOME` — `$HOME/.local/state`.
- `XDG_DATA_HOME` — `$HOME/.local/share`.
- `XDG_DATA_DIRS` — `$PREFIX/share:$ROOTFS/usr/share`, with any existing
  entries appended.
- `XDG_CONFIG_DIRS` — `$PREFIX/etc/xdg:$ROOTFS/etc/xdg`, with any existing
  entries appended.
- `NOCTALIA_ASSETS_DIR` — `$ROOTFS/usr/share/noctalia/assets`.
- `FONTCONFIG_PATH` — `$PREFIX/etc/fonts` when that directory exists.
- `__EGL_VENDOR_LIBRARY_DIRS` —
  `$PREFIX/libexec/mango-termux/egl_vendor.d`.
- `VK_ICD_FILENAMES` and `VK_DRIVER_FILES` — the absolute rootfs Freedreno ICD
  manifest under `$PREFIX/libexec/mango-termux/vulkan/icd.d`.
- `LIBGL_DRIVERS_PATH` — `$ROOTFS/usr/lib/dri` when that directory exists.
- `GBM_BACKENDS_PATH` — `$ROOTFS/usr/lib/gbm` when that directory exists.
- `DBUS_SESSION_BUS_ADDRESS` — inherited when present; otherwise a native Termux
  session bus is started with `dbus-run-session`.
- `MANGO_INSTANCE_SIGNATURE` — inherited from MangoWM. It enables the
  `mango-ipc` workspace backend. It is not set by the Noctalia launcher and is
  not a proot bind.
- `MANGO_NOCTALIA_DBUS_WRAPPED` — internal guard set to `1` during the
  `dbus-run-session` re-exec to prevent recursion.
- `NOCTALIA_GPU` — removed and not read. The launcher does not set it.

The launcher clears `LD_LIBRARY_PATH`, `LD_PRELOAD`,
`MESA_LOADER_DRIVER_OVERRIDE`, `GALLIUM_DRIVER`,
`__EGL_VENDOR_LIBRARY_FILENAMES`, `EGL_PLATFORM`, `FD_KGSL_DMABUF`, and all
`PROOT_*` variables. It does not export `LD_LIBRARY_PATH` or `LD_PRELOAD`.
Library resolution relies on the patched RPATH and the private `rootfs-libs`
directory.

QML and Qt variables are not set. The current Noctalia 5.4.1 binary has no Qt
or QML component. The hypothetical values in section 4.4 apply only to a future
Quickshell or Qt build.
