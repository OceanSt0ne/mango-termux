**English** | [Russian](README_ru.md)

<div align="center">
  <img src="assets/mango.svg" alt="Mango Logo" width="120"/>

  <h1>Mango Wayland Compositor</h1>

  <p>A fast, feature-rich Wayland compositor.</p>

<a href="https://github.com/mangowm/mango/stargazers"><img src="https://img.shields.io/github/stars/mangowm/mango?style=flat&color=orange" alt="Stars"/></a>
<a href="https://github.com/mangowm/mango/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat" alt="License"/></a>
<a href="https://repology.org/project/mangowm/versions"><img src="https://repology.org/badge/tiny-repos/mangowm.svg" alt="Packaged in"/></a>
<a href="https://discord.gg/CPjbDxesh5"><img src="https://img.shields.io/discord/1430889676264177687?style=flat&logo=discord&label=discord" alt="Discord"/></a>

</div>

---

https://github.com/user-attachments/assets/bb83004a-0563-4b48-ad89-6461a9b78b1f

https://github.com/user-attachments/assets/be85e13f-7798-456d-957e-f8931687392e

> **Termux/Android port:** mango runs inside Termux:X11 with hardware effects
> (blur, shadows, rounded corners) via Android EGL + AHardwareBuffer. See
> [Termux / Android](#termux--android) below for build and usage instructions.

> See all layouts in action at [mangowm.github.io](https://mangowm.github.io/)

## Why Mango?

- **Lightweight & fast** — no functionality compromised
- **Excellent xwayland support** — run X11 apps without friction(Supports scale without blurring)
- **Tags, not workspaces** — each tag maintains its own independent window layout
- **Smooth animations** — window open/move/close, tag transitions, layer surfaces
- **Flexible layouts** — scroller, vertical-scroller, master-stack, monocle, dwindle and more
- **Rich window states** — swallow, group, minimize, maximize, global, overlay, fakefullscreen
- **Window effects** — blur, shadow, corner radius, opacity (via scenefx)
- **Excellent input method support** — text-input v2/v3
- **Powerful scratchpad** — sway-style scratchpad, special workspace and named-scratchpad support
- **label jump overview** — see all windows at a glance with easymotion jump label.
- **Gnome-style application switcher** — quick switching between apps
- **IPC** — send/receive messages from external programs
- **Hot-reload config** — no restart needed for keybinding changes
- **Zero flickering** — every frame is correct

## Vision

**Stability first.** After months of testing, Mango is solid enough for daily use. Breaking changes will be minimal.

**Practicality over novelty.** Features get added when they genuinely improve daily workflows — not for the sake of completeness.

**Focused scope.** Niche requests are evaluated by community interest. Significant upvotes move things forward.

## AI Policy

- **Pull requests:** AI may be used to assist in preparing a pull request (PR), but direct AI-generated PRs are not accepted. Contributors must clearly understand what the code does, whether the implementation is reasonable and rigorous, whether it wastes resources, and whether the implementation is sufficiently convergent rather than scattered.

- **Bug reports:** Using AI to report bugs is acceptable. AI-provided information may serve as reference material, which is preferable to reports that provide no reference information.

## Installation

[![Packaging status](https://repology.org/badge/vertical-allrepos/mangowm.svg)](https://repology.org/project/mangowm/versions)

### Arch Linux

```bash
yay -S mangowm-git
```
#### use my config
- install dependencies
```
yay -S rofi foot xdg-desktop-portal-wlr swaybg waybar wl-clip-persist cliphist wl-clipboard wlsunset xfce-polkit swaync pamixer wlr-dpms sway-audio-idle-inhibit-git swayidle dimland-git brightnessctl swayosd wlr-randr grim slurp satty swaylock-effects-git wlogout sox
```
- clone config
```
git clone https://github.com/DreamMaoMao/mango-config.git ~/.config/mango
```

### Other distributions

See the [Installation Guide](https://mangowm.github.io/docs/installation) for Fedora, Gentoo, Guix, NixOS, openSUSE, PikaOS, AerynOS, and building from source.

## Documentation

- **[mangowm.github.io](https://mangowm.github.io/)** — website docs with configuration reference, keybindings, layouts, IPC, and more
- **[GitHub Wiki](https://github.com/mangowm/mango/wiki/)** — community-maintained wiki

## Community

Join us on **[Discord](https://discord.gg/CPjbDxesh5)**

## Acknowledgements

- [wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) — Wayland protocol implementation
- [dwl](https://codeberg.org/dwl/dwl) — the foundation Mango builds on
- [scenefx](https://github.com/wlrfx/scenefx) — window effects library
- [owl](https://github.com/dqrk0jeste/owl) — animation groundwork
- [sway](https://github.com/swaywm/sway) — protocol reference

## Sponsor

If Mango makes your desktop better, consider supporting its development.

Thanks to everyone who has sponsored this project:

<table>
  <tr>
    <!-- add new sponsors here: copy the <td>...</td> block below -->
    <td align="center">
      <a href="https://github.com/dl09r">
        <img src="https://unavatar.io/github/dl09r" width="48" style="border-radius:50%"/><br/>
        <sub>dl09r</sub>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/tonybanters">
        <img src="https://unavatar.io/github/tonybanters" width="48" style="border-radius:50%"/><br/>
        <sub>tonybanters</sub>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/vinthara">
        <img src="https://unavatar.io/github/vinthara" width="48" style="border-radius:50%"/><br/>
        <sub>vinthara</sub>
      </a>
    </td>
    <td align="center">
      <a href="https://github.com/stepbrobd">
        <img src="https://unavatar.io/github/stepbrobd" width="48" style="border-radius:50%"/><br/>
        <sub>stepbrobd</sub>
      </a>
    </td>
  </tr>
</table>

Crypto donations accepted:

<table>
  <tr>
    <td valign="middle">
      <strong>Network:</strong> BEP20 (BSC)<br/>
      <strong>Address:</strong> <code>0xf9cda472f2556671d2504afc4c35340ec5615da1</code>
    </td>
    <td valign="middle">
      <img width="120" alt="sponsor QR" src="assets/crypto_sponserme_qrcode.png" />
    </td>
  </tr>
</table>

---

## Termux / Android

A port of [mango](https://github.com/mangowm/mango) for Android/Termux.
The compositor runs as a regular X11 application inside **Termux:X11**
(`termux-x11` plus the `com.termux.x11` app) and uses wlroots' native
`wlr_x11_backend`.

Termux:GUI is no longer used.

### Source changes

- `meson_options.txt` — the `termux` option (enabled by default).
- `meson.build` — in `termux` mode:
  - `libinput` and `wlr/backend/session.h` are not required;
  - stub headers from `termux-compat/` are included;
  - links against `libandroid-wordexp` (bionic has no `wordexp(3)`);
  - configs are installed to `$PREFIX/etc/mango`.
- `termux-compat/libinput.h`, `termux-compat/wlr/backend/libinput.h`,
  `termux-compat/wlr/backend/session.h`,
  `termux-compat/wlr/types/wlr_drm_lease_v1.h` — stubs for wlroots interfaces
  missing from the Termux build.
- `src/main.c`:
  - backend selection: `x11` (default), `wayland`, `headless`;
  - `WLR_BACKENDS=x11` is used by default on Termux;
  - `mango_renderer_create()`: uses the scenefx FX renderer when DRM/DMA-BUF
    (DRI3) is available; otherwise on Termux it tries Android system EGL +
    AHardwareBuffer (Adreno), and falls back to `pixman` on failure.
- `src/manage/monitor.c` — renderer recreation after a GPU reset goes through
  the same `mango_renderer_create()` and `mango_allocator_create()`.
- `mangonag/mangonag.c` — `memfd_create` via `syscall()` for API < 30.
- `termux/ahb.c`, `termux/ahb.h` — AHardwareBuffer allocator and buffers,
  Android system EGL/GLES, an EGLImage provider for scenefx, and handing the
  GPU buffer to X11 over SHM. This is how effects work without DRI3.
- `scenefx/` — bundled scenefx 0.5 sources with the Termux/AHardwareBuffer
  patch already applied.
- `termux-compat/scenefx-termux.patch` — scenefx patch: pixman fallback,
  support for an external EGLImage provider (AHardwareBuffer), working without
  `EGL_EXT_image_dma_buf_import` and `EGL_EXT_platform_base`.
- `build-termux.sh` — builds the bundled patched scenefx + mango, and private
  GPU copies of `mango`/`libwlroots`/`libscenefx` in
  `$PREFIX/lib/mango-termux`.
- `run-mango.sh` — starts Termux:X11 (if needed) and mango on X11. Installed as
  `$PREFIX/bin/mango-termux`.
- `termux/x11-check.c` — a small probe (`mango-x11-check`) that tests the X11
  connection with a real handshake rather than the presence of a socket file.

### Dependencies

```bash
pkg install clang pkg-config ninja patchelf git python-pip \
            wlroots libwayland libwayland-protocols libxkbcommon \
            libpixman libdrm libxcb libglvnd-dev mesa mesa-dev littlecms \
            vulkan-loader pcre2 pango cjson libandroid-wordexp
python -m pip install meson

# Termux:X11 server
pkg install x11-repo
pkg update
pkg install termux-x11-nightly
```

### Patched wlroots 0.20 (optional)

The port builds against wlroots 0.20. A pre-patched 0.20.2 tree with the official
Termux fixes (`shm_open`, Xwayland paths, Termux:GUI backend) is available at
<https://github.com/OceanSt0ne/wlroots-termux>. Install it before building mango
if you need those patches or want to replace the Termux package:

```bash
pkg install x11-repo
pkg install meson ninja clang pkg-config patch git \
  libwayland libwayland-protocols libdrm libxkbcommon libpixman \
  libglvnd-dev mesa-dev vulkan-loader-generic vulkan-headers glslang \
  libxcb xcb-util-renderutil xcb-util-wm xwayland littlecms termux-gui-c

git clone https://github.com/OceanSt0ne/wlroots-termux.git ~/Projects/wlroots-0.20
cd ~/Projects/wlroots-0.20
chmod 700 /data/data/com.termux/files/lib
meson setup build --prefix="$PREFIX" \
  -Dexamples=false -Dxwayland=enabled -Dsession=disabled \
  -Dbackends=x11,termuxgui -Drenderers=gles2,vulkan -Dwerror=false
ninja -C build
ninja -C build install
pkg-config --modversion wlroots-0.20   # 0.20.2
```

The Termux patches are already committed, so do not apply them again. After
installing, rebuild mango with `./build-termux.sh` so the private
`$PREFIX/lib/mango-termux/libwlroots-0.20.so` copy is refreshed. To roll back to
the Termux package: `pkg reinstall wlroots`.

`scenefx 0.5` is bundled in `scenefx/` and built from source (see below); it is
not available in the Termux repositories.

### Quick start

You need Android arm64, Termux, and the **Termux:X11** app
(`com.termux.x11`).

```bash
pkg install clang pkg-config ninja patchelf git python-pip \
  wlroots libwayland libwayland-protocols libxkbcommon libpixman \
  libdrm libxcb libglvnd-dev mesa mesa-dev littlecms vulkan-loader \
  pcre2 pango cjson libandroid-wordexp
python -m pip install meson

pkg install x11-repo
pkg update
pkg install termux-x11-nightly

# clone the port branch, for example:
# git clone -b termux-port <URL> ~/Projects/mango-termux
cd ~/Projects/mango-termux
./build-termux.sh
mango-termux
```

Effects are enabled automatically for a new config; if a config already
existed, enable them manually (see the "Effects" section). Launch
`mango-termux` specifically: the regular `mango` binary stays on the pixman
path.

### Build

Everything is automated. The script can be run from any directory, using an
absolute path, a relative path, or a symlink:

```bash
cd ~/Projects/mango-termux
./build-termux.sh
```

The script:

1. builds the bundled, pre-patched `scenefx` 0.5 from `scenefx/` (or
   `$SCENEFX_DIR`);
2. builds and installs scenefx and mango into `$PREFIX`;
3. creates private GPU copies in `$PREFIX/lib/mango-termux`, redirecting
   `libEGL`/`libGLESv2` to the Android system libraries with `patchelf`;
4. copies the config to `~/.config/mango` (enables `blur`, shadows, and
   rounded corners for a new config).

If `scenefx` is already located elsewhere:

```bash
SCENEFX_DIR=/path/to/scenefx ./build-termux.sh
```

When `$SCENEFX_DIR` points to an unpatched git checkout, the script applies
`termux-compat/scenefx-termux.patch` automatically.

The `-Dtermux=true` flag is already used by the script. The manual build below
produces a regular Mesa/pixman build; GPU effects require `./build-termux.sh`.

```bash
# scenefx (bundled, already patched)
cd ~/Projects/mango-termux/scenefx
chmod 700 /data/data/com.termux/files/lib
meson setup build --prefix="$PREFIX" -Dexamples=false -Dwerror=false
meson compile -C build && meson install -C build
chmod 000 /data/data/com.termux/files/lib

# mango
cd ~/Projects/mango-termux
chmod 700 /data/data/com.termux/files/lib
meson setup build --prefix="$PREFIX" -Dtermux=true -Dxwayland=disabled
meson compile -C build && meson install -C build
chmod 000 /data/data/com.termux/files/lib
```

Check:

```bash
mango -v
mango -p -c ~/.config/mango/config.conf
```

### Running

The **Termux:X11** app (`com.termux.x11`) must be installed. The
`termux-x11-nightly` package provides the server.

```bash
mango-termux
```

`mango-termux` is an installed copy of `run-mango.sh`, so it can be launched
from any directory and after any Termux restart.

The script:

- sets `XDG_RUNTIME_DIR` (if unset) to `$TMPDIR` and mode `700`;
- uses `DISPLAY=:0` (override with `MANGO_X11_DISPLAY`);
- checks that the X server on this display actually responds
  (`mango-x11-check`), not merely that a socket file exists;
- if the server does not respond, starts
  `termux-x11 "$DISPLAY" -ac -noreset`, waits for a connection, removes stale
  lock/socket files, and retries;
- sets `WLR_BACKENDS=x11`;
- launches `$PREFIX/lib/mango-termux/mango` (GPU effects), or the installed
  `mango`, `./build/mango`, or `$MANGO_BIN` if it is absent.

Useful options:

```bash
# verbose log
mango-termux -d

# another display
MANGO_X11_DISPLAY=:1 mango-termux

# custom config
mango-termux -c ~/.config/mango/config.conf

# startup command
mango-termux -s foot

# restart a running mango
mango-termux --restart
```

### Restarting after re-entering Termux

The script can be run repeatedly:

- if mango is still running (Termux has not killed the process),
  `mango-termux` finds its IPC socket `$XDG_RUNTIME_DIR/mango-*.sock`, checks it
  with `mmsg get version`, and does not start another instance;
- if mango was killed but Wayland sockets remain, `mango-termux` removes stale
  `wayland-*.lock`/sockets (a live compositor holds `flock`);
- if Termux:X11 was killed and a `.X0-lock`/socket remains, the script checks
  the connection, removes the dead lock, and starts the server again;
- to forcibly replace a running instance: `mango-termux --restart`.

#### Optional autostart when opening Termux

If you want mango to start automatically in every new interactive shell, add a
marker-file check to your shell config. Create the marker:

```bash
mkdir -p ~/.config/mango
touch ~/.config/mango/autostart
```

For bash (`~/.bashrc`):

```bash
if [[ $- == *i* && -f "$HOME/.config/mango/autostart" ]]; then
  nohup mango-termux >/dev/null 2>&1 &
fi
```

For fish (`~/.config/fish/config.fish`):

```fish
if status is-interactive; and test -f "$HOME/.config/mango/autostart"
    nohup mango-termux >/dev/null 2>&1 &
end
```

Remove autostart: `rm ~/.config/mango/autostart`.

If you launch `mango` directly, set the variables yourself:

```bash
export XDG_RUNTIME_DIR="$TMPDIR"
export DISPLAY=:0
export WLR_BACKENDS=x11
mango
```

### Configuration

Files are installed to `$PREFIX/etc/mango/`. Mango looks for the config in this
order:

1. `~/.config/mango/config.conf`
2. `~/.config/mango/config.toml`
3. `$PREFIX/etc/mango/config.conf`
4. `$PREFIX/etc/mango/config.toml`

Default keybindings (`config.conf`):

| Key combination | Action |
|---|---|
| `Super+M` | exit mango |
| `Alt+Return` | launch `foot` |
| `Alt+Space` | `rofi -show drun` |
| `Super+R` | reload config |
| `Alt+Q` | close window |
| `Super+Tab` | next window |
| `Alt+Tab` | jump-label switching |
| `Alt+F` | fullscreen |

Install `foot` and `rofi` separately (`pkg install foot rofi`).

### How it works

`wlr_x11_backend` creates a window inside the Termux:X11 X server and receives
keyboard, pointer, and touch events from it. Clients connect to mango over the
Wayland socket (`$XDG_RUNTIME_DIR/wayland-0`):

```bash
export XDG_RUNTIME_DIR="$TMPDIR"
export WAYLAND_DISPLAY=wayland-0
foot
```

Rendering:

- with working DRI3 (`wlr_backend_get_drm_fd() >= 0`), the scenefx FX renderer
  is used;
- in Termux:X11, `DRI3Open` does not provide a DRM fd, so `mango-termux`
  launches a private build that creates the scenefx FX renderer on **Android
  system EGL** (Adreno) and renders into **AHardwareBuffer**. The buffer is
  handed to the X11 server over SHM, accounting for the aligned stride;
- if Android system EGL/AHardwareBuffer is unavailable, `pixman` is enabled
  automatically and scenefx renders the scene without effects.

### Effects

Effects are enabled in `~/.config/mango/config.conf` (or `config.toml`):

```ini
blur=1
blur_layer=1
shadows=1
layer_shadows=1
border_radius=12
```

When launched via `mango-termux`, they run on the GPU (blur, shadows, rounded
corners, animations). To verify the GPU path is used:

```bash
MANGO_TERMUX_GPU=1 mango-termux --restart -d 2>&1 | grep -E 'AHB|FX renderer|pixman'
```

To force pixman (no effects, for diagnostics):

```bash
MANGO_TERMUX_GPU=0 mango-termux
```

Launching `$PREFIX/bin/mango` directly uses Termux Mesa and stays on the
pixman path; use `mango-termux` for effects.

### Limitations

- Termux has no DRM/libinput/session backends — that is how `wlroots-0.20` is
  built.
- Termux:X11 does not provide a DRI3 DRM fd. Effects work through Android
  system EGL + AHardwareBuffer instead of DRI3. This requires Android with a
  working `/system/lib64/libEGL.so` and AHardwareBuffer support; otherwise
  pixman is used.
- At very high resolutions, copying AHB to SHM for X11 can be a bottleneck.
- XWayland is disabled in this build (`-Dxwayland=disabled`); X11 applications
  will not launch directly.
- `chvt`/virtual terminal switching is unavailable.

### Diagnostics

- `Failed to open DRI3` / `Disabling DMA-BUF support` — normal for Termux:X11.
  `mango-termux` does not use DRI3: effects go through Android system EGL +
  AHardwareBuffer.
- `Termux: AHB/EGL renderer unavailable, falling back to pixman` — Android
  system EGL/AHardwareBuffer or the private libraries were not found. Rebuild
  with `./build-termux.sh` (requires `patchelf`) and launch `mango-termux`.
- `fatal error: 'gbm.h' file not found` — Termux's `mesa` package provides
  `gbm.pc`/`libgbm`, but the header is in `mesa-dev`. Install it and rerun:
  `pkg install mesa-dev && ./build-termux.sh`. No need to delete the build
  directory; the failed target is rebuilt.
- `X11 error: op 18:0, code 5` — harmless `ChangeProperty` errors when the X11
  backend starts.
- `Failed to connect to Termux:X11` — check `$TMPDIR/termux-x11.log`, launch
  the Termux:X11 app manually, and test the connection:
  `DISPLAY=:0 mango-x11-check; echo $?`.
- Black/empty screen — make sure the Termux:X11 app is open; launch with
  `run-mango.sh -d` and inspect the log.
- Slow — lower the Termux:X11 screen resolution or disable animations in
  `config.conf`.
- `couldn't create renderer` — verify scenefx was built with
  `scenefx-termux.patch` and installed into `$PREFIX`, and that `mango-termux`
  uses `$PREFIX/lib/mango-termux/mango`.

### Rebuild

```bash
cd ~/Projects/mango-termux
./build-termux.sh
```
