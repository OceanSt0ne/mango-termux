[English](README.md) | [Русский](README_ru.md)

---

<div align="center">
  <img src="assets/mango.svg" alt="Mango Logo" width="120"/>

  <h1>Mango Wayland Compositor v0.18.5</h1>

  <p>A fast, feature-rich Wayland compositor adapted for Android/Termux.</p>

</div>

---

> **Termux/Android port:** this repository is the Android/Termux port of [mango](https://github.com/mangowm/mango).
> It runs inside Termux:X11 without PRoot.
>
> **Optional Noctalia integration:** [English](TERMUX_NOCTALIA.md) | [Russian](TERMUX_NOCTALIA_ru.md).

---

## 1. Overview

### What this repository is

Mango is a fast, feature-rich Wayland compositor. This repository is the Termux/Android port, not a PRoot wrapper.

The compositor runs as a regular X11 client inside Termux:X11 (`termux-x11` plus the `com.termux.x11` app) and uses wlroots' `wlr_x11_backend`. Termux:GUI is no longer used.

Optional Noctalia/Arch proot integration is separate and not required.

### Architecture at a glance

- No DRM, libinput, session, systemd, or udev requirement.
- Default launcher path: Mesa Zink + Turnip (Freedreno Vulkan), rendering into CPU-mappable Android AHardwareBuffers, presented to Termux:X11 through SHM because Termux:X11 has no usable DRI3 DRM fd.
- Fallback: Android system EGL + AHardwareBuffer (Adreno), then pixman.
- Session clients and nested Xwayland use the private Mesa 27 native Freedreno/KGSL path where `$PREFIX/opt/mesa-kgsl` and `$PREFIX/opt/xwayland-kgsl` are installed.
- Configs live under `$PREFIX/etc/mango`; user configs in `~/.config/mango`.

### Known limitations

- No DRM/libinput/session backends and no `chvt`/VT switching.
- Termux:X11 lacks a DRI3 DRM fd, so the output path is AHB + SHM; the AHB→SHM copy, padded AHB stride, and explicit GPU synchronization can limit presentation at high resolution.
- Turnip/Zink adds Vulkan translation overhead; AHB can be faster on some workloads.
- Apps launched from an outer shell with `DISPLAY=:0` open in Termux:X11, not inside mango; launch them inside mango or through `mango-termux -s`.
- High `vkmark` FPS does not mean the X11 presentation path is free of copies or Present stalls.

## 2. Port Changes & Fixes

### Build system and Termux adaptation

- `meson_options.txt`: `termux` boolean option, default `true`; `xwayland` enabled.
- `meson.build` in Termux mode:
  - does not require libinput or `wlr/backend/session.h`;
  - adds the `termux-compat/` include directory with stub headers;
  - links `libandroid-wordexp` because bionic lacks `wordexp(3)`;
  - installs configs to `$PREFIX/etc/mango` and sets `SYSCONFDIR` under the prefix;
  - defines `TERMUX_BUILD`;
  - adds `termux/ahb.c` and `termux/zink.c`;
  - links `libandroid` and `libEGL`;
  - builds `mango-x11-check` with xcb;
  - installs `run-mango.sh` as `$PREFIX/bin/mango-termux` with executable mode.
- `termux-compat/libinput.h`, `termux-compat/wlr/backend/libinput.h`, `termux-compat/wlr/backend/session.h`, `termux-compat/wlr/types/wlr_drm_lease_v1.h`: compatibility stubs for wlroots interfaces absent from Termux.
- `mangonag/mangonag.c`: `memfd_create` through `syscall()` for Android API < 30.
- `build-termux.sh`:
  - works from any cwd/symlink; uses `PREFIX` default `/data/data/com.termux/files/usr` and `SCENEFX_DIR` override;
  - checks clang, pkg-config, meson, ninja, patchelf, git, wlroots 0.20, wayland, xkbcommon, pixman, libdrm, pango, cjson, xcb, EGL/GLES, GBM, lcms2, Vulkan, Xwayland, `libandroid-wordexp`, `mesa-dev`, Mesa Zink, Freedreno ICD;
  - works around Meson being unable to stat `/data/data/com.termux/files/lib` (mode 000) by temporarily `chmod 700` and restoring `000` on exit;
  - applies/reverts `termux-compat/scenefx-termux.patch` for an unpatched git scenefx tree;
  - builds scenefx and mango with `--prefix="$PREFIX"`, `--buildtype=release`, `-Doptimization=3`; scenefx also uses `-Dexamples=false -Dwerror=false`; mango uses `-Dtermux=true -Dxwayland=enabled`;
  - always reconfigures existing build directories so old debug/`-O0` configurations are replaced;
  - installs private GPU copies in `$PREFIX/lib/mango-termux`: `mango`, `libwlroots-0.20.so`, `libscenefx-0.5.so`;
  - patches private copies with `patchelf`: replace `libEGL.so.1` and `libGLESv2.so.2` with Android `/system/lib64` or `/system/lib` paths, set RPATH to the private directory plus `$PREFIX/lib`;
  - copies configs to `~/.config/mango` for a new install and enables `blur`, `blur_layer`, `shadows`, `layer_shadows`, and `border_radius=12` only for a new `config.conf`;
  - leaves existing configs untouched.
- `mango-session.target` may be installed, but the port does not require systemd, udev, libinput, DRM, or a login session.

### Backends and launcher

- `src/main.c` Termux backend creation:
  - `WLR_BACKENDS` supports `x11`, `wayland`, `headless`; x11 is the default when unset;
  - `tgui` is rejected with a message to use `WLR_BACKENDS=x11` and Termux:X11;
  - creates a wlroots multi-backend and outputs for the requested backends;
  - the X11 path pre-interns `_NET_WM_NAME`, `UTF8_STRING`, `_VARIABLE_REFRESH`, `WM_PROTOCOLS`, `WM_DELETE_WINDOW` on a throwaway X connection to avoid harmless `BadAtom`/`ChangeProperty` errors;
  - keeps a secondary headless backend available.
- `run-mango.sh` / installed `$PREFIX/bin/mango-termux`:
  - resolves its own path and `PREFIX`; uses `$PREFIX/opt/xwayland-kgsl/bin/Xwayland` when present unless `WLR_XWAYLAND` is set;
  - renderer precedence: `MANGO_TERMUX_RENDERER` first, then compatibility `MANGO_TERMUX_GPU` (`0` → pixman, `1`/`ahb` → ahb, `turnip`/`zink` → turnip), otherwise turnip;
  - Turnip mode exports private Mesa 27 variables (`LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, `GBM_BACKENDS_PATH`, `MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `GALLIUM_DRIVER=kgsl`) for session children and clears stale Vulkan ICD variables; `termux/zink.c` scopes Zink variables to mango's own renderer creation;
  - if `$PREFIX/opt/mesa-kgsl/lib` is absent, unsets the private Mesa/KGSL variables rather than leaking a stale override;
  - AHB mode selects `$PREFIX/lib/mango-termux/mango`, the binary patched to Android EGL/GLES;
  - pixman mode forces software rendering;
  - sets `XDG_RUNTIME_DIR` to `$TMPDIR` if unset and mode 700;
  - removes stale `wayland-*.lock`/sockets using `flock` when possible, otherwise PID checks;
  - reuses a live mango IPC socket `$XDG_RUNTIME_DIR/mango-*.sock` after checking with `mmsg get version`; `--restart` stops it and retries;
  - display defaults to `$DISPLAY` or `:0`; checks a real X11 handshake with `mango-x11-check`, not just a socket file;
  - starts `termux-x11 "$display" -ac -noreset` with Mesa/KGSL/Vulkan/EGL variables stripped via `env -u` so the X server chooses its own renderer stack;
  - strips `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, `GBM_BACKENDS_PATH`, `MESA_LOADER_DRIVER_OVERRIDE`, `GALLIUM_DRIVER`, `FD_KGSL_DMABUF`, `VK_DRIVER_FILES`, `VK_ICD_FILENAMES`, `EGL_PLATFORM`, `__EGL_VENDOR_LIBRARY_FILENAMES` from the Termux:X11 process;
  - handles stale `.X<n>-lock`/socket, waits for an already-starting server, retries once after cleanup;
  - sets `WLR_BACKENDS` (default `x11`);
  - selects `MANGO_BIN`, installed `mango`, or `./build/mango`;
  - unsets `LD_LIBRARY_PATH` for the private AHB binary so its absolute Android EGL/GLES NEEDED entries resolve outside the Termux namespace; RUNPATH is sufficient.
- `termux/x11-check.c`: a small xcb probe installed as `mango-x11-check`; exit 0 means a real X11 connection.

### Rendering: AHardwareBuffer and scenefx

- `termux/ahb.c`, `termux/ahb.h`:
  - declare the needed NDK `AHardwareBuffer` subset locally for older Termux API targets;
  - allocate AHB with CPU read/write and GPU sampled/framebuffer usage;
  - support BGRA/RGBA DRM formats;
  - expose AHB as EGLImage through `eglGetNativeClientBufferANDROID` + `eglCreateImageKHR`;
  - export AHB as one-plane DMA-BUF attributes for the Zink path;
  - provide CPU data-pointer access through `AHardwareBuffer_lock/unlock`;
  - present to X11 through SHM; because `xcb_shm_create_pixmap` requires stride == width × 4 and AHB pads the stride, report `stride / 4` as the SHM width; the X server crops the padding;
  - provide `termux_ahb_allocator_create()` and `termux_ahb_renderer_create()`.
- `scenefx/` is bundled scenefx 0.5 with the Termux patch already applied. `termux-compat/scenefx-termux.patch` adds:
  - `fx_renderer_create_with_egl()` for an existing EGL display/context;
  - external EGLImage provider and DMA-BUF provider hooks;
  - fallback when `EGL_EXT_image_dma_buf_import` / `EGL_EXT_platform_base` are unavailable;
  - SHM/DATA_PTR buffer capabilities when using the EGLImage provider;
  - GLES 3.0 core unpack support when the EXT name is not advertised (Adreno);
  - pixman/non-FX scene fallback: draw rectangles/textures without effects;
  - alpha-preserving optimized blur buffers;
  - damage-triggered refresh of optimized blur nodes;
  - AHB/offscreen buffers sampled as GPU textures via EGLImage/DMA-BUF instead of CPU-mapped pixels;
  - `glFinish()` after AHB-backed render targets because the X11 server consumes the buffer via mmap, not a GPU fence.
- `src/main.c` renderer/allocator selection:
  - if a DRM fd is available, use the normal scenefx FX renderer;
  - on Termux:X11 without a DRM fd, try Zink/Turnip, then Android EGL/AHB, then pixman;
  - when AHB or Zink is active, use the AHB allocator.
- `src/manage/monitor.c`: GPU reset renderer recreation goes through the same `mango_renderer_create()` and `mango_allocator_create()`.

### Rendering: Mesa Zink + Turnip

- `termux/zink.c`, `termux/zink.h`:
  - initializes an EGL display and ES2 context, requires `EGL_EXT_image_dma_buf_import`;
  - applies `VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json`, `MESA_LOADER_DRIVER_OVERRIDE=zink`, `GALLIUM_DRIVER=zink`, `EGL_PLATFORM=surfaceless` only while creating mango's renderer;
  - saves and restores `VK_ICD_FILENAMES`, `MESA_LOADER_DRIVER_OVERRIDE`, `GALLIUM_DRIVER`, `EGL_PLATFORM` so child GL/Vulkan clients use the native session stack;
  - imports AHB-backed buffers as DMA-BUF EGLImages and creates the FX renderer with `fx_renderer_create_with_egl()`;
  - sets both EGLImage and DMA-BUF providers for scenefx.
- The private Mesa 27 tree at `$PREFIX/opt/mesa-kgsl` supplies Zink and native Freedreno/KGSL. The launcher exports native KGSL variables to session children while Zink is scoped to mango itself, avoiding broken GTK4/Ghostty rendering from a global Zink override.

### Session GPU and Xwayland on KGSL

- The session and child clients use private Mesa 27 native Freedreno/KGSL (`MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `GALLIUM_DRIVER=kgsl`) and report `FD735`.
- Stock Termux Xwayland is built with `-Dglamor=false`, so nested X11 clients fall back to llvmpipe. The port uses `$PREFIX/opt/xwayland-kgsl/bin/Xwayland` when installed:
  - glamor/DRI3 over `/dev/kgsl-3d0` without `/dev/dri` or `wl_drm`;
  - the Xwayland server starts with private Mesa 27 Zink/Turnip (`MESA_LOADER_DRIVER_OVERRIDE=zink`, `GALLIUM_DRIVER=zink`, `FD_KGSL_DMABUF=1`);
  - X11 clients inherit native Mesa 27 KGSL, not global Zink;
  - KGSL buffers are exported as `DRM_FORMAT_MOD_LINEAR` so mango can import them instead of showing black windows;
  - stock server backup is `$PREFIX/bin/Xwayland.stock`; wrapper is `$PREFIX/bin/Xwayland`; override with `WLR_XWAYLAND`.
- Verify from a terminal inside mango:

```sh
DISPLAY=:1 glxinfo -B | grep -E 'Accelerated|OpenGL renderer'
# Accelerated: yes
# OpenGL renderer string: FD735
```

- One-off Zink diagnostic:

```sh
MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink glxinfo -B
# OpenGL renderer string: zink Vulkan 1.4(Turnip Adreno (TM) 735 ...)
```

### Performance: release builds and frame-done backpressure

- `build-termux.sh` builds both `scenefx` and `mango` as Meson release with `-Doptimization=3`; existing build directories are reconfigured to remove stale `buildtype=debug` / `optimization=0` settings. Helper binaries keep their own `-O2` flags.
- `src/manage/monitor.c`:
  - stores the boolean result of `mango_scene_output_commit()`;
  - if the commit fails or is skipped (typically the X11 swapchain is full while Present is pending), returns without sending `wlr_scene_output_send_frame_done()` and without re-arming the frame loop;
  - the resize skip path also does not send `frame_done`;
  - the next backend Present/Idle event drives the retry once the swapchain has room.
- This is backpressure, not a refresh-rate limiter. Clients must not receive `frame_done` for a frame that was not accepted by the output.
- There is no artificial 60 Hz cap. `MANGO_X11_FPS` and `-fakescreenfps` were removed and are not supported.
- The main remaining presentation cost is the AHB→SHM/X11 Present copy: no usable DRI3 on the Termux:X11 output, padded AHB width, rejected X11 flips, and `glFinish()` on the AHB path.
- `run-mango.sh` starts Termux:X11 with its own renderer environment; private Mesa/KGSL variables are not leaked into the X server.

### Config migration

- `termux-compat/fix-mango-config.sh` migrates old mango `.conf` key names to 0.18 names.
- Supports `-n/--dry-run`, `--no-validate`, `-h/--help`, a positional config directory, or `--config-dir`.
- Defaults to `${XDG_CONFIG_HOME:-$HOME/.config}/mango`.
- Creates a timestamped `backup-mango-config.XXXXXX` directory before edits.
- Uses `mango -p -c .../config.conf` for validation unless disabled.
- Safe to run again; if no old keys are found it exits successfully.
- Full rename table:

| Old key | Current key |
|---|---|
| `middle_button_emulation` | `trackpad_middle_button_emulation` |
| `default_mfact` | `default_master_factor` |
| `default_nmaster` | `default_master_count` |
| `smartgaps` | `smart_gaps` |
| `dwindle_hsplit` | `dwindle_horizontal_split` |
| `dwindle_vsplit` | `dwindle_vertical_split` |
| `overviewgappi` | `overview_gap_inner` |
| `overviewgappo` | `overview_gap_outer` |
| `idleinhibit_ignore_visible` | `idle_inhibit_ignore_visible` |
| `sloppyfocus` | `sloppy_focus` |
| `warpcursor` | `warp_cursor` |
| `tagrule` | `tag_rule` |
| `shadowscolor` | `shadows_color` |
| `gappih` | `gap_inner_horizontal` |
| `gappiv` | `gap_inner_vertical` |
| `gappoh` | `gap_outer_horizontal` |
| `gappov` | `gap_outer_vertical` |
| `borderpx` | `border_px` |
| `rootcolor` | `root_color` |
| `bordercolor` | `border_color` |
| `dropcolor` | `drop_color` |
| `splitcolor` | `split_color` |
| `focuscolor` | `focus_color` |
| `maximizescreencolor` | `maximized_screen_color` |
| `urgentcolor` | `urgent_color` |
| `scratchpadcolor` | `scratchpad_color` |
| `globalcolor` | `global_color` |
| `overlaycolor` | `overlay_color` |

- Removed options `ov_tab_mode` and `ov_no_resize` are commented out, not deleted.
- The script prints the backup path and reminds the user to reload with `Super+R` or restart.

### Benchmark fixes

- `termux-compat/install-benchmark-fixes.sh`:
  - requires `patchelf` and `readelf`/binutils;
  - backs up native `glmark2`/`glmark2-es2` as `.orig` and replaces `libjpeg.so` with `libjpeg.so.8` when needed;
  - installs `$PREFIX/glibc/bin/glmark2` and `glmark2-es2` wrappers that run the native Termux binaries on `$PREFIX/opt/mesa-kgsl` with native KGSL variables;
  - backs up existing glibc wrappers as `.glibc`;
  - for `vkmark`, verifies Arch Turnip contains `/dev/kgsl-3d0` and Arch `libassimp.so.6` exists;
  - copies Arch `libassimp`, `libvulkan_freedreno`, Wayland, xcb-keysyms, display-info, SPIRV-Tools, and udev libraries into `$PREFIX/opt/vkmark-kgsl/lib`;
  - creates `$PREFIX/opt/vkmark-kgsl/freedreno_icd.json` pointing at the copied Turnip;
  - installs the `$PREFIX/glibc/bin/vkmark` wrapper and `vkmark.real`, with `VK_DRIVER_FILES`/`VK_ICD_FILENAMES` set to that JSON;
  - patches `vkmark.real` from `libassimp.so.5` to `libassimp.so.6` when needed;
  - patches `$PREFIX/opt/glibc-runner/glibc-runner.sh` to clear bionic Mesa/KGSL variables before entering the glibc loader; backup is `.bak`.
- `termux-compat/build-arch-turnip.sh`:
  - runs inside the Arch Linux ARM proot (`PROOT_DISTRO_NAME`, default `archlinuxarm`);
  - installs Mesa build dependencies with pacman;
  - downloads the matching Mesa source tarball from `archive.mesa3d.org`;
  - configures only the Freedreno Vulkan driver with `-Dfreedreno-kmds=msm,kgsl`, no Gallium/EGL/GLX/LLVM;
  - builds `libvulkan_freedreno.so`, verifies the `/dev/kgsl-3d0` string, backs up the old Arch driver as `.kgsl-old`, installs the new driver and ICD manifest;
  - is optional and only needed for Arch/proot tooling; the host Termux session does not require PRoot.
- Benchmark commands:

```bash
pkg install glmark2 libjpeg-turbo patchelf binutils
./termux-compat/build-arch-turnip.sh   # only if Arch Turnip lacks KGSL
./termux-compat/install-benchmark-fixes.sh
glmark2
glmark2-es2
grun --shell vkmark
```

### Helper scripts and documentation

- `termux-compat/fix-mango-config.sh`, `termux-compat/install-benchmark-fixes.sh`, `termux-compat/build-arch-turnip.sh`.
- `termux-compat/scenefx-termux.patch`.
- `termux/x11-check.c`.
- `TERMUX_NOCTALIA.md` and `TERMUX_NOCTALIA_ru.md`: optional Arch proot integration guide, native KGSL setup, Noctalia launch script, and environment isolation. Not part of the required host port.

## 3. Requirements & Build

### Prerequisites

- Android arm64, Termux, the Termux:X11 app (`com.termux.x11`); `termux-x11-nightly` package.
- No PRoot, systemd, udev, libinput, DRM session, or virtual terminal required.
- `$PREFIX` is `/data/data/com.termux/files/usr` by default.
- Optional for the best GPU path: private Mesa 27 at `$PREFIX/opt/mesa-kgsl`, patched Xwayland at `$PREFIX/opt/xwayland-kgsl`. If absent, the launcher falls back to the host Mesa/Xwayland path.

### Termux packages

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
```

- `scenefx 0.5` is bundled in `scenefx/` and is not available from Termux packages.

### Optional patched wlroots 0.20

- The port builds against wlroots 0.20. A pre-patched 0.20.2 tree with Termux fixes (`shm_open`, Xwayland paths, Termux:GUI backend) is available at `https://github.com/OceanSt0ne/wlroots-termux`.
- Install it only if those patches are needed or the Termux package must be replaced.
- The patches are already present in that tree; do not reapply them.
- After installing, rerun `./build-termux.sh` so the private `$PREFIX/lib/mango-termux/libwlroots-0.20.so` copy is refreshed.
- Roll back with `pkg reinstall wlroots`.

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

### Automated build

```bash
cd ~/Projects/mango-termux
./build-termux.sh
```

- The script can be run from any directory, with absolute/relative paths or through symlinks.
- `SCENEFX_DIR=/path/to/scenefx ./build-termux.sh` uses an external scenefx tree; an unpatched git checkout gets the patch automatically.
- The script uses release `-O3`, installs `mango`, `mmsg`, `mangonag`, `mango-x11-check`, and `mango-termux`.
- It creates private GPU copies in `$PREFIX/lib/mango-termux`, patches Android EGL/GLES references, and prepares `~/.config/mango` for a new install.
- The installed `$PREFIX/bin/mango` is the normal Mesa/Turnip-linked build; `$PREFIX/lib/mango-termux/mango` is the private Android EGL/AHardwareBuffer build.

### Manual build

- The script is recommended because it also creates the private GPU binary and launcher.
- Manual commands use the same release flags:

```bash
# scenefx (bundled, patched)
cd ~/Projects/mango-termux/scenefx
chmod 700 /data/data/com.termux/files/lib
meson setup build --prefix="$PREFIX" -Dexamples=false -Dwerror=false \
  --buildtype=release -Doptimization=3
meson compile -C build && meson install -C build
chmod 000 /data/data/com.termux/files/lib

# mango
cd ~/Projects/mango-termux
chmod 700 /data/data/com.termux/files/lib
meson setup build --prefix="$PREFIX" -Dtermux=true -Dxwayland=enabled \
  --buildtype=release -Doptimization=3
meson compile -C build && meson install -C build
chmod 000 /data/data/com.termux/files/lib
```

- Manual build does not create `$PREFIX/lib/mango-termux/mango`; use `./build-termux.sh` for the AHB/private GPU path.

### Verify installation

```bash
mango -v
mango -p -c ~/.config/mango/config.conf
test -x "$PREFIX/bin/mango-termux" && echo launcher-ok
test -x "$PREFIX/lib/mango-termux/mango" && echo private-gpu-ok
```

## 4. Usage & Configuration

### Quick start

- Open the Termux:X11 app, then:

```bash
mango-termux
```

- New configs get effects enabled automatically. Existing configs are not overwritten; enable effects manually if needed.
- Launch `mango-termux`, not the bare `mango` binary, when the renderer environment is needed.

### Launcher behavior

- Uses `XDG_RUNTIME_DIR` or `$TMPDIR`; display defaults to `:0` or `MANGO_X11_DISPLAY`.
- Reuses a live mango IPC socket; `--restart` replaces it.
- Cleans stale Wayland locks/sockets using `flock`/PID checks.
- Tests X11 with `mango-x11-check`; starts Termux:X11 if needed; removes stale `.X<n>-lock`/socket and retries once.
- Starts Termux:X11 with `-ac -noreset` and a clean renderer environment.
- Sets `WLR_BACKENDS=x11` by default.
- Selects the renderer and binary as described above.
- Exports nested Xwayland `DISPLAY` to children so X11 apps launched inside mango stay inside the nested session.
- Unsets `LD_LIBRARY_PATH` before exec of the private AHB binary.

### Environment variables

| Variable | Meaning |
|---|---|
| `MANGO_BACKEND` | `x11` (default), `wayland`, or `headless`. |
| `WLR_BACKENDS` | Backend list passed to wlroots; default `x11`. |
| `MANGO_X11_DISPLAY` | X display for Termux:X11; default `$DISPLAY` or `:0`. |
| `MANGO_BIN` | Explicit mango binary path. |
| `MANGO_TERMUX_RENDERER` | `turnip` (default), `ahb`, or `pixman`. |
| `MANGO_TERMUX_GPU` | Compatibility selector: `0` = pixman, `1`/`ahb` = ahb, `turnip`/`zink` = turnip. |
| `MANGO_RESTART` | `1` stops a running instance before starting. |
| `WLR_XWAYLAND` | Override the Xwayland server path. |
| `XDG_RUNTIME_DIR` | Wayland/IPC runtime directory; defaults to `$TMPDIR`. |
| `PREFIX` | Termux prefix; default `/data/data/com.termux/files/usr`. |
| `SCENEFX_DIR` | External scenefx source tree for the build. |
| `PROOT_DISTRO_NAME` | Arch proot container for optional Turnip/benchmark scripts. |
| `JOBS`, `MESA_BUILD_DIR` | Arch Turnip build parallelism and work directory. |
| `NOCTALIA_GPU` | Optional Arch Noctalia GPU mode; `kgsl` default, `0` = llvmpipe, `zink` legacy. |

### Examples

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

# software rendering
MANGO_TERMUX_RENDERER=pixman mango-termux
```

### Restart and autostart

- The launcher is safe to run again after reopening Termux.
- If mango is still alive, it finds `$XDG_RUNTIME_DIR/mango-*.sock`, validates it with `mmsg get version`, and does not start a second instance.
- If mango was killed, stale `wayland-*.lock`/sockets are removed; a live compositor holds `flock`.
- If Termux:X11 was killed, stale `.X0-lock`/socket is removed and the server is restarted.
- Optional autostart: create `~/.config/mango/autostart`, then add a marker check to the shell config.

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

Remove autostart with `rm ~/.config/mango/autostart`.

### Configuration files and migration

- Installed defaults: `$PREFIX/etc/mango/config.conf` and `config.toml`.
- Search order:
  1. `~/.config/mango/config.conf`
  2. `~/.config/mango/config.toml`
  3. `$PREFIX/etc/mango/config.conf`
  4. `$PREFIX/etc/mango/config.toml`
- If mango shows an error plaque after an upgrade, migrate old key names:

```bash
./termux-compat/fix-mango-config.sh
mango -p -c ~/.config/mango/config.conf
```

- The migration script creates a timestamped backup, comments out removed options, and is safe to rerun.
- Reload with `Super+R` or restart mango after migration.

### Effects

```ini
blur=1
blur_layer=1
shadows=1
layer_shadows=1
border_radius=12
```

- Effects run on the GPU when launched through `mango-termux`.
- Verify the Turnip path:

```bash
MANGO_TERMUX_RENDERER=turnip mango-termux --restart -d 2>&1 | \
  grep -E 'Zink|Turnip|AHB|FX renderer|pixman'
```

- Force AHB: `MANGO_TERMUX_RENDERER=ahb mango-termux`.
- Force pixman: `MANGO_TERMUX_RENDERER=pixman mango-termux`.
- Direct `$PREFIX/bin/mango` does not set the renderer environment; use `mango-termux` or set variables explicitly.

### Keybindings

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

- Install `foot` and `rofi` separately: `pkg install foot rofi`.

### Nested Xwayland and child environment

- `wlr_x11_backend` creates a window in Termux:X11 and receives keyboard, pointer, and touch events.
- Clients connect to mango over `$XDG_RUNTIME_DIR/wayland-0`:

```bash
export XDG_RUNTIME_DIR="$TMPDIR"
export WAYLAND_DISPLAY=wayland-0
foot
```

- With working DRI3, the normal scenefx FX renderer is used.
- On Termux:X11, the output has no DRI3 DRM fd. Mango renders into AHB and presents over SHM.
- Turnip is the default via `mango-termux`; Zink/Vulkan variables are scoped to mango's renderer creation.
- Child GL clients use private Mesa 27 native Freedreno/KGSL (`FD735`), not global Zink.
- Nested Xwayland gives X11 clients DRI3 and native KGSL when the patched server is installed.
- Apps launched from a shell with the outer `DISPLAY=:0` still open outside mango; launch them inside mango or with `mango-termux -s`.

### Benchmarks

- Install and run:

```bash
pkg install glmark2 libjpeg-turbo patchelf binutils
./termux-compat/build-arch-turnip.sh   # only if Arch Turnip lacks KGSL
./termux-compat/install-benchmark-fixes.sh
glmark2
glmark2-es2
grun --shell vkmark
```

- The installer fixes native glmark2 `libjpeg`, installs KGSL Turnip `vkmark` wrappers, and isolates `glibc-runner` from bionic Mesa/KGSL variables.
- `vkmark` may report very high FPS; see the troubleshooting section.

### Optional Noctalia integration

- Noctalia inside Arch proot is optional and not required for mango-termux.
- Guides: `TERMUX_NOCTALIA.md` / `TERMUX_NOCTALIA_ru.md`.
- `~/.config/mango/start-noctalia.sh` clears host Mesa/Vulkan/library variables before entering proot, so Arch uses its own Mesa 27 native KGSL (`renderer="FD735"`).
- `NOCTALIA_GPU=kgsl` is the default; `NOCTALIA_GPU=0` forces llvmpipe; `NOCTALIA_GPU=zink` is legacy.
- `MANGO_INSTANCE_SIGNATURE` makes Noctalia use mango's native `mango-ipc` workspace backend.
- The host port itself does not use PRoot.

## 5. Troubleshooting

### Renderer diagnostics: Turnip/KGSL vs llvmpipe

- `FD735` means native Freedreno/KGSL for the session or X11 clients.
- `zink Vulkan ... Turnip ...` means Zink/Turnip; expected for mango's own renderer or explicit diagnostics.
- `llvmpipe` means software fallback.
- Check X11 client acceleration from inside mango:

```sh
DISPLAY=:1 glxinfo -B | grep -E 'Accelerated|OpenGL renderer'
```

- Check the Freedreno Vulkan ICD:

```sh
VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json \
  vulkaninfo --summary
```

- Check the compositor renderer:

```sh
MANGO_TERMUX_RENDERER=turnip mango-termux --restart -d 2>&1 | \
  grep -E 'Zink|Turnip|AHB|FX renderer|pixman'
```

- `Termux: Zink/Turnip renderer unavailable`: install `mesa-vulkan-icd-freedreno`, verify the ICD above, and expect fallback to AHB or pixman.
- `Termux: AHB/EGL renderer unavailable, falling back to pixman`: rebuild with `./build-termux.sh` and make sure `patchelf` is installed and the private binary exists.
- `Failed to open DRI3` / `Disabling DMA-BUF support`: normal for the Termux:X11 output; the port uses AHB + SHM.

### FPS measurements and vkmark

- `vkmark`/mailbox/immediate results can be in the thousands of FPS. This measures GPU submission throughput, not the Termux:X11 display refresh rate.
- There is no artificial 60 Hz cap. `MANGO_X11_FPS` and `-fakescreenfps` are not supported.
- High FPS does not prove the presentation path is smooth: the AHB→SHM copy, padded stride, Present stalls, and `glFinish()` can limit visible frame pacing.
- Judge smoothness visually in Termux:X11 and compare `glmark2`, `vkmark`, and interactive behavior separately.
- For diagnosis, use `mango-termux -d` and inspect renderer/commit/Present messages.

### Wayland and X11 sockets

- Wayland socket: `$XDG_RUNTIME_DIR/wayland-0` (normally `$TMPDIR/wayland-0`).
- Mango IPC socket: `$XDG_RUNTIME_DIR/mango-*.sock`; validate with `mmsg get version`.
- X11 lock/socket: `$TMPDIR/.X0-lock`, `$TMPDIR/.X11-unix/X0`.
- Test a real X11 handshake:

```bash
DISPLAY=:0 mango-x11-check; echo $?
```

- Termux:X11 log: `$TMPDIR/termux-x11.log`.
- The launcher removes stale locks only after confirming the server does not respond; do not delete a live server's socket manually.

### Common errors

- `fatal error: 'gbm.h' file not found`: Termux `mesa` provides `gbm.pc`/`libgbm`, but the header is in `mesa-dev`. Run `pkg install mesa-dev && ./build-termux.sh`; no need to delete the build directory.
- `X11 error: op 18:0, code 5`: harmless `ChangeProperty`/atom error during X11 backend startup; the compositor pre-interns the relevant atoms.
- `Failed to connect to Termux:X11`: open the Termux:X11 app, inspect `$TMPDIR/termux-x11.log`, and run `DISPLAY=:0 mango-x11-check; echo $?`.
- X11 apps open on the outer Termux:X11 desktop: they inherited `DISPLAY=:0`. Start them from a terminal inside mango or use `mango-termux -s <app>`; rebuild with the current script so Xwayland is enabled for existing build dirs.
- Black/empty screen: make sure the Termux:X11 app is open; launch `mango-termux -d` and inspect the log.
- Slow rendering: lower the Termux:X11 resolution, disable animations/effects in `config.conf`, or try `MANGO_TERMUX_RENDERER=ahb` / `pixman` for comparison.
- `couldn't create renderer`: verify scenefx was built with `scenefx-termux.patch`, installed under `$PREFIX`, and that the launcher uses the expected binary.
- No GPU effects: check that the config enables effects, that `$PREFIX/opt/mesa-kgsl` exists for the Turnip path, and that `mesa-vulkan-icd-freedreno` is installed.
- `vkmark` fails with assimp/Vulkan errors: run `termux-compat/install-benchmark-fixes.sh`; for Arch Turnip KGSL, run `termux-compat/build-arch-turnip.sh`.
- `glibc-runner` picks up bionic Mesa: rerun the benchmark installer to patch `glibc-runner.sh`, or remove the bionic variables from the environment.

### Rebuild

```bash
cd ~/Projects/mango-termux
./build-termux.sh
```

- The script reconfigures existing scenefx and mango build directories as release `-O3` and refreshes installed binaries and private GPU copies.
- Restart the session after rebuilding: `mango-termux --restart`.
