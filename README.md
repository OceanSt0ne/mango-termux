[English](README.md) | [Русский](README_ru.md)

# Mango Wayland Compositor for Termux

> Native Termux/Android port of [mango](https://github.com/mangowm/mango) 0.18.5, running inside Termux:X11 without PRoot. Qualcomm Adreno only.
> The session uses a private KGSL Mesa `.deb` stack: use at your own risk and back up your data first.

## Table of Contents

- [1. Overview](#1-overview)
- [2. Requirements](#2-requirements)
- [3. Build](#3-build)
- [4. Quick Start](#4-quick-start)
- [5. Launcher and Environment](#5-launcher-and-environment)
- [6. Configuration](#6-configuration)
- [7. Rendering and GPU](#7-rendering-and-gpu)
- [8. Native Noctalia](#8-native-noctalia)
- [9. Integrations and Helper Scripts](#9-integrations-and-helper-scripts)
- [10. Troubleshooting](#10-troubleshooting)
- [11. Documentation](#11-documentation)

## 1. Overview

Mango is a Wayland compositor. This repository is its native Termux/Android port, based on wlroots 0.20. It is a regular Termux program, not a PRoot wrapper.

Architecture:

- Termux:X11 owns the Android surface and display.
- Mango is an X11 client of Termux:X11, uses the wlroots X11 backend, and creates a nested Wayland session.
- The default compositor path is Mesa Zink on Freedreno Vulkan (Turnip).
- Session clients default to the private Freedreno/KGSL Mesa 27 stack.
- Alternative paths are Android EGL/AHardwareBuffer (`ahb`) and software rendering (`pixman`).
- Nested Xwayland is created for X11 applications and normally uses display `:1`.

Limitations:

- Adreno only. MediaTek, Exynos, Tensor and other SoCs are unsupported.
- Termux:X11 has no DRI3, so AHB frames are copied through SHM. Expect copy overhead.
- The default Xwayland server is a stable no-glamor server with indirect GLX, not a DRI3 server.
- High `vkmark` numbers measure GPU submission throughput, not display refresh.
- The private KGSL Mesa stack comes from pinned third-party `.deb` packages and is installed outside the stock Termux Mesa tree.

## 2. Requirements

- Android arm64 device with a Qualcomm Adreno GPU.
- Termux, the Termux:X11 app, and the `termux-x11-nightly` package.
- No PRoot, systemd, udev, libinput, or DRM/KMS is required.
- Bundled `scenefx` 0.5 sources are pre-patched; scenefx is not available as a Termux package.
- The `wlroots` 0.20 package is required.
- Private KGSL Mesa 27 is optional, but required for hardware GL in session clients.

Install the build dependencies:

```bash
pkg install x11-repo
pkg update
pkg install termux-x11-nightly
pkg install clang pkg-config ninja patchelf git python-pip \
  wlroots libwayland libwayland-protocols libxkbcommon libpixman \
  libdrm libxcb xcb-util-wm xcb-util-renderutil xwayland \
  libglvnd-dev mesa mesa-dev mesa-vulkan-icd-freedreno \
  littlecms vulkan-loader pcre2 pango cjson libandroid-wordexp \
  dpkg curl
python -m pip install meson
```

`mesa-dev` provides `gbm.h`; missing it is a common build error.

## 3. Build

The supported path is `./build-termux.sh`. The script:

- checks native tools and pkg-config dependencies;
- applies or reverts the bundled `scenefx` patch from `termux-compat/scenefx-termux.patch`;
- builds scenefx and mango as release with `-O3`;
- installs into `$PREFIX`;
- creates `$PREFIX/lib/mango-termux/` with the AHB binary and private `libwlroots-0.20.so` / `libscenefx-0.5.so`, patched to Android EGL/GLES;
- creates `~/.config/mango/config.conf` and `config.toml` only if absent, enabling visible effects for new configs;
- installs the private Freedreno/KGSL Mesa 27 stack when `/dev/kgsl-3d0` exists;
- runs `mango-integrate`, installs the Firefox wrapper, and installs the native Noctalia launcher when a usable rootfs is found.

Build-time variables:

- `PREFIX` — Termux prefix; default `/data/data/com.termux/files/usr`.
- `SCENEFX_DIR` — alternative scenefx source tree.
- `MANGO_SKIP_KGSL=1` — skip the private Mesa 27 stack.
- `MANGO_SKIP_INTEGRATIONS=1` — skip `mango-integrate`.
- `MANGO_SKIP_FIREFOX_FIX=1` — skip the Firefox WebGL wrapper.

```bash
./build-termux.sh
MANGO_SKIP_KGSL=1 ./build-termux.sh
MANGO_SKIP_INTEGRATIONS=1 ./build-termux.sh
MANGO_SKIP_FIREFOX_FIX=1 ./build-termux.sh
```

Verify the installation:

- `mango -v` reports version 0.18.5.
- Installed commands include `mango`, `mango-termux`, `mango-x11-check`, `mango-integrate`, `mango-noctalia`, `noctalia-exec`, `noctalia-terminal`, `mango-firefox`, and `mango-gpu-run`.
- After source changes, run `./build-termux.sh` again and restart the session.

## 4. Quick Start

Open the Termux:X11 app before starting Mango. Start the launcher from Termux with `mango-termux`.

The first run creates configs and may install the KGSL stack and integrations. Existing config files are never overwritten by the build; visible effects are enabled only in newly created configs.

```bash
mango-termux
mango-termux --restart
MANGO_TERMUX_RENDERER=ahb mango-termux
MANGO_TERMUX_RENDERER=pixman mango-termux
```

If the session does not appear, check the Termux:X11 app and the launcher log at `$PREFIX/tmp/termux-x11.log`.

## 5. Launcher and Environment

`mango-termux` is the installed copy of `run-mango.sh`. It:

- sets `PREFIX`, `TMPDIR`, `XDG_RUNTIME_DIR`, a native `SHELL`, and `TERMINAL`;
- exports native XKB defaults: `XKB_CONFIG_ROOT=$PREFIX/share/X11/xkb`, `XKB_DEFAULT_LAYOUT=us,ru`, `XKB_DEFAULT_OPTIONS=grp:win_space_toggle`, `XKB_DEFAULT_RULES=evdev`, and `XKB_DEFAULT_MODEL=pc105`;
- writes `$PREFIX/tmp/mango-session.env` for Noctalia children;
- removes stale `wayland-*` sockets and locks;
- starts or reuses Termux:X11;
- configures the stable Xwayland wrapper;
- selects the renderer and binary;
- runs `mango-integrate` unless skipped;
- reuses a running Mango instance through `MANGO_INSTANCE_SIGNATURE` unless `--restart` is used.

| Variable | Default | Purpose |
| --- | --- | --- |
| `MANGO_BACKEND` | `x11` | `x11`, `wayland`, or `headless` |
| `MANGO_X11_DISPLAY` | `$DISPLAY` or `:0` | Termux:X11 display |
| `MANGO_BIN` | auto | Override the Mango binary |
| `MANGO_TERMUX_RENDERER` | `turnip` | `turnip`, `ahb`, or `pixman` |
| `MANGO_TERMUX_GPU` | auto | Compatibility alias: `1`/`ahb`, `0`/pixman, `turnip`/`zink` |
| `MANGO_RESTART` | `0` | Stop a running Mango before starting |
| `MANGO_XWAYLAND_GLAMOR` | `0` | `1` opts into the DRI3/glamor Xwayland server |
| `MANGO_X11_INPUT_PREFS` | `touchMode:1 tapToMove:false` | Termux:X11 input preferences: trackpad mode and no tap-to-move; empty skips |
| `WLR_XWAYLAND` | auto | Override the Xwayland binary |
| `XDG_RUNTIME_DIR` | `$PREFIX/tmp` | Wayland/X11 runtime directory |
| `NOCTALIA_ROOTFS` | auto | Rootfs used by the native Noctalia installer |

`TERMINAL` and the `XKB_*` defaults are set automatically; override them only when necessary.

```bash
MANGO_X11_DISPLAY=:1 mango-termux
MANGO_TERMUX_RENDERER=ahb mango-termux
MANGO_XWAYLAND_GLAMOR=1 mango-termux
WLR_XWAYLAND=/path/to/Xwayland mango-termux
mango-termux --restart -s foot
```

Extra arguments are passed to Mango itself.

## 6. Configuration

Mango searches for a config in this order:

1. `$HOME/.config/mango/config.conf`
2. `$HOME/.config/mango/config.toml`
3. `$PREFIX/etc/mango/config.conf`
4. `$PREFIX/etc/mango/config.toml`

`config.conf` and `config.toml` are alternative formats; `config.conf` is the installed default on Termux. Modular configs are supported with `source=./file.conf`; common split files are `binds.conf`, `env.conf`, `input.conf`, `mics.conf`, `monitors.conf`, `windows.conf`, `animations.conf`, `layouts.conf`, and `tags.conf`.

Reload the shipped default with `Super+R`. User configs may remap it. Enable visible effects with:

```ini
blur=1
blur_layer=1
shadows = 1
layer_shadows = 1
border_radius=12
```

Effects require the GPU path (`mango-termux`), not software `pixman`.

Default keybindings from the shipped `assets/config.conf`:

- `Super+R` — reload config.
- `Super+M` — quit Mango.
- `Alt+Q` — close focused window.
- `Alt+Return` — launch `foot`.
- `Alt+Space` — launch `rofi -show drun`.
- `Super+Tab` — focus next window.
- `Alt+Tab` — toggle jump.
- `Alt+F` — toggle fullscreen.

User configs and `binds.conf` may override these defaults. Validate or migrate a config with:

```bash
mango -p
mango -p -c "$HOME/.config/mango/config.conf"
./termux-compat/fix-mango-config.sh --dry-run
./termux-compat/fix-mango-config.sh
```

`fix-mango-config.sh` accepts `-n`/`--dry-run`, `--no-validate`, an optional positional `CONFIG_DIR`, and `-h`/`--help`. It creates timestamped backups.

## 7. Rendering and GPU

Default `turnip` mode:

- Mango itself renders through Mesa Zink on Freedreno Vulkan/Turnip.
- Child clients get the native KGSL Mesa 27 environment, not global Zink.
- The private root is `$PREFIX/opt/mesa-kgsl` when `lib/dri/kgsl_dri.so` exists; otherwise stock `$PREFIX` is used if it has the KGSL driver.
- The launcher sets `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, `GBM_BACKENDS_PATH`, `MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `GALLIUM_DRIVER=kgsl`, `__EGL_VENDOR_LIBRARY_FILENAMES`, `VK_DRIVER_FILES`, and `VK_ICD_FILENAMES` as applicable.
- If KGSL is missing, the launcher warns and clients may fall back to llvmpipe.

`ahb` mode uses `$PREFIX/lib/mango-termux/mango` with Android system EGL/GLES and AHardwareBuffer support. It has no DRI3 and uses the bundled private `libwlroots-0.20.so` and `libscenefx-0.5.so`. Select it with `MANGO_TERMUX_RENDERER=ahb` or `MANGO_TERMUX_GPU=1`.

`pixman` mode is software rendering with the normal Mesa binary; select it with `MANGO_TERMUX_RENDERER=pixman` or `MANGO_TERMUX_GPU=0`.

The private KGSL stack is installed by `termux-compat/install-freedreno-kgsl.sh`. It uses the pinned lfdevs release `freedreno-27.0.0-devel-20261025-r2`, verifies SHA-256, backs up an old tree as `mesa-kgsl.bak.<timestamp>`, and does not replace stock Termux Mesa.

AHB caveat: Termux:X11 presents through SHM copies, so AHB removes GPU and driver limits but does not eliminate the copy to the Android surface.

Xwayland:

- The default wrapper is `$PREFIX/tmp/mango-xwayland`. It sets `XWAYLAND_NO_GLAMOR=1` and `LIBGL_DRI3_DISABLE=1`, then execs `Xwayland +iglx -shm`.
- `MANGO_XWAYLAND_GLAMOR=1` opts into DRI3/glamor and clears those limits.
- `WLR_XWAYLAND` overrides the real server.
- X11 apps usually see `DISPLAY=:1`; the outer Termux:X11 root is `:0`.

## 8. Native Noctalia

Noctalia 5.4.1 runs natively in Termux with the Termux glibc loader. The Arch rootfs supplies the Noctalia binary, Qt/Noctalia resources, and libraries. PRoot is used only for optional rootfs bootstrap and package setup, never at runtime.

Rootfs discovery order:

1. `--rootfs PATH`
2. `NOCTALIA_ROOTFS`
3. `$PREFIX/var/lib/proot-distro/installed-rootfs/*`
4. `$PREFIX/var/lib/proot-distro/containers/*/rootfs`

The installer bootstraps `archlinuxarm` and Noctalia when no usable rootfs exists (network required); `--no-bootstrap` makes that an error. It:

- builds a private runtime under `$PREFIX/libexec/mango-termux`;
- copies required rootfs libraries into `rootfs-libs`;
- uses `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`;
- creates a patched fallback cache with `patchelf` when possible;
- writes `runtime.env`;
- installs the `noctalia` and `mango-noctalia` launchers;
- installs `noctalia-exec` and `noctalia-terminal`;
- clears foreign IM/XKB variables and restores native XKB paths for children.

```bash
./install-noctalia-termux.sh
./install-noctalia-termux.sh --rootfs /path/to/rootfs
./install-noctalia-termux.sh --check
./install-noctalia-termux.sh --force --no-integrate
```

Installer flags: `--rootfs PATH`, `--force`, `--check`, `--no-integrate`, `--bootstrap-rootfs`, `--no-bootstrap`, `--quiet`, and `-h`/`--help`. `--check` is read-only; `--force` rebuilds the private runtime.

`noctalia-exec` rebuilds a clean native Termux child environment. It keeps the Wayland/X11 socket, D-Bus, XDG runtime, cursor, and KGSL/Turnip overrides; drops rootfs EGL/Mesa paths and inherited `GTK_IM_MODULE`, `QT_IM_MODULE`, `SDL_IM_MODULE`, `GLFW_IM_MODULE`, `XMODIFIERS`, `INPUT_METHOD`, and `XKB_*`; and resolves `TERMINAL` to an installed terminal.

`noctalia-terminal` is used because Noctalia `runInTerminal` calls `$TERMINAL` directly. It routes through `noctalia-exec` and prefers Wayland-native `foot`, then `kitty`, then `ghostty`.

Noctalia settings for this port:

- `launch_apps_custom_command = "noctalia-exec $CMD"`;
- `reserve_space = true` for the top and bottom bars so client titlebars are not drawn underneath them;
- overlay launchers may take keyboard focus; top and bottom layer bars must not steal focus from clients.

After changes, run `mango-integrate --check` and `mango-termux --restart`.

## 9. Integrations and Helper Scripts

`mango-integrate` is idempotent and normally runs from the build or launcher. It restores terminal desktop entries, patches Firefox entries and the launcher, maintains native Noctalia launchers and `env.conf` (`TERMINAL=noctalia-terminal`), and creates safe shell defaults. Backups end in `.mango-bak`.

Flags: `--quiet`, `--check`, `--no-firefox`, `--no-terminals`, and `-h`/`--help`.

Helper scripts:

- `termux-compat/install-freedreno-kgsl.sh` — private Mesa 27 KGSL stack.
- `termux-compat/install-firefox-webgl.sh` — Firefox WebGL wrapper; supports `--check`; can be skipped with `MANGO_SKIP_FIREFOX_FIX=1`.
- `termux-compat/install-benchmark-fixes.sh` — native glmark2 wrappers and glibc vkmark/assimp/Turnip fixes.
- `termux-compat/build-arch-turnip.sh` — Arch rootfs Turnip build for vkmark; optional, benchmark-only, and not part of the normal runtime.
- `termux-compat/fix-mango-config.sh` — config key migration.
- `termux-compat/scenefx-termux.patch` — bundled scenefx AHB/Termux patch.
- `termux-compat/mango-*`, `termux-compat/noctalia-*` — installed launchers and helpers.

```bash
mango-integrate
mango-integrate --check
mango-integrate --no-firefox --quiet
pkg install glmark2 libjpeg-turbo patchelf binutils
./termux-compat/install-benchmark-fixes.sh
./termux-compat/build-arch-turnip.sh
glmark2
glmark2-es2
grun --shell vkmark
```

The benchmark group is optional. `build-arch-turnip.sh` is only for the Arch/PRoot benchmark environment and is not required for normal sessions.

## 10. Troubleshooting

```bash
echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
mango -v
mango-termux --restart -d
glxinfo -B 2>/dev/null | grep -E 'OpenGL renderer|OpenGL version'
vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverName'
```

Common issues:

- `gbm.h` missing: `pkg install mesa-dev`.
- Termux:X11 not reachable: open the app, run `mango-x11-check`, and read `$PREFIX/tmp/termux-x11.log`.
- llvmpipe or no effects: install the KGSL stack, verify `$PREFIX/opt/mesa-kgsl/lib/dri/kgsl_dri.so`, then run `mango-termux --restart`.
- Nested Xwayland dies or an X11 GL client aborts: keep `MANGO_XWAYLAND_GLAMOR=0` (default) and do not force glamor.
- 3D games with a locked cursor (Minecraft/LWJGL/GLFW) spin or snap to ±90°: keep Termux:X11 in trackpad mode with `MANGO_X11_INPUT_PREFS=touchMode:1 tapToMove:false` (the default) and restart with `mango-termux --restart`. `touchMode` values 2 and 3 send absolute touch coordinates and break pointer lock. Inspect or override the live values with `termux-x11-preference list` and `termux-x11-preference touchMode:1 tapToMove:false`.
- An X11 app opens on the outer `:0`: make sure it inherits `DISPLAY=:1` from the Mango session, and rebuild with Xwayland enabled.
- Firefox WebGL fails: run `mango-integrate`, then `termux-compat/install-firefox-webgl.sh`, and restart the session.
- Noctalia has no rootfs: use `--bootstrap-rootfs` or `--rootfs`; validate with `--check`; `patchelf` is needed for the fallback binary.
- Noctalia app shortcuts or IME are broken: launch through `noctalia-exec`, keep the native `XKB_CONFIG_ROOT`, and do not inherit rootfs IM variables.
- `vkmark` shows thousands of FPS: that is GPU submission throughput, not Termux:X11 refresh; judge smoothness visually.

Rebuild and restart with `./build-termux.sh && mango-termux --restart`.

## 11. Documentation

- [README.md](README.md) / [README_ru.md](README_ru.md) — current bilingual overview.
- [TERMUX_NOCTALIA.md](TERMUX_NOCTALIA.md) / [TERMUX_NOCTALIA_ru.md](TERMUX_NOCTALIA_ru.md) — detailed native Noctalia setup, runtime, verification, and troubleshooting guide; the installer remains canonical.
- [docs/](docs/index.md) — upstream MangoWM configuration documentation: bindings, configuration, visuals, window management, and patches.
- Upstream project: [mangowm/mango](https://github.com/mangowm/mango)
- License: see [LICENSE](LICENSE).
