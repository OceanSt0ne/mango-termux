**English** | [Russian](README_ru.md)

<div align="center">
  <img src="assets/mango.svg" alt="Mango Logo" width="120"/>

  <h1>Mango Wayland Compositor v0.18.4</h1>

  <p>A fast, feature-rich Wayland compositor.</p>

</div>

---

https://github.com/user-attachments/assets/bb83004a-0563-4b48-ad89-6461a9b78b1f

https://github.com/user-attachments/assets/be85e13f-7798-456d-957e-f8931687392e

> **Termux/Android port:** mango runs inside Termux:X11 with hardware effects
> (blur, shadows, rounded corners) via Android EGL + AHardwareBuffer. See
> [Termux / Android](#termux--android) below for build and usage instructions.

> See all layouts in action at [mangowm.github.io](https://mangowm.github.io/)

> **Noctalia integration guide:** [English](TERMUX_NOCTALIA.md) | [Russian](TERMUX_NOCTALIA_ru.md)

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
- `termux/zink.c`, `termux/zink.h` — Mesa Zink + Turnip renderer. It renders
  into the same AHardwareBuffers, imported as DMA-BUF EGLImages, so effects use
  the Adreno GPU through the open Freedreno Vulkan driver instead of the
  proprietary Android EGL driver.
- `scenefx/` — bundled scenefx 0.5 sources with the Termux/AHardwareBuffer
  patch already applied.
- `termux-compat/scenefx-termux.patch` — scenefx patch: pixman fallback,
  support for an external EGLImage provider (AHardwareBuffer), working without
  `EGL_EXT_image_dma_buf_import` and `EGL_EXT_platform_base`.
- [`termux-compat/fix-mango-config.sh`](termux-compat/fix-mango-config.sh) —
  migrates older `~/.config/mango/*.conf` key names to the current mango 0.18
  names, comments out removed options, and validates the result with `mango -p`.
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
            libpixman libdrm libxcb xcb-util-wm xcb-util-renderutil \
            xwayland libglvnd-dev mesa mesa-dev \
            mesa-vulkan-icd-freedreno littlecms vulkan-loader \
            pcre2 pango cjson libandroid-wordexp
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
  libdrm libxcb xcb-util-wm xcb-util-renderutil xwayland \
  libglvnd-dev mesa mesa-dev mesa-vulkan-icd-freedreno \
  littlecms vulkan-loader pcre2 pango cjson libandroid-wordexp
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

The installed `$PREFIX/bin/mango` is the Mesa/Turnip build; the private
`$PREFIX/lib/mango-termux/mango` is the Android EGL/AHardwareBuffer build.

If `scenefx` is already located elsewhere:

```bash
SCENEFX_DIR=/path/to/scenefx ./build-termux.sh
```

When `$SCENEFX_DIR` points to an unpatched git checkout, the script applies
`termux-compat/scenefx-termux.patch` automatically.

The `-Dtermux=true` flag is already used by the script. The manual build below
produces the Mesa/Turnip build; the Android EGL/AHardwareBuffer path also needs
the private binary created by `./build-termux.sh`.

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
meson setup build --prefix="$PREFIX" -Dtermux=true -Dxwayland=enabled
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
- selects the renderer: `MANGO_TERMUX_RENDERER=turnip` (default) uses Mesa
  Zink + Turnip, `ahb` uses Android EGL/AHardwareBuffer, and `pixman` disables
  GPU rendering;
- lets mango start Xwayland and export its own `DISPLAY` to child processes, so
  X11 applications opened from mango stay inside the nested session;
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

# Android EGL/AHardwareBuffer instead of Turnip
MANGO_TERMUX_RENDERER=ahb mango-termux

# software rendering (no GPU effects)
MANGO_TERMUX_RENDERER=pixman mango-termux
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

If mango shows an error plaque after an upgrade, migrate the old `.conf` key
names with [`termux-compat/fix-mango-config.sh`](termux-compat/fix-mango-config.sh):

```bash
./termux-compat/fix-mango-config.sh
mango -p -c ~/.config/mango/config.conf
```

The script creates a timestamped backup in `~/.config/mango/`, comments out
options removed in the current release, and is safe to run again.

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
- in Termux:X11, `DRI3Open` does not provide a DRM fd. By default
  `mango-termux` creates the scenefx FX renderer on **Mesa Zink + Turnip**
  (Freedreno Vulkan) and renders into **AHardwareBuffers** imported as DMA-BUF
  EGLImages. `MANGO_TERMUX_RENDERER=ahb` uses the **Android system EGL**
  (Adreno) driver instead;
- the buffer is handed to the X11 server over SHM, accounting for the aligned
  stride;
- Mesa/Vulkan variables are scoped to mango's own renderer creation, so child
  GL clients use the private Mesa 27 build with native Freedreno/KGSL
  (`FD735`). With the patched Xwayland, X11 clients get DRI3 and use the same
  native KGSL driver instead of llvmpipe; see
  [Xwayland on KGSL](#xwayland-on-kgsl). Noctalia inside the Arch proot uses
  Mesa 27 with native Freedreno/KGSL (`renderer="FD735"`) by default; see the
  [Noctalia guide](TERMUX_NOCTALIA.md). `NOCTALIA_GPU=0` keeps the llvmpipe
  fallback.
- AHB/offscreen buffers are sampled through their EGLImage/DMA-BUF handles
  instead of CPU-mapped pixels, so scenefx blur reads the GPU-rendered scene.
  Optimized blur is refreshed whenever a blur region is damaged, avoiding black
  or stale backgrounds without forcing a full redraw every frame;
- if GPU rendering is unavailable, `pixman` is enabled automatically and
  scenefx renders the scene without effects.

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
corners, animations). To verify the Turnip path is used:

```bash
MANGO_TERMUX_RENDERER=turnip mango-termux --restart -d 2>&1 | \
  grep -E 'Zink|Turnip|AHB|FX renderer|pixman'
```

To use the Android EGL/AHardwareBuffer path instead:

```bash
MANGO_TERMUX_RENDERER=ahb mango-termux
```

To force pixman (no effects, for diagnostics):

```bash
MANGO_TERMUX_RENDERER=pixman mango-termux
```

Launching `$PREFIX/bin/mango` directly does not set the renderer environment;
use `mango-termux`, or set `MANGO_TERMUX_RENDERER=turnip` explicitly.

### Limitations

- Termux has no DRM/libinput/session backends — that is how `wlroots-0.20` is
  built.
- Termux:X11 does not provide a DRI3 DRM fd. Effects work through
  AHardwareBuffer plus either Mesa Zink + Turnip or Android system EGL. The AHB
  path requires a working `/system/lib64/libEGL.so`; the Turnip path requires
  `mesa-vulkan-icd-freedreno`. Otherwise pixman is used.
- Turnip/Zink adds a Vulkan translation layer; on some workloads the Android
  EGL/AHardwareBuffer path may be faster.
- At very high resolutions, copying AHB to SHM for X11 can be a bottleneck.
- XWayland is enabled. X11 apps started from mango use its nested Xwayland
  display and are managed by the compositor; apps launched from a shell with the
  outer `DISPLAY` (`:0`) still open directly in Termux:X11.
- `chvt`/virtual terminal switching is unavailable.

### Xwayland on KGSL

Termux's stock Xwayland is built with `-Dglamor=false`, so X11 clients inside
mango have no DRI3/GLX acceleration and fall back to llvmpipe. `run-mango.sh`
automatically uses a patched server when it exists at
`$PREFIX/opt/xwayland-kgsl/bin/Xwayland`:

- glamor/DRI3 are enabled on `/dev/kgsl-3d0` even without `/dev/dri` or
  `wl_drm`;
- the wrapper starts the Xwayland server with the private Mesa 27 build in
  `$PREFIX/opt/mesa-kgsl` (`MESA_LOADER_DRIVER_OVERRIDE=zink`,
  `GALLIUM_DRIVER=zink`, `FD_KGSL_DMABUF=1`);
- X11 clients inherit the session's native Mesa 27 path
  (`MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `GALLIUM_DRIVER=kgsl`), so they render
  through Freedreno/KGSL directly; a global Zink override is intentionally not
  exported because GTK4/Ghostty renders incorrectly with it;
- linear KGSL buffers are exported as `DRM_FORMAT_MOD_LINEAR`, so the
  compositor can import them instead of showing black windows.

Verify it from a terminal inside mango:

```sh
DISPLAY=:1 glxinfo -B | grep -E 'Accelerated|OpenGL renderer'
# Accelerated: yes
# OpenGL renderer string: FD735
```

For a Zink/Turnip result for a single diagnostic command, use:

```sh
MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink glxinfo -B
# OpenGL renderer string: zink Vulkan 1.4(Turnip Adreno (TM) 735 ...)
```

Override the path with `WLR_XWAYLAND=/path/to/Xwayland` if needed.

### Diagnostics

- `Failed to open DRI3` / `Disabling DMA-BUF support` — normal for Termux:X11.
  `mango-termux` does not use DRI3: effects go through Android system EGL +
  AHardwareBuffer.
- `OpenGL renderer string: FD735` — native Freedreno/KGSL is active for the
  session and X11 clients.
- `OpenGL renderer string: zink Vulkan ... Turnip ...` — Zink/Turnip is active;
  this is expected for mango's own renderer or when explicitly requested for a
  diagnostic command.
- `Termux: Zink/Turnip renderer unavailable` — check the Freedreno ICD:
  `VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json vulkaninfo --summary`
  and make sure `mesa-vulkan-icd-freedreno` is installed. mango then falls back
  to AHB or pixman.
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
- X11 apps open on the outer Termux:X11 desktop instead of inside mango — they
  inherited the outer `DISPLAY` (`:0`). Start them from a terminal opened inside
  mango (it exports its nested Xwayland display), or launch via
  `mango-termux -s <app>`. Rebuild with the current `./build-termux.sh`, which
  enables Xwayland for existing build directories too.
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
