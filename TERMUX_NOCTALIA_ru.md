[English](TERMUX_NOCTALIA.md) | [Русский](TERMUX_NOCTALIA_ru.md)

# Нативная Noctalia в Termux и MangoWM

Проект: [README.md](README.md) | [README_ru.md](README_ru.md)

## Содержание

- [1. Обзор](#1-обзор)
- [2. Требования](#2-требования)
- [3. Установка](#3-установка)
- [4. Нативный лаунчер](#4-нативный-лаунчер)
- [5. Окружение выполнения](#5-окружение-выполнения)
- [6. Интеграция с MangoWM](#6-интеграция-с-mangowm)
- [7. Дочерние приложения](#7-дочерние-приложения)
- [8. Проверка](#8-проверка)
- [9. Устранение неполадок](#9-устранение-неполадок)
- [10. Обновление и сброс](#10-обновление-и-сброс)

## 1. Обзор

Noctalia 5.4.1 — обычный Wayland-клиент вложенного композитора MangoWM внутри Termux:X11. Второй композитор не запускается.

- Noctalia работает нативно: лаунчер запускает ELF-файл rootfs через glibc-загрузчик Termux, поэтому во время работы нет процессов `proot` или `proot-distro`, а процессы rootfs не запускают Noctalia.
- Arch Linux ARM rootfs служит только источником бинарника, библиотек и ресурсов. `proot-distro` применяется только для необязательного bootstrap rootfs и обновления пакетов.
- Канонический установщик — `install-noctalia-termux.sh`: он один раз находит rootfs, собирает приватное окружение в `$PREFIX/libexec/mango-termux` и устанавливает лаунчеры и обёртки.
- Настройки лежат в `$HOME/.local/state/noctalia/settings.toml` с запасным путём `$HOME/.config/noctalia/settings.toml`; MangoWM читает `$HOME/.config/mango/`.

## 2. Требования

- Рабочая сессия Termux и MangoWM в Termux:X11 со стеком Adreno Mesa из этого проекта. `proot-distro` и сеть нужны только для bootstrap rootfs и обновления пакетов.
- Пригодный rootfs с файлами `usr/bin/noctalia`, `lib/ld-linux-aarch64.so.1` и `usr/lib/libstdc++.so.6`; все три обязательны.
- Загрузчик glibc Termux по пути `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`, иначе установщик сообщает `FAIL: Termux loader missing`. `patchelf` необязателен: прямому режиму не нужен патченный бинарник.
- D-Bus необязателен. Отсутствие сессионной шины не фатально; если `DBUS_SESSION_BUS_ADDRESS` не задан, а `dbus-run-session` доступен, обычный запуск перезапускается в нативной сессионной шине Termux.

## 3. Установка

Поиск выполняется один раз, при установке: `--rootfs PATH`, `NOCTALIA_ROOTFS`, `$PREFIX/var/lib/proot-distro/installed-rootfs/*`, затем `$PREFIX/var/lib/proot-distro/containers/*/rootfs`.

- Если пригодного rootfs нет и явного переопределения нет, установщик разворачивает `archlinuxarm` через `proot-distro`, затем выполняет `pacman -Syu --noconfirm` и `pacman -S --needed --noconfirm noctalia`.
- Явный `--rootfs` или `NOCTALIA_ROOTFS` при непригодном дереве сразу завершается ошибкой и не запускает bootstrap; `--no-bootstrap` превращает отсутствие rootfs в ошибку, а `--bootstrap-rootfs` явно запрашивает bootstrap. `--check` только читает файлы, `--force` пересобирает приватное окружение без удаления rootfs, `--no-integrate` пропускает интеграцию, `--quiet` сокращает вывод.
- Установщик создаёт `$PREFIX/libexec/mango-termux` с `rootfs-libs/`, `egl_vendor.d/50_mesa.json`, `vulkan/icd.d/freedreno_icd.aarch64.json`, `runtime.env` и необязательным патченным `noctalia-native`; затем ставит `noctalia` и побайтово идентичный `mango-noctalia`, а также `noctalia-exec` и `noctalia-terminal`.
- Затем он запускает `mango-integrate`, переносит конфигурацию, состояние, данные и обои, переписывает пути `/root/`, обеспечивает `exec=noctalia`, `launch_apps_custom_command = "noctalia-exec $CMD"` и `reserve_space = true`, а также прогревает кэши.

```bash
./install-noctalia-termux.sh
./install-noctalia-termux.sh --check
./install-noctalia-termux.sh --bootstrap-rootfs
./install-noctalia-termux.sh --rootfs /path/to/rootfs
./install-noctalia-termux.sh --force --no-integrate
mango-termux --restart
```

## 4. Нативный лаунчер

`$PREFIX/bin/noctalia` и `$PREFIX/bin/mango-noctalia` создаются установщиком и побайтово совпадают; старый лаунчер один раз сохраняется как `.proot-bak` или `.mango-bak`.

- Лаунчер задаёт нативные `PREFIX`, `HOME`, `SHELL` (fish, запасной bash), `TMPDIR`, `XDG_RUNTIME_DIR=$PREFIX/tmp` и `PATH=$PREFIX/bin:/system/bin:/system/xbin`.
- При чтении `$PREFIX/tmp/mango-session.env` он сохраняет унаследованные `WAYLAND_DISPLAY` и `MANGO_INSTANCE_SIGNATURE`, а затем восстанавливает их.
- Он загружает `$PREFIX/libexec/mango-termux/runtime.env`; отсутствующий или устаревший runtime, непригодный rootfs или отличающийся явный `NOCTALIA_ROOTFS` приводят к остановке с требованием перезапустить установщик.
- Прямой режим включён по умолчанию (`NOCTALIA_DIRECT_LOADER=1`) и выполняет команду ниже; при `NOCTALIA_DIRECT_LOADER=0` используется патченный `$NOCTALIA_NATIVE_BIN`, если он существует.
- Ни один запуск не сканирует rootfs и не пересоздаёт символические ссылки. Запуск без аргументов берёт `flock`; `msg`, `--version` и `--help` обходят и блокировку, и повторный запуск через D-Bus под защитой `NOCTALIA_DBUS_WRAPPED=1`.

```bash
exec "$NOCTALIA_LOADER" --library-path "$NOCTALIA_RPATH" \
  "$NOCTALIA_ROOTFS/usr/bin/noctalia" "$@"
```

## 5. Окружение выполнения

Лаунчер очищает унаследованные `LD_*`, `PROOT_*`, переопределения Mesa, EGL и Vulkan из rootfs, пути Qt/QML, переменные IM и переопределения XKB, после чего выставляет нативные значения.

- Пути XDG нативные: состояние и данные лежат в `$HOME`, `XDG_DATA_DIRS` равен только `$PREFIX/share`, а `XDG_CONFIG_DIRS` — `$PREFIX/etc/xdg`. `MESA_SHADER_CACHE_DIR` указывает на `mesa_shader_cache_noctalia` в `$HOME/.cache`, а `MESA_SHADER_CACHE_MAX_SIZE` равен `256M`; унаследованные `MESA_SHADER_CACHE_DISABLE`, `MESA_GLSL_CACHE_DISABLE` и `MESA_GLSL_VERSION_OVERRIDE` снимаются, чтобы кэш оставался активным.
- Графика остаётся приватной: `__EGL_VENDOR_LIBRARY_DIRS="$PREFIX/libexec/mango-termux/egl_vendor.d"`, а `LIBGL_DRIVERS_PATH` и `GBM_BACKENDS_PATH` при наличии указывают внутрь rootfs. Переменные `VK_*` не экспортируются; `noctalia-exec` собирает нативный Vulkan ICD для дочерних приложений только из нативных файлов Termux, а `NOCTALIA_ASSETS_DIR` указывает на `$ROOTFS/usr/share/noctalia/assets`.
- XKB нативный: `XKB_CONFIG_ROOT="$PREFIX/share/X11/xkb"` со значениями по умолчанию `XKB_DEFAULT_LAYOUT=us,ru`, `XKB_DEFAULT_OPTIONS=grp:win_space_toggle`, `XKB_DEFAULT_RULES=evdev` и `XKB_DEFAULT_MODEL=pc105`; приоритет остаётся за `input.conf` в MangoWM.
- `TERMINAL` сохраняет существующее исполняемое значение; иначе лаунчер пробует `$PREFIX/bin/noctalia-terminal`, затем `foot`, `kitty`, `ghostty`, `alacritty`, `wezterm` и `xterm`. `run-mango.sh` также по умолчанию выбирает `$PREFIX/bin/noctalia-terminal`.
- Qt и QML включаются условно: при `NOCTALIA_HAS_QT=0` переменные `QML2_IMPORT_PATH`, `QT_PLUGIN_PATH` и `QML_DISK_CACHE_PATH` не выставляются и не действуют для текущего бинарника.

`runtime.env` содержит `NOCTALIA_ROOTFS`, `NOCTALIA_LOADER`, `NOCTALIA_RPATH`, `NOCTALIA_NATIVE_BIN`, `NOCTALIA_ASSETS_DIR`, `NOCTALIA_EGL_DIR`, `NOCTALIA_LIBGL_DRIVERS`, `NOCTALIA_GBM_BACKENDS` и `NOCTALIA_HAS_QT`.

```bash
cat "$PREFIX/libexec/mango-termux/runtime.env"
```

При `NOCTALIA_HAS_QT=1` лаунчер также экспортирует `QML2_IMPORT_PATH`, `QML_IMPORT_PATH`, `QT_PLUGIN_PATH`, `QT_QPA_PLATFORM_PLUGIN_PATH`, `QML_DISK_CACHE_PATH` и `QT_LOGGING_RULES`. Нативными также являются `TERM=xterm-256color`, если переменная не задана или равна `dumb`, `TERMINFO=$PREFIX/share/terminfo` и `FONTCONFIG_PATH="$PREFIX/etc/fonts"` при наличии каталога.

## 6. Интеграция с MangoWM

MangoWM записывает `MANGO_INSTANCE_SIGNATURE` с путём к своему IPC-сокету `$XDG_RUNTIME_DIR/mango-<pid>.sock` в `src/ipc/ipc.c`.

- Лаунчер сохраняет унаследованное значение, поэтому Noctalia определяет Mango и использует нативный workspace-бэкенд `mango-ipc` через `mmsg`. Если подпись отсутствует или непригодна, в лог пишется `Mango detected but MANGO_INSTANCE_SIGNATURE socket IPC is missing or unusable`, после чего используется `ext-workspace`.
- В `mics.conf` есть одна строка автозапуска `exec=noctalia`; биндинги вызывают `noctalia msg panel-toggle launcher`, `noctalia msg panel-toggle wallpaper`, а также действия громкости и яркости. `noctalia msg ...` и `mmsg` — нативные клиенты, которым не нужен D-Bus, а `mmsg get version` проверяет живость IPC.
- `mango-integrate` принимает `--quiet`, `--check`, `--no-firefox`, `--no-terminals` и `-h`/`--help`; `--check` только читает файлы и завершается с ненулевым кодом при отсутствии обёрток или патченных элементов рабочего стола.
- Панели используют layer-shell, а `reserve_space = true` не даёт заголовкам тайловых окон скрываться под ними; верхние и нижние панели не забирают фокус клавиатуры, а оверлейные лаунчеры могут. `run-mango.sh --restart` и `mango-termux --restart` обновляют интеграцию и завершают оставшуюся Noctalia; `MANGO_SKIP_INTEGRATIONS=1` пропускает обновление интеграции.

```bash
ls -l "$PREFIX/tmp"/mango-*.sock
MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)" \
  mmsg get version
grep -n 'noctalia msg' "$HOME/.config/mango/binds.conf"
```

## 7. Дочерние приложения

Изоляцией дочерних процессов управляет `noctalia-exec`.

- Она читает `$PREFIX/tmp/mango-session.env`, но приоритет отдаёт живым значениям `WAYLAND_DISPLAY`, `DISPLAY`, `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS`, `MANGO_INSTANCE_SIGNATURE`, `XCURSOR_THEME` и `XCURSOR_SIZE`.
- Она выставляет нативную идентичность Termux (`PREFIX`, `HOME`, `TMPDIR`, `PATH`, `SHELL`, `XDG_*`, `TERMINAL`, `TERM`) и удаляет переменные rootfs, glibc и приватного окружения Noctalia: `__EGL_VENDOR_LIBRARY_DIRS`, `LIBGL_DRIVERS_PATH`, `GBM_BACKENDS_PATH` из rootfs, `QML*`, `QT_*`, `MESA_SHADER_CACHE_*`, `NOCTALIA_*`, `LD_PRELOAD`, а также чужие переменные IM и XKB. `XDG_DATA_DIRS` остаётся `$PREFIX/share`, поэтому приложения, иконки и GSchemas из rootfs к детям не попадают. Обёртка завершается вызовом `exec "$@"`.
- Она восстанавливает нативный XKB и собирает пути KGSL и Turnip только из реальных файлов Termux в `$PREFIX/opt/mesa-kgsl` или `$PREFIX`, выставляя `MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `GALLIUM_DRIVER=kgsl`, нативный `LIBGL_DRIVERS_PATH` и нативный Vulkan ICD при наличии.
- `noctalia-terminal` нужен потому, что `runInTerminal` вызывает `$TERMINAL` напрямую; обёртка работает через `noctalia-exec` и предпочитает `$PREFIX/bin/foot`, затем `kitty`, затем `ghostty`. `kitty` и `ghostty` — сборки X11 и требуют вложенного Xwayland, а `foot` нативный для Wayland; без них обёртка завершается с `noctalia-terminal: no supported terminal found in $PREFIX/bin`. `mango-integrate` возвращает прямым записям терминалов исходный вид, направляет Firefox на `$PREFIX/bin/mango-firefox` и создаёт конфиги терминалов.

```bash
grep -H '^Exec=' "$PREFIX/share/applications/foot.desktop" \
  "$PREFIX/share/applications/kitty.desktop" \
  "$PREFIX/share/applications/com.mitchellh.ghostty.desktop" \
  "$PREFIX/share/applications/firefox.desktop"
command -v foot kitty ghostty firefox fish
```

## 8. Проверка

- `./install-noctalia-termux.sh --check` печатает строки `OK:` и `FAIL:` и проверяет rootfs, загрузчик, `libstdc++`, приватные ссылки, манифест EGL, Vulkan ICD, `libxml2.so.2`, лаунчеры и их побайтовую идентичность, `noctalia-exec`, нативный `XDG_DATA_DIRS`, `runtime.env` и `mango-integrate --check`.
- `mango-integrate --check` только читает файлы и завершается с ненулевым кодом при отсутствии обёрток или патченных записей. Отдельная проверка `./install-noctalia-termux.sh --check` сообщает об отсутствии `patchelf` как `FAIL: patchelf not found (patched fallback unavailable)`; прямой режим работает и без него.
- `"$PREFIX/bin/noctalia" --version` печатает установленную версию без запущенной сессии, а `pgrep -af` должен показывать один нативный процесс `noctalia` или `noctalia-native` и не показывать `proot`.

```bash
./install-noctalia-termux.sh --check
mango-integrate --check
"$PREFIX/bin/noctalia" --version
pgrep -af '/usr/bin/noctalia|libexec/mango-termux/noctalia-native'
```

## 9. Устранение неполадок

- `FAIL: no usable Noctalia rootfs found` означает, что ни одно дерево не прошло проверку: укажите `--rootfs`, задайте `NOCTALIA_ROOTFS` или разрешите автоматический bootstrap.
- `FAIL: rootfs is not usable` и `FAIL: NOCTALIA_ROOTFS is not usable` означают отсутствие обязательного файла rootfs; `FAIL: Termux loader missing` — отсутствие загрузчика по пути `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`.
- `FAIL: private link missing`, `FAIL: runtime env missing or stale`, отсутствующий лаунчер, неполное приватное окружение и ошибки EGL/GBM требуют повторного запуска установщика, при необходимости с `--force`; глобальную ссылку `libxml2.so.2` создавать нельзя. Ошибки лаунчера `missing runtime env`, `installed rootfs is not usable`, `Termux glibc loader not found` и `NOCTALIA_ROOTFS=... does not match installed rootfs` означают то же самое.
- `noctalia: another instance is already running` означает, что занята блокировка запуска без аргументов: используйте `noctalia msg ...` или перезапустите сессию; `mango-ipc` и `msg` этой блокировкой не ограничены.
- `noctalia-terminal: no supported terminal found in $PREFIX/bin` означает, что не установлены `foot`, `kitty` или `ghostty`; установите один из них и перезапустите установщик, если обёртка отсутствует.
- Если дочернее приложение загружает EGL или Mesa из rootfs либо падает с ошибками glibc, оно запущено не через `noctalia-exec`: проверьте `launch_apps_custom_command = "noctalia-exec $CMD"` и выполните `mango-integrate`.
- Если Noctalia пишет в лог сообщение об отсутствии подписи, она запущена без пригодного унаследованного значения: запустите её из автозапуска MangoWM или экспортируйте живой сокет командой `MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"`. Оставшееся предупреждение `/root/` исправляет `mango-integrate`: он копирует обои в `$HOME/Walls` и переписывает пути с резервными копиями `.mango-bak`; rootfs удалять не нужно.
- Ошибка Xwayland `fatal IO error 25` или исчезновение `:1` означают, что нужно сохранить значение по умолчанию `MANGO_XWAYLAND_GLAMOR=0` и перезапустить сессию; `1` снова включает DRI3 и glamor и может вернуть падения.

```bash
./install-noctalia-termux.sh --check
mango-integrate --check
pid=$(pgrep -f '/usr/bin/noctalia|libexec/mango-termux/noctalia-native' | head -1)
tr '\0' '\n' < "/proc/$pid/environ" | grep -E 'MANGO_INSTANCE_SIGNATURE|XKB_CONFIG_ROOT|TERMINAL'
```

## 10. Обновление и сброс

- Пакеты rootfs обновляются командой `proot-distro login archlinuxarm -- pacman -Syu --noconfirm` — это единственное оставшееся применение `proot-distro`; затем повторно запустите установщик, который обновляет приватные библиотеки, `runtime.env`, лаунчеры и интеграцию. `mango-termux --restart` запускает новую нативную сессию и завершает оставшуюся Noctalia.
- Для сброса конфигурации и состояния перенесите `$HOME/.config/noctalia` и `$HOME/.local/state/noctalia` в пути с суффиксом `.bak` и перезапустите сессию; `$HOME/Walls` сохраняется, если его не нужно удалять явно.

```bash
proot-distro login archlinuxarm -- pacman -Syu --noconfirm
./install-noctalia-termux.sh
mango-termux --restart
```
