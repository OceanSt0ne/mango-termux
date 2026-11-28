[English](README.md) | [Русский](README_ru.md)

# Mango Wayland Compositor для Termux

> Нативный порт [mango](https://github.com/mangowm/mango) 0.18.5 для Termux/Android: Termux:X11 без PRoot, только Qualcomm Adreno; другие SoC не поддерживаются.
> Сессия использует приватный стек Freedreno/KGSL Mesa 27 из сторонних `.deb`-пакетов: используйте на свой риск и сначала сделайте резервную копию данных.

## Содержание

- [1. Обзор](#1-обзор)
- [2. Требования](#2-требования)
- [3. Сборка](#3-сборка)
- [4. Быстрый старт](#4-быстрый-старт)
- [5. Запуск и окружение](#5-запуск-и-окружение)
- [6. Конфигурация](#6-конфигурация)
- [7. Рендеринг и GPU](#7-рендеринг-и-gpu)
- [8. Нативная Noctalia](#8-нативная-noctalia)
- [9. Интеграции и вспомогательные скрипты](#9-интеграции-и-вспомогательные-скрипты)
- [10. Устранение неполадок](#10-устранение-неполадок)
- [11. Документация](#11-документация)

## 1. Обзор

Mango — Wayland-композитор, портированный на Termux/Android. Версия 0.18.5 основана на wlroots 0.20 и работает как X11-клиент Termux:X11, а не как DRM/KMS-композитор.

Архитектура:

- Termux:X11 владеет Android-поверхностью и дисплеем.
- Mango использует X11-бэкенд wlroots и создаёт вложенную Wayland-сессию.
- Сам композитор по умолчанию рендерит через Mesa Zink поверх Freedreno Vulkan (Turnip).
- Клиенты сессии по умолчанию используют приватный стек Freedreno/KGSL Mesa 27.
- Альтернативные пути: Android EGL/AHardwareBuffer (`ahb`) и программный рендеринг (`pixman`).
- Для X11-приложений создаётся вложенный Xwayland, обычно с дисплеем `:1`.

Ограничения:

- Поддерживается только Adreno; другие SoC не тестируются и не поддерживаются.
- В Termux:X11 нет DRI3, кадры AHB передаются через SHM: возможны накладные расходы на копирование.
- Xwayland по умолчанию — стабильный сервер без glamor с косвенным GLX, а не DRI3-сервер.
- Высокие значения `vkmark` измеряют пропускную способность отправки GPU, а не частоту обновления дисплея.
- Приватный стек KGSL Mesa собирается из закреплённых сторонних `.deb`-пакетов и устанавливается вне штатного дерева Mesa Termux.

## 2. Требования

- Android arm64 с GPU Qualcomm Adreno.
- Termux, приложение Termux:X11 и пакет `termux-x11-nightly`.
- PRoot, systemd, udev, libinput и DRM/KMS не требуются.
- `scenefx` 0.5 входит в репозиторий уже пропатченным; в пакетах Termux его нет.
- Пакет `wlroots` 0.20 обязателен.
- Приватный KGSL Mesa 27 необязателен, но без него у клиентов сессии не будет аппаратного GL.
- Нативной Noctalia 5.6.x дополнительно нужны `glibc-runner` (загрузчик glibc Termux), `proot-distro` для bootstrap и обновления пакетов rootfs и терминал, например `foot`, для `runInTerminal`.

Установите зависимости сборки:

```bash
apt install x11-repo
apt update
apt install termux-x11-nightly
apt install clang pkg-config ninja patchelf git python-pip \
  wlroots libwayland libwayland-protocols libxkbcommon libpixman \
  libdrm libxcb xcb-util-wm xcb-util-renderutil xwayland \
  libglvnd-dev mesa mesa-dev mesa-vulkan-icd-freedreno \
  littlecms vulkan-loader pcre2 pango cjson libandroid-wordexp \
  dpkg curl
python -m pip install meson
```

Для нативной Noctalia также установите загрузчик, помощник rootfs и рекомендуемый терминал:

```bash
apt install glibc-runner proot-distro foot
```

Пакет `mesa-dev` даёт `gbm.h`; без него сборка падает с ошибкой о недостающем заголовке.

## 3. Сборка

Поддерживаемый способ — `./build-termux.sh`. Скрипт:

- проверяет нативные инструменты и зависимости pkg-config;
- применяет и откатывает `termux-compat/scenefx-termux.patch` для встроенного дерева `scenefx`;
- собирает scenefx и mango в release-режиме с `-O3`;
- устанавливает файлы в `$PREFIX`;
- создаёт `$PREFIX/lib/mango-termux/` с AHB-бинарником и приватными `libwlroots-0.20.so` и `libscenefx-0.5.so`, пропатченными на Android EGL/GLES;
- создаёт `~/.config/mango/config.conf` и `config.toml` только при их отсутствии, включая видимые эффекты для новых конфигураций;
- устанавливает приватный Freedreno/KGSL Mesa 27, если существует `/dev/kgsl-3d0`;
- запускает `mango-integrate`, ставит обёртку Firefox и launcher нативной Noctalia, если найден подходящий rootfs.

Переменные сборки:

- `PREFIX` — префикс Termux, по умолчанию `/data/data/com.termux/files/usr`.
- `SCENEFX_DIR` — альтернативное дерево исходников scenefx.
- `MANGO_SKIP_KGSL=1` — пропустить установку приватного стека Mesa 27.
- `MANGO_SKIP_INTEGRATIONS=1` — пропустить `mango-integrate`.
- `MANGO_SKIP_FIREFOX_FIX=1` — пропустить обёртку Firefox WebGL.

```bash
./build-termux.sh
MANGO_SKIP_KGSL=1 ./build-termux.sh
MANGO_SKIP_INTEGRATIONS=1 ./build-termux.sh
MANGO_SKIP_FIREFOX_FIX=1 ./build-termux.sh
```

Проверка установки:

- `mango -v` выводит версию 0.18.5.
- Установлены команды `mango`, `mango-termux`, `mango-x11-check`, `mango-integrate`, `noctalia`, `mango-noctalia`, `noctalia-exec`, `noctalia-terminal`, `mango-firefox` и `mango-gpu-run`.
- После изменения исходников повторите `./build-termux.sh` и перезапустите сессию.

## 4. Быстрый старт

Сначала откройте приложение Termux:X11, затем запустите launcher из Termux командой `mango-termux`.

Первый запуск создаёт конфигурации и при необходимости устанавливает KGSL и интеграции. Сборка никогда не перезаписывает существующие конфигурации: видимые эффекты включаются только в новых файлах.

```bash
mango-termux
mango-termux --restart
MANGO_TERMUX_RENDERER=ahb mango-termux
MANGO_TERMUX_RENDERER=pixman mango-termux
```

На экранах 2K размытие включайте только с оптимизированным проходом и не более двух проходов, иначе резко упадёт FPS:

```ini
blur=1
blur_optimized=1
blur_params_num_passes=2
```

Затем перечитайте конфигурацию `Super+R` или перезапустите сессию `mango-termux --restart`.

Если сессия не появилась, проверьте приложение Termux:X11 и журнал launcher `$PREFIX/tmp/termux-x11.log`.

## 5. Запуск и окружение

`mango-termux` — установленная копия `run-mango.sh`. Launcher:

- задаёт `PREFIX`, `TMPDIR`, `XDG_RUNTIME_DIR`, нативные `SHELL` и `TERMINAL`;
- экспортирует нативные значения XKB: `XKB_CONFIG_ROOT=$PREFIX/share/X11/xkb`, `XKB_DEFAULT_LAYOUT=us,ru`, `XKB_DEFAULT_OPTIONS=grp:win_space_toggle`, `XKB_DEFAULT_RULES=evdev`, `XKB_DEFAULT_MODEL=pc105`;
- создаёт `$PREFIX/tmp/mango-session.env` для дочерних процессов Noctalia;
- удаляет устаревшие сокеты и блокировки `wayland-*`;
- запускает Termux:X11 или переиспользует уже запущенный;
- настраивает стабильную обёртку Xwayland;
- выбирает рендерер и бинарник;
- запускает `mango-integrate`, если интеграции не отключены;
- переиспользует работающий экземпляр Mango по `MANGO_INSTANCE_SIGNATURE`, пока не указан `--restart`.

| Переменная | Значение по умолчанию | Назначение |
| --- | --- | --- |
| `MANGO_BACKEND` | `x11` | `x11`, `wayland` или `headless` |
| `MANGO_X11_DISPLAY` | `$DISPLAY` или `:0` | Дисплей Termux:X11 |
| `MANGO_BIN` | авто | Переопределить бинарник Mango |
| `MANGO_TERMUX_RENDERER` | `turnip` | `turnip`, `ahb` или `pixman` |
| `MANGO_TERMUX_GPU` | авто | Совместимый синоним: `1`/`ahb`, `0`/pixman, `turnip`/`zink` |
| `MANGO_RESTART` | `0` | Остановить работающий Mango перед запуском |
| `MANGO_XWAYLAND_GLAMOR` | `0` | `1` включает Xwayland с DRI3/glamor |
| `MANGO_X11_INPUT_PREFS` | `touchMode:1` | Настройки ввода Termux:X11: режим тачпада сохраняет относительный ввод; пусто — пропустить |
| `WLR_XWAYLAND` | авто | Переопределить бинарник Xwayland |
| `XDG_RUNTIME_DIR` | `$PREFIX/tmp` | Каталог сокетов Wayland/X11 |
| `NOCTALIA_ROOTFS` | авто | Rootfs для установщика нативной Noctalia |

Кэш шейдеров Mesa: лаунчер `mango-noctalia` экспортирует `MESA_SHADER_CACHE_DIR=$XDG_CACHE_HOME/mesa_shader_cache_noctalia` (по умолчанию `$HOME/.cache/mesa_shader_cache_noctalia`) с `MESA_SHADER_CACHE_MAX_SIZE=256M` и снимает унаследованные `MESA_SHADER_CACHE_DISABLE`, `MESA_GLSL_CACHE_DISABLE` и `MESA_GLSL_VERSION_OVERRIDE`, чтобы кэш шейдеров не инвалидировался между запусками Noctalia.

`TERMINAL` и переменные `XKB_*` задаются автоматически; переопределяйте их только при необходимости.

```bash
MANGO_X11_DISPLAY=:1 mango-termux
MANGO_TERMUX_RENDERER=ahb mango-termux
MANGO_XWAYLAND_GLAMOR=1 mango-termux
WLR_XWAYLAND=/path/to/Xwayland mango-termux
mango-termux --restart -s foot
```

Флага `--help` у launcher нет: дополнительные аргументы передаются самому Mango.

## 6. Конфигурация

Порядок поиска конфигурации:

1. `$HOME/.config/mango/config.conf`
2. `$HOME/.config/mango/config.toml`
3. `$PREFIX/etc/mango/config.conf`
4. `$PREFIX/etc/mango/config.toml`

`config.conf` и `config.toml` — альтернативные форматы; на Termux по умолчанию установлен `config.conf`. Модульные конфигурации подключаются через `source=./file.conf`; типичные файлы: `binds.conf`, `env.conf`, `input.conf`, `mics.conf`, `monitors.conf`, `windows.conf`, `animations.conf`, `layouts.conf`, `tags.conf`.

Стандартная конфигурация перечитывается по `Super+R`; пользовательские конфигурации могут переназначить эту комбинацию. Мобильный профиль для 2K включает размытие окон и тени плавающих окон, но оставляет отключёнными полноэкранное размытие слоёв и тени слоёв:

```ini
blur=1
blur_layer=0
blur_optimized=1
blur_params_num_passes = 2
blur_params_radius = 4
shadows = 1
layer_shadows = 0
shadow_only_floating = 1
shadows_size = 8
shadows_blur = 10
border_radius=12
animation_duration_move=300
animation_duration_open=250
animation_duration_tag=250
animation_duration_close=250
layer_animations = 0
```

На 2K включайте размытие только при `blur_optimized=1` и `blur_params_num_passes<=2`; больше проходов или неоптимизированное размытие дают заметное падение FPS. Эффекты требуют GPU-пути (`mango-termux`), а не программного `pixman`. Скрипт сборки записывает этот профиль только если `$HOME/.config/mango/config.conf` ещё не существует; существующие конфигурации никогда не перезаписываются, поэтому примените эти значения вручную и перечитайте конфигурацию по `Super+R` (или перезапустите сессию через `mango-termux --restart`), если анимации окон всё ещё дёргаются.

Горячие клавиши по умолчанию из `assets/config.conf`:

- `Super+R` — перечитать конфигурацию.
- `Super+M` — выйти из Mango.
- `Alt+Q` — закрыть активное окно.
- `Alt+Return` — запустить `foot`.
- `Alt+Space` — запустить `rofi -show drun`.
- `Super+Tab` — перейти к следующему окну.
- `Alt+Tab` — переключить jump-режим.
- `Alt+F` — переключить полноэкранный режим.

Пользовательские конфигурации и `binds.conf` могут переопределять эти комбинации. Проверьте или мигрируйте конфигурацию:

```bash
mango -p
mango -p -c "$HOME/.config/mango/config.conf"
./termux-compat/fix-mango-config.sh --dry-run
./termux-compat/fix-mango-config.sh
```

Параметры `fix-mango-config.sh`: `-n`/`--dry-run`, `--no-validate`, необязательный позиционный `CONFIG_DIR`, `-h`/`--help`. Скрипт создаёт резервные копии с меткой времени.

## 7. Рендеринг и GPU

Режим `turnip` (по умолчанию):

- Mango рендерит через Mesa Zink поверх Freedreno Vulkan/Turnip.
- Дочерние клиенты получают нативное окружение KGSL Mesa 27, а не глобальный Zink.
- Приватный корень — `$PREFIX/opt/mesa-kgsl`, если существует `lib/dri/kgsl_dri.so`; иначе используется штатный `$PREFIX`, если в нём есть драйвер KGSL.
- Launcher задаёт `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, `GBM_BACKENDS_PATH`, `MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `GALLIUM_DRIVER=kgsl`, `__EGL_VENDOR_LIBRARY_FILENAMES`, `VK_DRIVER_FILES` и `VK_ICD_FILENAMES` по необходимости.
- Если KGSL отсутствует, launcher предупреждает, и клиенты могут откатиться на llvmpipe.

Режим `ahb` использует `$PREFIX/lib/mango-termux/mango`, системные Android EGL/GLES и AHardwareBuffer; DRI3 не используется. Вместе с бинарником поставляются приватные `libwlroots-0.20.so` и `libscenefx-0.5.so`. Включается через `MANGO_TERMUX_RENDERER=ahb` или `MANGO_TERMUX_GPU=1`.

Режим `pixman` — программный рендеринг обычным бинарником Mesa; включается через `MANGO_TERMUX_RENDERER=pixman` или `MANGO_TERMUX_GPU=0`.

Приватный стек KGSL устанавливается скриптом `termux-compat/install-freedreno-kgsl.sh`. Он использует закреплённый release `freedreno-27.0.0-devel-20261025-r2`, проверяет SHA-256, сохраняет старое дерево как `mesa-kgsl.bak.<timestamp>` и не заменяет штатную Mesa Termux.

Ограничение AHB: Termux:X11 показывает кадры через копии SHM, поэтому AHB снимает ограничения GPU и драйвера, но не устраняет копирование в Android-поверхность.

Xwayland:

- Обёртка по умолчанию — `$PREFIX/tmp/mango-xwayland`. Она задаёт `XWAYLAND_NO_GLAMOR=1` и `LIBGL_DRI3_DISABLE=1`, затем запускает `Xwayland +iglx -shm`.
- `MANGO_XWAYLAND_GLAMOR=1` включает DRI3/glamor и снимает эти ограничения.
- `WLR_XWAYLAND` переопределяет реальный сервер.
- X11-приложения обычно видят `DISPLAY=:1`; внешний корень Termux:X11 — `:0`.

Производительность:

- Оптимизированное размытие (`blur_optimized=1`) кэширует обои и обновляет только при пересечении с ущербом экрана (partial damage), без полной перерисовки вывода каждый кадр.
- Кэш `wlr_texture` для blur-FBO: текстуры хранятся внутри каждой `fx_framebuffer`, инвалидация только при смене буфера или destroy — в горячем пути нет `wlr_texture_destroy`/`fx_texture_from_buffer`.
- При OPEN-анимации окна сила размытия фиксирована в `1.0`, затухание идёт только через alpha, чтобы не инвалидировать оптимизированное размытие.
- KGSL/Turnip (Freedreno) на Adreno 735; кэш шейдеров Mesa в `$HOME/.cache/mesa_shader_cache_noctalia` (256МБ), управляемый лаунчером `mango-noctalia`.

## 8. Нативная Noctalia

Noctalia 5.6.x работает в Termux нативно через glibc-загрузчик Termux. Rootfs Arch служит только источником бинарника, библиотек и ресурсов Noctalia; Noctalia 5.6 не является Qt/QML-приложением; PRoot применяется лишь для необязательной начальной установки rootfs и пакетов, но никогда во время работы.

Порядок поиска rootfs:

1. `--rootfs PATH`
2. `NOCTALIA_ROOTFS`
3. `$PREFIX/var/lib/proot-distro/installed-rootfs/*`
4. `$PREFIX/var/lib/proot-distro/containers/*/rootfs`

Установщику нужен `glibc-runner`; при отсутствии загрузчика он завершается с подсказкой `apt install glibc-runner`. Если подходящего rootfs нет, установщик разворачивает `archlinuxarm` и Noctalia (нужна сеть); с `--no-bootstrap` это становится ошибкой.

Установщик:

- собирает приватную среду в `$PREFIX/libexec/mango-termux`;
- копирует нужные библиотеки rootfs в `rootfs-libs`;
- использует `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`;
- при возможности создаёт пропатченный резервный кэш через `patchelf`;
- записывает `runtime.env`;
- связывает `$ROOTFS/usr/share/noctalia/assets` с `$PREFIX/glibc/lib/assets`, `$PREFIX/glibc/share/noctalia/assets` и аналогичными путями приватной среды; Noctalia 5.6 ищет ресурсы относительно загрузчика, поэтому эти ссылки обязательны;
- создаёт `mics.conf` с `exec=noctalia` и добавляет `source=./mics.conf` в `config.conf`;
- устанавливает launcher'ы `noctalia` и `mango-noctalia`;
- устанавливает `noctalia-exec` и `noctalia-terminal`;
- очищает чужие переменные IM/XKB и восстанавливает нативные пути XKB для дочерних процессов.

`noctalia-exec` пересобирает чистое нативное окружение Termux, сохраняет сокеты Wayland/X11, D-Bus, XDG runtime, курсор и переопределения KGSL/Turnip, отбрасывает rootfs-пути EGL/Mesa и унаследованные `GTK_IM_MODULE`, `QT_IM_MODULE`, `SDL_IM_MODULE`, `GLFW_IM_MODULE`, `XMODIFIERS`, `INPUT_METHOD`, `XKB_*`, а также разрешает `TERMINAL` в установленный терминал.

`noctalia-terminal` нужен потому, что `runInTerminal` в Noctalia вызывает `$TERMINAL` напрямую; обёртка направляет запуск через `noctalia-exec` и предпочитает Wayland-нативные `foot`, затем `kitty`, затем `ghostty`. Для пути по умолчанию установите `foot`.

Настройки Noctalia для этого порта:

- `launch_apps_custom_command = "noctalia-exec $CMD"`;
- `reserve_space = true` для верхней и нижней панелей, чтобы заголовки окон не рисовались под ними;
- overlay-launcher'ы могут забирать фокус клавиатуры; верхние и нижние панели не должны перехватывать фокус у клиентов;
- биндинги `noctalia msg` по умолчанию не устанавливаются; при необходимости добавьте их в `config.conf` или подключаемый `binds.conf`.

```bash
./install-noctalia-termux.sh
./install-noctalia-termux.sh --rootfs /path/to/rootfs
./install-noctalia-termux.sh --check
./install-noctalia-termux.sh --force --no-integrate
```

Флаги установщика: `--rootfs PATH`, `--force`, `--check`, `--no-integrate`, `--bootstrap-rootfs`, `--no-bootstrap`, `--quiet`, `-h`/`--help`. Режим `--check` только читает файлы, дополнительно проверяет ссылки на ресурсы и подключение автозапуска `mics.conf`; `--force` пересобирает приватную среду. После изменений выполните `mango-integrate --check` и `mango-termux --restart`.

Лаунчер `mango-noctalia` экспортирует `MESA_SHADER_CACHE_DIR`/`MESA_SHADER_CACHE_MAX_SIZE` (кэш в `$HOME/.cache/mesa_shader_cache_noctalia`, 256МБ) и снимает `MESA_SHADER_CACHE_DISABLE`, `MESA_GLSL_CACHE_DISABLE`, `MESA_GLSL_VERSION_OVERRIDE`, чтобы кэш шейдеров Mesa сохранялся между запусками Noctalia и её дочерних процессов.

## 9. Интеграции и вспомогательные скрипты

`mango-integrate` идемпотентен и обычно запускается из сборки и launcher. Он восстанавливает desktop-файлы терминалов, патчит записи и launcher Firefox, поддерживает launcher'ы нативной Noctalia и `env.conf` (`TERMINAL=noctalia-terminal`), подключает `mics.conf` из `config.conf` и создаёт безопасные настройки shell. Резервные копии получают суффикс `.mango-bak`.

Флаги: `--quiet`, `--check`, `--no-firefox`, `--no-terminals`, `-h`/`--help`.

Вспомогательные скрипты:

- `termux-compat/install-freedreno-kgsl.sh` — приватный стек Mesa 27 KGSL.
- `termux-compat/install-firefox-webgl.sh` — обёртка Firefox WebGL; поддерживает `--check`, пропускается через `MANGO_SKIP_FIREFOX_FIX=1`.
- `termux-compat/install-benchmark-fixes.sh` — обёртки glmark2 и исправления glibc для vkmark/assimp/Turnip.
- `termux-compat/build-arch-turnip.sh` — сборка Turnip в rootfs Arch для vkmark; необязательна и не входит в обычную работу.
- `termux-compat/fix-mango-config.sh` — миграция ключей конфигурации.
- `termux-compat/scenefx-termux.patch` — патч scenefx для AHB/Termux.
- `termux-compat/mango-*`, `noctalia-*` — устанавливаемые launcher'ы и помощники.

```bash
mango-integrate
mango-integrate --check
mango-integrate --no-firefox --quiet
apt install glmark2 libjpeg-turbo patchelf binutils
./termux-compat/install-benchmark-fixes.sh
./termux-compat/build-arch-turnip.sh
glmark2
glmark2-es2
grun --shell vkmark
```

Последняя группа команд необязательна: `build-arch-turnip.sh` нужен только для окружения Arch/proot с бенчмарками, а `install-benchmark-fixes.sh` не требуется для обычных сессий.

## 10. Устранение неполадок

```bash
echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
mango -v
mango-termux --restart -d
glxinfo -B 2>/dev/null | grep -E 'OpenGL renderer|OpenGL version'
vulkaninfo --summary 2>/dev/null | grep -E 'deviceName|driverName'
```

Типичные проблемы:

- Нет `gbm.h`: установите `apt install mesa-dev`.
- Termux:X11 недоступен: откройте приложение, выполните `mango-x11-check`, прочитайте `$PREFIX/tmp/termux-x11.log`.
- llvmpipe или отсутствие эффектов: установите стек KGSL, проверьте `$PREFIX/opt/mesa-kgsl/lib/dri/kgsl_dri.so` и перезапустите сессию через `mango-termux --restart`.
- FPS проседает при открытии окон: отключите размытие (`blur=0`) или снизьте `blur_params_num_passes` до ≤2 с `blur_optimized=1` (рекомендуемый мобильный профиль для 2K).
- Вложенный Xwayland падает или X11-клиент с GL завершается: оставьте `MANGO_XWAYLAND_GLAMOR=0` (значение по умолчанию) и не включайте glamor принудительно.
- 3D-игры с захватом курсора (Minecraft/LWJGL/GLFW) крутят камеру, упираются в ±90° или перестают вращаться у края экрана: держите Termux:X11 в режиме тачпада с `MANGO_X11_INPUT_PREFS=touchMode:1` (значение по умолчанию) и перезапускайте через `mango-termux --restart`. Пока курсор захвачен, MangoWM автоматически возвращает внешний указатель к центру, поэтому вращение не ограничено. Значения `touchMode` 2 и 3 передают абсолютные координаты касаний и ломают захват курсора. Посмотреть или переопределить живые значения: `termux-x11-preference list` и `termux-x11-preference touchMode:1`. Баги pointer-lock в вложенном X11 исправлены коммитами 37fa059 (подтверждение варпа указателя до рецентринга) и 95fd8d4 (остановка вращения камеры при захвате).
- X11-приложение открывается на внешнем `:0`: оно должно наследовать `DISPLAY=:1` от сессии Mango; пересоберите проект с включённым Xwayland.
- Firefox WebGL: выполните `mango-integrate`, затем `termux-compat/install-firefox-webgl.sh` и перезапустите сессию.
- Noctalia: при отсутствии rootfs используйте `--bootstrap-rootfs` или `--rootfs`; проверяйте через `--check`; для резервного бинарника нужен `patchelf`.
- `FAIL: Termux loader missing` или `Termux glibc loader not found`: установите загрузчик командой `apt install glibc-runner` и повторите запуск установщика.
- `fatal: could not locate library assets`: повторно запустите `./install-noctalia-termux.sh`; проверьте, что `$PREFIX/glibc/lib/assets` и `$PREFIX/glibc/share/noctalia/assets` указывают на `$ROOTFS/usr/share/noctalia/assets`. Для этого поиска Noctalia 5.6 игнорирует `NOCTALIA_ASSETS_DIR`.
- Noctalia не запускается автоматически: установщик или `mango-integrate` должны оставить `exec=noctalia` в `mics.conf` и `source=./mics.conf` в `config.conf`; `--check` сообщает об отсутствующем подключении.
- Биндинги `noctalia msg` не работают: по умолчанию они не устанавливаются. Добавьте их вручную при необходимости.
- Предупреждения `--check` о `libdisplay-info.so.2` или `libvulkan_freedreno.so` не фатальны: Noctalia использует EGL, а `noctalia-exec` передаёт дочерним процессам нативный Vulkan.
- Ярлыки приложений или ввод в Noctalia не работают: запускайте через `noctalia-exec`, сохраняйте нативный `XKB_CONFIG_ROOT` и не наследуйте IM-переменные rootfs.
- `vkmark` показывает тысячи FPS: это пропускная способность отправки GPU, а не частота обновления Termux:X11; плавность оценивайте визуально.

Пересборка и перезапуск: `./build-termux.sh && mango-termux --restart`.

## 11. Документация

- [README.md](README.md) / [README_ru.md](README_ru.md) — актуальный двуязычный обзор.
- [TERMUX_NOCTALIA.md](TERMUX_NOCTALIA.md) / [TERMUX_NOCTALIA_ru.md](TERMUX_NOCTALIA_ru.md) — подробное руководство по нативной настройке, работе, проверке и устранению неполадок Noctalia; установщик остаётся каноническим способом.
- [docs/](docs/index.md) — документация MangoWM по конфигурации: привязки клавиш, параметры, визуальные эффекты, управление окнами, патчи.
- Upstream-проект: [mangowm/mango](https://github.com/mangowm/mango)
- Лицензия: см. [LICENSE](LICENSE).
