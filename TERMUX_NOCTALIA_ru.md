[English](TERMUX_NOCTALIA.md) | **Русский**

# Noctalia в Termux + mango (Arch Linux ARM proot)

Проверенная связка:

```text
Android
└── Termux
    └── Termux:X11 (:0)
        └── mango-termux (X11 backend, нативный Termux-бинарь)
            └── Arch Linux ARM proot
                └── Noctalia 5.4.1
```

Noctalia запускается внутри proot, но подключается к Wayland-сокету mango.
Благодаря `MANGO_INSTANCE_SIGNATURE` используется родной backend mango:
`workspace backend=mango-ipc`, а не только общий `ext-workspace`.

Проверялось на:

- Termux / Android 14, aarch64
- Termux:X11 1.03.01
- proot-distro 5.10.3
- Arch Linux ARM, пакет `noctalia 5.4.1-1` из `extra`
- mango 0.18.5

---

## 0. Быстрый запуск (если всё уже настроено)

1. Открыть приложение Termux:X11.
2. В Termux выполнить:

```sh
mango-termux --restart
```

Noctalia стартует автоматически через `~/.config/mango/mics.conf`.

---

## 1. Что нужно заранее

- Termux.
- Приложение Termux:X11 (`com.termux.x11`).
- `proot-distro` и контейнер `archlinuxarm`.
- Работающий mango-termux.

### Termux:X11

```sh
pkg update
pkg install x11-repo
pkg update
pkg install termux-x11-nightly
```

### mango-termux

Порт mango для Termux собирается отдельно:

```sh
git clone https://github.com/OceanSt0ne/mango-termux.git
cd mango-termux
./build-termux.sh
```

`build-termux.sh` устанавливает:

- `$PREFIX/bin/mango-termux` — скрипт запуска;
- `$PREFIX/lib/mango-termux/mango` — приватная GPU-сборка;
- конфиги в `$PREFIX/etc/mango`.

Подробности и список зависимостей — в README этого репозитория.

Проверка:

```sh
mango-termux --restart
```

Должен открыться mango поверх Termux:X11. Wayland-сокет появится здесь:

```sh
ls -l "$PREFIX/tmp"/wayland-*
# $PREFIX/tmp/wayland-0
```

---

## 2. Установка Noctalia в Arch Linux ARM

```sh
proot-distro install archlinuxarm
proot-distro login archlinuxarm
```

Внутри Arch:

```sh
pacman -Syu --noconfirm
pacman -S --needed --noconfirm noctalia dbus grim
exit
```

`noctalia` уже есть в репозитории Arch Linux ARM `extra`.
`dbus` нужен для session D-Bus (уведомления, ScreenSaver).
`grim` опционален — для скриншотов.

Проверка:

```sh
proot-distro login archlinuxarm -- noctalia --version
# noctalia v5.4.1
```

> Контейнер работает от root. Конфиги Noctalia лежат в
> `/root/.config/noctalia` и `/root/.local/state/noctalia`.

### Аппаратное ускорение в proot (Freedreno + KGSL)

Штатный Arch `mesa`/`vulkan-freedreno` собран для DRM/MSM и не умеет работать
с `/dev/kgsl-3d0`. Установите Arch-пакеты Mesa 27 от lfdevs — в них есть
Gallium-драйвер Freedreno с KGSL:

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

После этого Noctalia рендерит нативно через `FD735`, а не llvmpipe. Скрипт
запуска использует `MESA_LOADER_DRIVER_OVERRIDE=kgsl` и
`GALLIUM_DRIVER=kgsl` (`NOCTALIA_GPU=kgsl`, по умолчанию). `NOCTALIA_GPU=0`
принудительно включает llvmpipe, `NOCTALIA_GPU=zink` — старый
экспериментальный путь.

Проверка рендерера:

```sh
grep 'OpenGL ES vendor' "$PREFIX/tmp/mango.log"
# ... vendor="freedreno" renderer="FD735" — GPU
# ... renderer="llvmpipe (LLVM ...)" — программный fallback
```

---

## 3. Скрипт запуска Noctalia

Mango ограничивает значение `exec=` в конфиге 255 байтами, поэтому длинную
команду запуска нужно вынести в отдельный скрипт.

Создать `~/.config/mango/start-noctalia.sh`:

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

Сделать исполняемым:

```sh
chmod +x ~/.config/mango/start-noctalia.sh
```

Что здесь важно:

- `--shared-tmp` и `--bind "$XDG_RUNTIME_DIR:$XDG_RUNTIME_DIR"` — Noctalia
  видит Wayland-сокет mango.
- `MANGO_INSTANCE_SIGNATURE` — включает backend `mango-ipc` (рабочие столы,
  фокус, output power, keyboard layout, завершение сессии).
- `XDG_DATA_DIRS=...:$PREFIX/share` — в launcher попадают `.desktop`-файлы
  Termux-приложений.
- `NOCTALIA_GPU=kgsl` (по умолчанию) — нативный Freedreno/KGSL через Mesa 27;
  `NOCTALIA_GPU=0` — llvmpipe, `NOCTALIA_GPU=zink` — только старый
  экспериментальный путь.
- Обёртка `env -u ...` очищает host-переменные Mesa, Vulkan и путей к
  библиотекам перед входом в proot, чтобы Arch использовал свою Mesa 27, а не
  приватную KGSL-сборку Termux.
- `VK_DRIVER_FILES` / `VK_ICD_FILENAMES` — задаются только для
  `NOCTALIA_GPU=zink`; KGSL-путь использует Gallium напрямую, без Vulkan.
- `dbus-run-session` — запускает Noctalia с собственным session bus.

---

## 4. Подключение к mango

В `~/.config/mango/mics.conf` добавить:

```ini
exec=~/.config/mango/start-noctalia.sh
```

Убедиться, что нет второго `exec=` с `noctalia` из старой конфигурации.

Перезапустить mango:

```sh
mango-termux --restart
```

---

## 5. Проверка, что всё работает

### Процессы

```sh
ps -A -o pid,stat,comm,args | grep -E 'mango-termux/mango|dbus-run|noctalia'
```

Ожидается примерно так:

```text
... /mango-termux/mango
... proot ... dbus-run-session -- noctalia
... dbus-run-session -- noctalia
... noctalia
```

### Лог Noctalia

Запуск с сохранением лога:

```sh
mango-termux --restart > "$PREFIX/tmp/mango.log" 2>&1
```

Либо в фоне:

```sh
nohup mango-termux --restart > "$PREFIX/tmp/mango.log" 2>&1 &
```

Проверка:

```sh
grep -E 'connected compositor|workspace_mango|workspace backend|Notifications|ScreenSaver' \
  "$PREFIX/tmp/mango.log"
```

Ключевые строки:

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

### Рабочие столы mango

```sh
export MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"
mmsg get tags X11-1
```

Переключение через Noctalia:

```sh
proot-distro login archlinuxarm --shared-tmp \
  --bind "$PREFIX/tmp:$PREFIX/tmp" \
  -- env WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="$PREFIX/tmp" \
  noctalia msg workspace-switch next
```

Тег mango должен смениться с `1` на `2`; `prev` вернёт обратно.

---

## 6. `noctalia msg` прямо из Termux

Бинды mango вызывают `noctalia msg ...` в хостовом Termux, но сам бинарь
Noctalia находится в proot. Нужен прокси-скрипт.

Создать `$PREFIX/bin/noctalia`:

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

Теперь работают бинды вида:

```ini
bind=SUPER,r,spawn,noctalia msg panel-toggle launcher
```

Проверка:

```sh
noctalia msg color-scheme-get
# builtin Noctalia
```

---

## 7. Запуск приложений Termux в сессии mango

Чтобы `foot`, `kitty` и другие GUI-приложения Termux подключались к mango,
нужно экспортировать Wayland-переменные.

### fish

В `~/.config/fish/config.fish`:

```fish
# Mango/Noctalia Wayland session (Termux)
if test -S "$PREFIX/tmp/wayland-0"
    set -gx XDG_RUNTIME_DIR "$PREFIX/tmp"
    set -gx WAYLAND_DISPLAY wayland-0
end
```

### bash

В `~/.bashrc`:

```sh
# Mango/Noctalia Wayland session (Termux)
if [ -S "${PREFIX:-/data/data/com.termux/files/usr}/tmp/wayland-0" ]; then
  export XDG_RUNTIME_DIR="${PREFIX:-/data/data/com.termux/files/usr}/tmp"
  export WAYLAND_DISPLAY=wayland-0
fi
```

### zsh

В `~/.zshrc` — тот же блок, что и для bash.

После этого в новом шелле:

```sh
foot
```

Окно должно открыться внутри mango. Проверка:

```sh
export MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"
mmsg get all-clients
```

### Приложения Termux в launcher Noctalia

Строка `XDG_DATA_DIRS=...:$PREFIX/share` в `start-noctalia.sh` уже добавляет
хостовые `.desktop`-файлы. После перезапуска mango в launcher (SUPER+R)
появятся, например, `Foot`, `Foot Client`, `Foot Server`, `kitty`.

---

## 8. Ограничения proot-схемы

Работает:

- бар, обои, dock, launcher, control center, lock screen;
- IPC `noctalia msg`;
- рабочие столы и фокус через `mango-ipc`;
- уведомления и ScreenSaver через session D-Bus;
- запуск Wayland-приложений Termux (`foot`, `kitty`) в сессии mango.

Не работает или работает частично:

- system D-Bus: нет upower, NetworkManager, logind, polkit-агента;
- PipeWire: звук в Noctalia может быть недоступен;
- Secret Service / keyring: сохранение секретов и часть истории буфера обмена;
- Noctalia рендерит через нативный Freedreno/KGSL (`FD735`) с Arch-пакетами
  Mesa 27 от lfdevs. Без них используйте `NOCTALIA_GPU=0` (llvmpipe); старый
  Zink-путь может откатываться на SHM и давать чёрный экран;
- Android-приложения не появляются в launcher автоматически. Для них нужны
  отдельные `.desktop`-обёртки с `am start` / `termux-open`; открываться они
  будут как Android-окна, а не внутри mango.

---

## 9. Полезные команды

Перезапуск всей сессии:

```sh
mango-termux --restart
```

Остановить только Noctalia (mango перезапустит её при следующем старте):

```sh
pkill -x noctalia
```

Скриншот (если установлен `grim` в proot):

```sh
proot-distro login archlinuxarm --shared-tmp \
  --bind "$PREFIX/tmp:$PREFIX/tmp" \
  -- env WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR="$PREFIX/tmp" \
  grim "$PREFIX/tmp/noctalia.png"
```

Сбросить конфиг Noctalia:

```sh
proot-distro login archlinuxarm -- \
  rm -rf /root/.config/noctalia /root/.local/state/noctalia
```

---

## 10. Диагностика проблем

### Noctalia не запускается

1. Проверить, что `start-noctalia.sh` исполняемый:

   ```sh
   ls -l ~/.config/mango/start-noctalia.sh
   ```

2. Проверить, что `exec=` в `mics.conf` короче 255 байт. Если mango пишет
   `Configuration value exceeds 255 bytes`, команда игнорируется — используйте
   скрипт.

3. Запустить вручную и посмотреть ошибки:

   ```sh
   XDG_RUNTIME_DIR="$PREFIX/tmp" WAYLAND_DISPLAY=wayland-0 \
     MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)" \
     ~/.config/mango/start-noctalia.sh
   ```

### Noctalia чёрная / рендерит через `llvmpipe`

`renderer="FD735"` — ожидаемый GPU-путь; `renderer="llvmpipe"` означает, что
Arch-пакеты Mesa 27 от lfdevs не установлены или задан `NOCTALIA_GPU=0`:

```sh
grep 'OpenGL ES vendor' "$PREFIX/tmp/mango.log"
# ... vendor="freedreno" renderer="FD735" — GPU
```

Если доступен только llvmpipe, установите пакеты Mesa 27 из раздела выше или
явно включите программный режим:

```sh
NOCTALIA_GPU=0 ~/.config/mango/start-noctalia.sh
```

### В логе `workspace backend=ext-workspace`, а не `mango-ipc`

Не передан `MANGO_INSTANCE_SIGNATURE`. Проверить:

```sh
NP=$(pgrep -x noctalia | head -1)
tr '\0' '\n' < /proc/$NP/environ | grep MANGO
```

### `dbus-run-session: command not found`

Установить `dbus` внутри Arch:

```sh
proot-distro login archlinuxarm -- pacman -S --needed dbus
```

### `mmsg: command not found` или IPC mango не работает

`mmsg` — хостовый бинарь Termux, он должен быть в `PATH` внутри proot.
Проверить:

```sh
proot-distro login archlinuxarm -- \
  env MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)" \
  mmsg get version
```

### Ошибки `autostart.sh: Permission denied` / `bad interpreter`

Это отдельный `~/.config/mango/autostart.sh`, к Noctalia отношения не имеет.
Можно сделать `chmod 600 ~/.config/mango/autostart.sh` или убрать
`source=./autostart.conf` из `~/.config/mango/config.conf`.

### Ошибки `Unknown keyword` в логе mango

Установленная версия mango не знает часть ключей из конфига. На запуск
Noctalia это не влияет.

---

## 11. Удаление

```sh
proot-distro login archlinuxarm -- pacman -Rns noctalia
rm -f ~/.config/mango/start-noctalia.sh
rm -f "$PREFIX/bin/noctalia"
```

Из `~/.config/mango/mics.conf` удалить строку:

```ini
exec=~/.config/mango/start-noctalia.sh
```
