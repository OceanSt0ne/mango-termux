**English** | [Русский](TERMUX_NOCTALIA_ru.md)

# Noctalia in Termux + mango (Arch Linux ARM proot)

Tested stack:

```text
Android
└── Termux
    └── Termux:X11 (:0)
        └── mango-termux (X11 backend, native Termux binary)
            └── Arch Linux ARM proot
                └── Noctalia 5.4.1
```

Noctalia runs inside proot but connects to mango's Wayland socket. Thanks to
`MANGO_INSTANCE_SIGNATURE`, it uses mango's native backend:
`workspace backend=mango-ipc`, not just the generic `ext-workspace`.

Tested on:

- Termux / Android 14, aarch64
- Termux:X11 1.03.01
- proot-distro 5.10.3
- Arch Linux ARM, `noctalia 5.4.1-1` package from `extra`
- mango 0.18.5

---

## 0. Quick start (if everything is already configured)

1. Open the Termux:X11 app.
2. In Termux, run:

```sh
mango-termux --restart
```

Noctalia starts automatically via `~/.config/mango/mics.conf`.

---

## 1. Prerequisites

- Termux.
- The Termux:X11 app (`com.termux.x11`).
- `proot-distro` and the `archlinuxarm` container.
- A working mango-termux.

### Termux:X11

```sh
pkg update
pkg install x11-repo
pkg update
pkg install termux-x11-nightly
```

### mango-termux

The mango port for Termux is built separately:

```sh
git clone https://github.com/OceanSt0ne/mango-termux.git
cd mango-termux
./build-termux.sh
```

`build-termux.sh` installs:

- `$PREFIX/bin/mango-termux` — the launch script;
- `$PREFIX/lib/mango-termux/mango` — the private GPU build;
- configs in `$PREFIX/etc/mango`.

For details and the dependency list, see the README of this repository.

Check:

```sh
mango-termux --restart
```

mango should open on top of Termux:X11. The Wayland socket appears here:

```sh
ls -l "$PREFIX/tmp"/wayland-*
# $PREFIX/tmp/wayland-0
```

---

## 2. Installing Noctalia in Arch Linux ARM

```sh
proot-distro install archlinuxarm
proot-distro login archlinuxarm
```

Inside Arch:

```sh
pacman -Syu --noconfirm
pacman -S --needed --noconfirm noctalia dbus grim
exit
```

`noctalia` is already available in the Arch Linux ARM `extra` repository.
`dbus` is needed for the session D-Bus (notifications, ScreenSaver).
`grim` is optional — for screenshots.

Check:

```sh
proot-distro login archlinuxarm -- noctalia --version
# noctalia v5.4.1
```

> The container runs as root. Noctalia configs live in
> `/root/.config/noctalia` and `/root/.local/state/noctalia`.

### GPU acceleration in the proot (Freedreno + KGSL)

Arch's stock `mesa`/`vulkan-freedreno` is built for DRM/MSM and cannot drive
Android's `/dev/kgsl-3d0`. Install the lfdevs Mesa 27 Arch packages, which
include the KGSL Freedreno Gallium driver:

```sh
cd "$PREFIX/tmp"
gh release download mesa-27.0.0-devel-20261025-r2 \
  -R lfdevs/mesa-for-android-container \
  -p '*archlinux_arm64.tar' --clobber
tar -xf mesa-for-android-container_*_archlinux_arm64.tar
proot-distro login archlinuxarm -- bash -lc '
  pacman -U --noconfirm --overwrite="/usr/lib/libvulkan_freedreno.so" \
    --overwrite="/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json" \
    /data/data/com.termux/files/usr/tmp/mesa-1:27.0.0-92-aarch64.pkg.tar.xz \
    /data/data/com.termux/files/usr/tmp/vulkan-freedreno-1:27.0.0-92-aarch64.pkg.tar.xz
  ldconfig'
```

Noctalia then renders natively through `FD735` instead of llvmpipe. The launch
script uses `MESA_LOADER_DRIVER_OVERRIDE=kgsl` and `GALLIUM_DRIVER=kgsl`
(`NOCTALIA_GPU=kgsl`, the default). `NOCTALIA_GPU=0` forces llvmpipe as a safe
fallback; `NOCTALIA_GPU=zink` is the older experimental path and is not needed.

Verify the renderer:

```sh
grep 'OpenGL ES vendor' "$PREFIX/tmp/mango.log"
# ... vendor="freedreno" renderer="FD735" — GPU path
# ... renderer="llvmpipe (LLVM ...)" — software fallback
```

---

## 3. Noctalia launch script

Mango limits the `exec=` value in the config to 255 bytes, so the long launch
command must be moved into a separate script.

Create `~/.config/mango/start-noctalia.sh`:

```sh
#!/data/data/com.termux/files/usr/bin/bash
# Start Noctalia from the Arch Linux ARM proot inside the mango session.
set -euo pipefail

: "${PREFIX:=/data/data/com.termux/files/usr}"
: "${XDG_RUNTIME_DIR:=${TMPDIR:-/tmp}}"
: "${WAYLAND_DISPLAY:=wayland-0}"
: "${NOCTALIA_GPU:=kgsl}"

case "$NOCTALIA_GPU" in
  0|llvmpipe)
    renderer_env=(
      MESA_LOADER_DRIVER_OVERRIDE="llvmpipe"
      GALLIUM_DRIVER="llvmpipe"
    )
    ;;
  zink)
    renderer_env=(
      MESA_LOADER_DRIVER_OVERRIDE="zink"
      GALLIUM_DRIVER="zink"
      VK_DRIVER_FILES="/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
      VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    )
    ;;
  *)
    renderer_env=(
      MESA_LOADER_DRIVER_OVERRIDE="kgsl"
      GALLIUM_DRIVER="kgsl"
    )
    ;;
esac

exec env \
  -u MESA_LOADER_DRIVER_OVERRIDE \
  -u GALLIUM_DRIVER \
  -u VK_DRIVER_FILES \
  -u VK_ICD_FILENAMES \
  -u LD_LIBRARY_PATH \
  -u LIBGL_DRIVERS_PATH \
  -u GBM_BACKENDS_PATH \
  proot-distro login archlinuxarm --shared-tmp \
  --bind "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR" \
  -- env \
  WAYLAND_DISPLAY="$WAYLAND_DISPLAY" \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  XDG_DATA_DIRS="/usr/local/share:/usr/share:$PREFIX/share" \
  "${renderer_env[@]}" \
  MANGO_INSTANCE_SIGNATURE="${MANGO_INSTANCE_SIGNATURE:-}" \
  dbus-run-session -- noctalia
```

Make it executable:

```sh
chmod +x ~/.config/mango/start-noctalia.sh
```

What matters here:

- `--shared-tmp` and `--bind "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR"` — Noctalia
  can see mango's Wayland socket.
- `MANGO_INSTANCE_SIGNATURE` — enables the `mango-ipc` backend (workspaces,
  focus, output power, keyboard layout, session shutdown).
- `XDG_DATA_DIRS=...:$PREFIX/share` — Termux apps' `.desktop` files appear in
  the launcher.
- `NOCTALIA_GPU=kgsl` (default) — native Freedreno/KGSL via Mesa 27; use
  `NOCTALIA_GPU=0` for the llvmpipe fallback and `NOCTALIA_GPU=zink` only for
  the old experimental Zink path.
- The `env -u ...` wrapper clears host Mesa, Vulkan and library-path variables
  before entering the proot, so Arch uses its own Mesa 27 rather than Termux's
  private KGSL build.
- `VK_DRIVER_FILES` / `VK_ICD_FILENAMES` — only set for `NOCTALIA_GPU=zink`;
  the KGSL path uses the Gallium driver directly and does not need Vulkan.
- `dbus-run-session` — starts Noctalia with its own session bus.

---

## 4. Connecting to mango

In `~/.config/mango/mics.conf`, add:

```ini
exec=~/.config/mango/start-noctalia.sh
```

Make sure there is no second `exec=` line with `noctalia` from an old
configuration.

Restart mango:

```sh
mango-termux --restart
```

---

## 5. Verifying everything works

### Processes

```sh
ps -A -o pid,stat,comm,args | grep -E 'mango-termux/mango|dbus-run|noctalia'
```

Expected output is roughly:

```text
... /mango-termux/mango
... proot ... dbus-run-session -- noctalia
... dbus-run-session -- noctalia
... noctalia
```

### Noctalia log

Start with logging:

```sh
mango-termux --restart > "$PREFIX/tmp/mango.log" 2>&1
```

Or in the background:

```sh
nohup mango-termux --restart > "$PREFIX/tmp/mango.log" 2>&1 &
```

Check:

```sh
grep -E 'connected compositor|workspace_mango|workspace backend|Notifications|ScreenSaver' \
  "$PREFIX/tmp/mango.log"
```

Key lines:

```text
connected compositor=yes ... ext-workspace=yes ... session-lock=yes ...
workspace_mango connected Mango IPC workspace socket=.../mango-<pid>.sock
workspace backend=mango-ipc
listening on org.freedesktop.Notifications
listening on org.freedesktop.ScreenSaver
```

### IPC

```sh
proot-distro login archlinuxarm --shared-tmp \
  --bind "$PREFIX/tmp:$PREFIX/tmp" \
  -- env WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="$PREFIX/tmp" \
  noctalia msg color-scheme-get
# builtin Noctalia
```

### mango workspaces

```sh
export MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"
mmsg get tags X11-1
```

Switching via Noctalia:

```sh
proot-distro login archlinuxarm --shared-tmp \
  --bind "$PREFIX/tmp:$PREFIX/tmp" \
  -- env WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="$PREFIX/tmp" \
  noctalia msg workspace-switch next
```

The mango tag should change from `1` to `2`; `prev` switches back.

---

## 6. `noctalia msg` directly from Termux

mango keybindings call `noctalia msg ...` in the host Termux, but the Noctalia
binary lives in proot. A proxy script is needed.

Create `$PREFIX/bin/noctalia`:

```sh
#!/data/data/com.termux/files/usr/bin/bash
# Proxy Noctalia IPC commands from Termux into the Arch Linux ARM proot.
set -euo pipefail

# Already inside the Arch proot: use the real binary, never recurse.
if [[ -f /etc/arch-release ]]; then
  exec /usr/bin/noctalia "$@"
fi

: "${XDG_RUNTIME_DIR:=/data/data/com.termux/files/usr/tmp}"
export XDG_RUNTIME_DIR

exec proot-distro login archlinuxarm --shared-tmp \
  --bind "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR" \
  -- env WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" \
  XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
  /usr/bin/noctalia "$@"
```

```sh
chmod +x "$PREFIX/bin/noctalia"
```

Now bindings like this work:

```ini
bind=SUPER,r,spawn,noctalia msg panel-toggle launcher
```

Check:

```sh
noctalia msg color-scheme-get
# builtin Noctalia
```

---

## 7. Launching Termux apps in the mango session

To make `foot`, `kitty`, and other Termux GUI apps connect to mango, export the
Wayland variables.

### fish

In `~/.config/fish/config.fish`:

```fish
# Mango/Noctalia Wayland session (Termux)
if test -S "$PREFIX/tmp/wayland-0"
    set -gx XDG_RUNTIME_DIR "$PREFIX/tmp"
    set -gx WAYLAND_DISPLAY wayland-0
end
```

### bash

In `~/.bashrc`:

```sh
# Mango/Noctalia Wayland session (Termux)
if [ -S "${PREFIX:-/data/data/com.termux/files/usr}/tmp/wayland-0" ]; then
  export XDG_RUNTIME_DIR="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
  export WAYLAND_DISPLAY=wayland-0
fi
```

### zsh

In `~/.zshrc` — the same block as for bash.

After that, in a new shell:

```sh
foot
```

The window should open inside mango. Check:

```sh
export MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"
mmsg get all-clients
```

### Termux apps in the Noctalia launcher

The `XDG_DATA_DIRS=...:$PREFIX/share` line in `start-noctalia.sh` already adds
host `.desktop` files. After restarting mango, the launcher (SUPER+R) will show,
for example, `Foot`, `Foot Client`, `Foot Server`, and `kitty`.

---

## 8. Limitations of the proot setup

Works:

- bar, wallpaper, dock, launcher, control center, lock screen;
- `noctalia msg` IPC;
- workspaces and focus via `mango-ipc`;
- notifications and ScreenSaver via the session D-Bus;
- launching Termux Wayland apps (`foot`, `kitty`) in the mango session.

Does not work or works partially:

- system D-Bus: no upower, NetworkManager, logind, or polkit agent;
- PipeWire: audio in Noctalia may be unavailable;
- Secret Service / keyring: secret storage and part of clipboard history;
- Noctalia renders through native Freedreno/KGSL (`FD735`) with the lfdevs
  Mesa 27 packages. Without them, use `NOCTALIA_GPU=0` for llvmpipe; the old
  Zink path may fall back to SHM and render black;
- Android apps do not appear in the launcher automatically. They need separate
  `.desktop` wrappers using `am start` / `termux-open`; they will open as
  Android windows, not inside mango.

---

## 9. Useful commands

Restart the whole session:

```sh
mango-termux --restart
```

Stop only Noctalia (mango will restart it on the next start):

```sh
pkill -x noctalia
```

Screenshot (if `grim` is installed in proot):

```sh
proot-distro login archlinuxarm --shared-tmp \
  --bind "$PREFIX/tmp:$PREFIX/tmp" \
  -- env WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="$PREFIX/tmp" \
  grim "$PREFIX/tmp/noctalia.png"
```

Reset the Noctalia config:

```sh
proot-distro login archlinuxarm -- \
  rm -rf /root/.config/noctalia /root/.local/state/noctalia
```

---

## 10. Troubleshooting

### Noctalia does not start

1. Check that `start-noctalia.sh` is executable:

   ```sh
   ls -l ~/.config/mango/start-noctalia.sh
   ```

2. Check that `exec=` in `mics.conf` is shorter than 255 bytes. If mango prints
   `Configuration value exceeds 255 bytes`, the command is ignored — use the
   script.

3. Run it manually and inspect the errors:

   ```sh
   XDG_RUNTIME_DIR="$PREFIX/tmp" WAYLAND_DISPLAY=wayland-0 \
     MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)" \
     ~/.config/mango/start-noctalia.sh
   ```

### Noctalia is black / renders with `llvmpipe`

`renderer="FD735"` is the expected GPU path; `renderer="llvmpipe"` means the
lfdevs Mesa 27 packages are missing or `NOCTALIA_GPU=0` is set:

```sh
grep 'OpenGL ES vendor' "$PREFIX/tmp/mango.log"
# ... vendor="freedreno" renderer="FD735" — GPU
```

If only llvmpipe is available, install the lfdevs Mesa 27 packages from the
section above, or explicitly force the stable software path:

```sh
NOCTALIA_GPU=0 ~/.config/mango/start-noctalia.sh
```

### The log says `workspace backend=ext-workspace`, not `mango-ipc`

`MANGO_INSTANCE_SIGNATURE` was not passed. Check:

```sh
NP=$(pgrep -x noctalia | head -1)
tr '\0' '\n' < /proc/$NP/environ | grep MANGO
```

### `dbus-run-session: command not found`

Install `dbus` inside Arch:

```sh
proot-distro login archlinuxarm -- pacman -S --needed dbus
```

### `mmsg: command not found` or mango IPC does not work

`mmsg` is a host Termux binary; it must be in `PATH` inside proot. Check:

```sh
proot-distro login archlinuxarm -- \
  env MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)" \
  mmsg get version
```

### `autostart.sh: Permission denied` / `bad interpreter` errors

This is a separate `~/.config/mango/autostart.sh`, unrelated to Noctalia. You can
run `chmod 600 ~/.config/mango/autostart.sh` or remove
`source=./autostart.conf` from `~/.config/mango/config.conf`.

### `Unknown keyword` errors in the mango log

The installed mango version does not recognize some config keys. This does not
affect Noctalia startup.

---

## 11. Removal

```sh
proot-distro login archlinuxarm -- pacman -Rns noctalia
rm -f ~/.config/mango/start-noctalia.sh
rm -f "$PREFIX/bin/noctalia"
```

Remove this line from `~/.config/mango/mics.conf`:

```ini
exec=~/.config/mango/start-noctalia.sh
```
