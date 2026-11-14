[English](README.md) | [Русский](README_ru.md)

---

<div align="center">
  <img src="assets/mango.svg" alt="Логотип Mango" width="120"/>

  <h1>Mango Wayland Compositor v0.18.5</h1>

  <p>Быстрый, многофункциональный Wayland-композитор, адаптированный для Android/Termux.</p>

</div>

---

> **Порт для Termux/Android:** этот репозиторий — адаптация [mango](https://github.com/mangowm/mango) для Android/Termux.
> Композитор работает внутри Termux:X11 без PRoot.
>
> **Опциональная интеграция с Noctalia:** [English](TERMUX_NOCTALIA.md) | [Русский](TERMUX_NOCTALIA_ru.md).

---

## 1. Обзор проекта

### Что это за репозиторий

Mango — быстрый, многофункциональный Wayland-композитор. Этот репозиторий —
порт для Termux/Android, а не обёртка над PRoot.

Композитор запускается как обычный X11-клиент внутри Termux:X11 (`termux-x11`
и `com.termux.x11`) и использует нативный бэкенд wlroots `wlr_x11_backend`.
Termux:GUI больше не используется.

Опциональная интеграция Noctalia/Arch proot выполняется отдельно и не
требуется.

### Архитектура кратко

- Не требуются DRM, libinput, session, systemd и udev.
- Путь launcher по умолчанию: Mesa Zink + Turnip (Freedreno Vulkan). Рендеринг
  идёт в доступные для CPU Android AHardwareBuffer, а вывод в Termux:X11 — через
  SHM, поскольку Termux:X11 не предоставляет пригодный DRI3 DRM fd.
- Резервные пути: системный Android EGL + AHardwareBuffer (Adreno), затем
  pixman.
- Клиенты сессии и вложенный Xwayland используют приватный нативный путь
  Mesa 27 Freedreno/KGSL, если установлены `$PREFIX/opt/mesa-kgsl` и
  `$PREFIX/opt/xwayland-kgsl`.
- Конфигурация по умолчанию: `$PREFIX/etc/mango`; пользовательская:
  `~/.config/mango`.

### Известные ограничения

- Нет бэкендов DRM/libinput/session и нет `chvt`/переключения виртуальных
  терминалов.
- В Termux:X11 нет DRI3 DRM fd, поэтому путь вывода — AHB + SHM. Копирование
  AHB→SHM, выровненный stride AHB и явная синхронизация GPU могут ограничивать
  вывод на высоких разрешениях.
- Turnip/Zink добавляет накладные расходы на трансляцию в Vulkan; на некоторых
  нагрузках AHB может быть быстрее.
- Приложения, запущенные из внешнего shell с `DISPLAY=:0`, открываются в
  Termux:X11, а не внутри mango; запускайте их внутри mango или через
  `mango-termux -s`.
- Высокий FPS в `vkmark` не означает, что путь вывода X11 свободен от
  копирований или задержек Present.

## 2. Все изменения и патчи порта

### Система сборки и адаптация под Termux

- `meson_options.txt`: логическая опция `termux` со значением по умолчанию
  `true`; `xwayland` включён.
- `meson.build` в режиме Termux:
  - не требует libinput и `wlr/backend/session.h`;
  - добавляет include-каталог `termux-compat/` с заголовками-заглушками;
  - линкует `libandroid-wordexp`, поскольку в bionic отсутствует `wordexp(3)`;
  - устанавливает конфиги в `$PREFIX/etc/mango` и задаёт `SYSCONFDIR` внутри
    prefix;
  - определяет `TERMUX_BUILD`;
  - добавляет `termux/ahb.c` и `termux/zink.c`;
  - линкует `libandroid` и `libEGL`;
  - собирает `mango-x11-check` с xcb;
  - устанавливает `run-mango.sh` как `$PREFIX/bin/mango-termux` с правом на
    исполнение.
- `termux-compat/libinput.h`, `termux-compat/wlr/backend/libinput.h`,
  `termux-compat/wlr/backend/session.h`,
  `termux-compat/wlr/types/wlr_drm_lease_v1.h`: заглушки совместимости для
  интерфейсов wlroots, отсутствующих в Termux.
- `mangonag/mangonag.c`: `memfd_create` через `syscall()` для Android API < 30.
- `build-termux.sh`:
  - работает из любого cwd/симлинка; использует `PREFIX` по умолчанию
    `/data/data/com.termux/files/usr` и переопределение `SCENEFX_DIR`;
  - проверяет clang, pkg-config, meson, ninja, patchelf, git, wlroots 0.20,
    wayland, xkbcommon, pixman, libdrm, pango, cjson, xcb, EGL/GLES, GBM, lcms2,
    Vulkan, Xwayland, `libandroid-wordexp`, `mesa-dev`, Mesa Zink, Freedreno ICD;
  - обходит неспособность Meson выполнить stat для
    `/data/data/com.termux/files/lib` (режим 000), временно выполняя `chmod 700`
    и восстанавливая `000` при выходе;
  - применяет/откатывает `termux-compat/scenefx-termux.patch` для непатченного
    git-дерева scenefx;
  - собирает scenefx и mango с `--prefix="$PREFIX"`, `--buildtype=release`,
    `-Doptimization=3`; scenefx дополнительно использует
    `-Dexamples=false -Dwerror=false`; mango использует
    `-Dtermux=true -Dxwayland=enabled`;
  - всегда перенастраивает существующие каталоги сборки, чтобы старые
    конфигурации debug/`-O0` были заменены;
  - устанавливает приватные GPU-копии в `$PREFIX/lib/mango-termux`: `mango`,
    `libwlroots-0.20.so`, `libscenefx-0.5.so`;
  - патчит приватные копии через `patchelf`: заменяет `libEGL.so.1` и
    `libGLESv2.so.2` на пути Android `/system/lib64` или `/system/lib`, задаёт
    RPATH на приватный каталог + `$PREFIX/lib`;
  - копирует конфиги в `~/.config/mango` для новой установки и включает `blur`,
    `blur_layer`, `shadows`, `layer_shadows` и `border_radius=12` только для
    нового `config.conf`;
  - не изменяет существующие конфиги.
- `mango-session.target` может устанавливаться, но порт не требует systemd,
  udev, libinput, DRM или сеанса входа.

### Бэкенды и launcher

- Создание бэкендов Termux в `src/main.c`:
  - `WLR_BACKENDS` поддерживает `x11`, `wayland`, `headless`; при отсутствии
    значения по умолчанию используется x11;
  - `tgui` отклоняется с сообщением использовать `WLR_BACKENDS=x11` и
    Termux:X11;
  - создаёт мультибэкенд wlroots и outputs для запрошенных бэкендов;
  - X11-путь заранее интернирует `_NET_WM_NAME`, `UTF8_STRING`,
    `_VARIABLE_REFRESH`, `WM_PROTOCOLS`, `WM_DELETE_WINDOW` на временном
    X-соединении, чтобы избежать безвредных ошибок `BadAtom`/`ChangeProperty`;
  - сохраняет доступным вторичный headless-бэкенд.
- `run-mango.sh` / установленный `$PREFIX/bin/mango-termux`:
  - определяет собственный путь и `PREFIX`; использует
    `$PREFIX/opt/xwayland-kgsl/bin/Xwayland`, если он присутствует, кроме
    случаев когда задан `WLR_XWAYLAND`;
  - приоритет рендерера: сначала `MANGO_TERMUX_RENDERER`, затем совместимый
    `MANGO_TERMUX_GPU` (`0` → pixman, `1`/`ahb` → ahb, `turnip`/`zink` →
    turnip), иначе turnip;
  - в режиме Turnip экспортирует приватные переменные Mesa 27
    (`LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`, `GBM_BACKENDS_PATH`,
    `MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `GALLIUM_DRIVER=kgsl`) для дочерних
    процессов сессии и очищает устаревшие переменные Vulkan ICD;
    `termux/zink.c` ограничивает переменные Zink созданием рендерера самого
    mango;
  - если `$PREFIX/opt/mesa-kgsl/lib` отсутствует, снимает приватные переменные
    Mesa/KGSL, а не оставляет устаревшее переопределение;
  - режим AHB выбирает `$PREFIX/lib/mango-termux/mango` — бинарник,
    пропатченный на Android EGL/GLES;
  - режим pixman принудительно включает программный рендеринг;
  - задаёт `XDG_RUNTIME_DIR` в `$TMPDIR`, если переменная не задана, и режим
    700;
  - удаляет устаревшие `wayland-*.lock`/сокеты через `flock`, когда это
    возможно, иначе через проверки PID;
  - переиспользует живой IPC-сокет mango `$XDG_RUNTIME_DIR/mango-*.sock` после
    проверки через `mmsg get version`; `--restart` останавливает его и повторяет
    попытку;
  - дисплей по умолчанию — `$DISPLAY` или `:0`; проверяет реальный X11 handshake
    через `mango-x11-check`, а не только наличие файла сокета;
  - запускает `termux-x11 "$display" -ac -noreset` с удалёнными через `env -u`
    переменными Mesa/KGSL/Vulkan/EGL, чтобы X-сервер выбирал собственный стек
    рендерера;
  - удаляет из процесса Termux:X11 `LD_LIBRARY_PATH`, `LIBGL_DRIVERS_PATH`,
    `GBM_BACKENDS_PATH`, `MESA_LOADER_DRIVER_OVERRIDE`, `GALLIUM_DRIVER`,
    `FD_KGSL_DMABUF`, `VK_DRIVER_FILES`, `VK_ICD_FILENAMES`, `EGL_PLATFORM`,
    `__EGL_VENDOR_LIBRARY_FILENAMES`;
  - обрабатывает устаревшие `.X<n>-lock`/сокет, ждёт уже запускающийся сервер и
    повторяет попытку один раз после очистки;
  - задаёт `WLR_BACKENDS` (по умолчанию `x11`);
  - выбирает `MANGO_BIN`, установленный `mango` или `./build/mango`;
  - снимает `LD_LIBRARY_PATH` для приватного AHB-бинарника, чтобы его абсолютные
    NEEDED-записи Android EGL/GLES разрешались вне пространства имён Termux;
    RUNPATH достаточно.
- `termux/x11-check.c`: небольшой пробник на xcb, устанавливаемый как
  `mango-x11-check`; код выхода 0 означает реальное X11-соединение.

### Рендеринг: AHardwareBuffer и scenefx

- `termux/ahb.c`, `termux/ahb.h`:
  - локально объявляют нужное подмножество NDK `AHardwareBuffer` для старых
    целевых API Termux;
  - выделяют AHB с доступом CPU на чтение/запись и использованием GPU
    sampled/framebuffer;
  - поддерживают DRM-форматы BGRA/RGBA;
  - предоставляют AHB как EGLImage через `eglGetNativeClientBufferANDROID` +
    `eglCreateImageKHR`;
  - экспортируют AHB как атрибуты DMA-BUF с одной плоскостью для пути Zink;
  - дают доступ к указателю данных CPU через `AHardwareBuffer_lock/unlock`;
  - выводят в X11 через SHM; поскольку `xcb_shm_create_pixmap` требует
    stride == width × 4, а AHB дополняет stride, в качестве ширины SHM
    передаётся `stride / 4`; X-сервер обрезает дополнение;
  - предоставляют `termux_ahb_allocator_create()` и
    `termux_ahb_renderer_create()`.
- `scenefx/` — это встроенный scenefx 0.5 с уже применённым Termux-патчем.
  `termux-compat/scenefx-termux.patch` добавляет:
  - `fx_renderer_create_with_egl()` для существующего EGL display/context;
  - хуки внешнего провайдера EGLImage и провайдера DMA-BUF;
  - резервный путь, когда недоступны `EGL_EXT_image_dma_buf_import` /
    `EGL_EXT_platform_base`;
  - возможности буферов SHM/DATA_PTR при использовании провайдера EGLImage;
  - поддержку распаковки GLES 3.0 core, когда имя EXT не объявлено (Adreno);
  - резервный путь pixman/сцены без FX: отрисовка прямоугольников/текстур без
    эффектов;
  - оптимизированные blur-буферы с сохранением альфа-канала;
  - обновление оптимизированных blur-узлов по повреждению;
  - сэмплирование AHB/offscreen-буферов как GPU-текстур через EGLImage/DMA-BUF
    вместо пикселей, отображённых в CPU;
  - `glFinish()` после render target на базе AHB, поскольку X11-сервер
    потребляет буфер через mmap, а не через GPU fence.
- Выбор рендерера/аллокатора в `src/main.c`:
  - если доступен DRM fd, используется обычный FX-рендерер scenefx;
  - в Termux:X11 без DRM fd сначала пробуется Zink/Turnip, затем Android
    EGL/AHB, затем pixman;
  - при активном AHB или Zink используется AHB-аллокатор.
- `src/manage/monitor.c`: пересоздание рендерера при GPU reset проходит через
  те же `mango_renderer_create()` и `mango_allocator_create()`.

### Рендеринг: Mesa Zink + Turnip

- `termux/zink.c`, `termux/zink.h`:
  - инициализируют EGL display и контекст ES2, требуют
    `EGL_EXT_image_dma_buf_import`;
  - применяют
    `VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json`,
    `MESA_LOADER_DRIVER_OVERRIDE=zink`, `GALLIUM_DRIVER=zink`,
    `EGL_PLATFORM=surfaceless` только на время создания рендерера mango;
  - сохраняют и восстанавливают `VK_ICD_FILENAMES`,
    `MESA_LOADER_DRIVER_OVERRIDE`, `GALLIUM_DRIVER`, `EGL_PLATFORM`, чтобы
    дочерние GL/Vulkan-клиенты использовали нативный стек сессии;
  - импортируют буферы на базе AHB как DMA-BUF EGLImage и создают FX-рендерер
    через `fx_renderer_create_with_egl()`;
  - задают оба провайдера — EGLImage и DMA-BUF — для scenefx.
- Приватное дерево Mesa 27 в `$PREFIX/opt/mesa-kgsl` предоставляет Zink и
  нативный Freedreno/KGSL. Launcher экспортирует нативные переменные KGSL
  дочерним процессам сессии, а Zink ограничивает самим mango, избегая сломанного
  рендеринга GTK4/Ghostty из-за глобального переопределения Zink.

### GPU сессии и Xwayland на KGSL

- Сессия и дочерние клиенты используют приватный нативный Freedreno/KGSL
  Mesa 27 (`MESA_LOADER_DRIVER_OVERRIDE=kgsl`, `GALLIUM_DRIVER=kgsl`) и сообщают
  `FD735`.
- Штатный Xwayland в Termux собран с `-Dglamor=false`, поэтому вложенные
  X11-клиенты откатываются на llvmpipe. Порт использует
  `$PREFIX/opt/xwayland-kgsl/bin/Xwayland`, если он установлен:
  - glamor/DRI3 поверх `/dev/kgsl-3d0` без `/dev/dri` и `wl_drm`;
  - сервер Xwayland запускается с приватной Mesa 27 Zink/Turnip
    (`MESA_LOADER_DRIVER_OVERRIDE=zink`, `GALLIUM_DRIVER=zink`,
    `FD_KGSL_DMABUF=1`);
  - X11-клиенты наследуют нативный Mesa 27 KGSL, а не глобальный Zink;
  - буферы KGSL экспортируются как `DRM_FORMAT_MOD_LINEAR`, чтобы mango мог их
    импортировать, а не показывать чёрные окна;
  - резервный штатный сервер — `$PREFIX/bin/Xwayland.stock`; обёртка —
    `$PREFIX/bin/Xwayland`; переопределение — `WLR_XWAYLAND`.
- Проверка из терминала внутри mango:

```sh
DISPLAY=:1 glxinfo -B | grep -E 'Accelerated|OpenGL renderer'
# Accelerated: yes
# OpenGL renderer string: FD735
```

- Разовая диагностика Zink:

```sh
MESA_LOADER_DRIVER_OVERRIDE=zink GALLIUM_DRIVER=zink glxinfo -B
# OpenGL renderer string: zink Vulkan 1.4(Turnip Adreno (TM) 735 ...)
```

### Производительность: release-сборка и frame-done backpressure

- `build-termux.sh` собирает и `scenefx`, и `mango` как Meson release с
  `-Doptimization=3`; существующие каталоги сборки перенастраиваются для
  удаления устаревших `buildtype=debug` / `optimization=0`. Вспомогательные
  бинарники сохраняют собственные флаги `-O2`.
- `src/manage/monitor.c`:
  - сохраняет логический результат `mango_scene_output_commit()`;
  - если commit завершается ошибкой или пропускается (обычно swapchain X11
    заполнен, пока Present ожидает), возвращает управление без отправки
    `wlr_scene_output_send_frame_done()` и без повторного включения frame loop;
  - путь пропуска при resize также не отправляет `frame_done`;
  - следующее событие Present/Idle бэкенда инициирует повторную попытку, когда
    в swapchain появляется место.
- Это backpressure, а не ограничитель частоты обновления. Клиенты не должны
  получать `frame_done` за кадр, который output не принял.
- Искусственного ограничения 60 Hz нет. `MANGO_X11_FPS` и `-fakescreenfps`
  удалены и не поддерживаются.
- Основная оставшаяся стоимость вывода — копирование AHB→SHM/X11 Present:
  отсутствие пригодного DRI3 на output Termux:X11, дополненная ширина AHB,
  отклонённые X11 flips и `glFinish()` на пути AHB.
- `run-mango.sh` запускает Termux:X11 с собственным окружением рендерера;
  приватные переменные Mesa/KGSL не попадают в X-сервер.

### Миграция конфигурации

- `termux-compat/fix-mango-config.sh` переносит старые имена ключей `.conf`
  mango в имена версии 0.18.
- Поддерживает `-n/--dry-run`, `--no-validate`, `-h/--help`, позиционный
  каталог конфигурации или `--config-dir`.
- По умолчанию использует `${XDG_CONFIG_HOME:-$HOME/.config}/mango`.
- Создаёт каталог `backup-mango-config.XXXXXX` с меткой времени перед
  изменениями.
- Использует `mango -p -c .../config.conf` для проверки, если она не отключена.
- Безопасен для повторного запуска; если старые ключи не найдены, завершается
  успешно.
- Полная таблица переименований:

| Старый ключ | Текущий ключ |
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

- Удалённые опции `ov_tab_mode` и `ov_no_resize` комментируются, а не удаляются.
- Скрипт выводит путь резервной копии и напоминает перечитать конфигурацию
  через `Super+R` или перезапустить.

### Исправления бенчмарков

- `termux-compat/install-benchmark-fixes.sh`:
  - требует `patchelf` и `readelf`/binutils;
  - делает резервные копии нативных `glmark2`/`glmark2-es2` как `.orig` и при
    необходимости заменяет `libjpeg.so` на `libjpeg.so.8`;
  - устанавливает обёртки `$PREFIX/glibc/bin/glmark2` и `glmark2-es2`,
    запускающие нативные бинарники Termux на `$PREFIX/opt/mesa-kgsl` с
    нативными переменными KGSL;
  - делает резервные копии существующих glibc-обёрток как `.glibc`;
  - для `vkmark` проверяет, что Arch Turnip содержит `/dev/kgsl-3d0`, а Arch
    `libassimp.so.6` существует;
  - копирует Arch-библиотеки `libassimp`, `libvulkan_freedreno`, Wayland,
    xcb-keysyms, display-info, SPIRV-Tools и udev в
    `$PREFIX/opt/vkmark-kgsl/lib`;
  - создаёт `$PREFIX/opt/vkmark-kgsl/freedreno_icd.json`, указывающий на
    скопированный Turnip;
  - устанавливает обёртку `$PREFIX/glibc/bin/vkmark` и `vkmark.real`, задавая
    `VK_DRIVER_FILES`/`VK_ICD_FILENAMES` на этот JSON;
  - при необходимости патчит `vkmark.real` с `libassimp.so.5` на
    `libassimp.so.6`;
  - патчит `$PREFIX/opt/glibc-runner/glibc-runner.sh`, чтобы очищать
    bionic-переменные Mesa/KGSL перед входом в загрузчик glibc; резервная
    копия — `.bak`.
- `termux-compat/build-arch-turnip.sh`:
  - выполняется внутри Arch Linux ARM proot (`PROOT_DISTRO_NAME`, по умолчанию
    `archlinuxarm`);
  - устанавливает зависимости сборки Mesa через pacman;
  - скачивает соответствующий архив исходников Mesa с `archive.mesa3d.org`;
  - конфигурирует только драйвер Freedreno Vulkan с
    `-Dfreedreno-kmds=msm,kgsl`, без Gallium/EGL/GLX/LLVM;
  - собирает `libvulkan_freedreno.so`, проверяет строку `/dev/kgsl-3d0`,
    делает резервную копию старого Arch-драйвера как `.kgsl-old`, устанавливает
    новый драйвер и манифест ICD;
  - необязателен и нужен только для инструментов Arch/proot; хостовая сессия
    Termux не требует PRoot.
- Команды бенчмарков:

```bash
pkg install glmark2 libjpeg-turbo patchelf binutils
./termux-compat/build-arch-turnip.sh   # only if Arch Turnip lacks KGSL
./termux-compat/install-benchmark-fixes.sh
glmark2
glmark2-es2
grun --shell vkmark
```

### Вспомогательные скрипты и документация

- `termux-compat/fix-mango-config.sh`,
  `termux-compat/install-benchmark-fixes.sh`,
  `termux-compat/build-arch-turnip.sh`.
- `termux-compat/scenefx-termux.patch`.
- `termux/x11-check.c`.
- `TERMUX_NOCTALIA.md` и `TERMUX_NOCTALIA_ru.md`: опциональное руководство по
  интеграции Arch proot, настройке нативного KGSL, скрипту запуска Noctalia и
  изоляции окружения. Не является частью обязательного host-порта.

## 3. Зависимости и сборка

### Требования

- Android arm64, Termux, приложение Termux:X11 (`com.termux.x11`); пакет
  `termux-x11-nightly`.
- Не требуются PRoot, systemd, udev, libinput, DRM-сессия или виртуальный
  терминал.
- `$PREFIX` по умолчанию — `/data/data/com.termux/files/usr`.
- Опционально для лучшего GPU-пути: приватная Mesa 27 в
  `$PREFIX/opt/mesa-kgsl`, пропатченный Xwayland в
  `$PREFIX/opt/xwayland-kgsl`. Если их нет, launcher откатывается на путь
  Mesa/Xwayland хоста.

### Пакеты Termux

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

- `scenefx 0.5` встроен в `scenefx/` и недоступен в пакетах Termux.

### Опциональный пропатченный wlroots 0.20

- Порт собирается против wlroots 0.20. Готовое пропатченное дерево 0.20.2 с
  Termux-исправлениями (`shm_open`, пути Xwayland, бэкенд Termux:GUI) доступно
  по адресу `https://github.com/OceanSt0ne/wlroots-termux`.
- Устанавливайте его только если нужны эти патчи или требуется заменить пакет
  Termux.
- Патчи уже присутствуют в этом дереве; не применяйте их повторно.
- После установки повторно запустите `./build-termux.sh`, чтобы обновилась
  приватная копия `$PREFIX/lib/mango-termux/libwlroots-0.20.so`.
- Откат: `pkg reinstall wlroots`.

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

### Автоматическая сборка

```bash
cd ~/Projects/mango-termux
./build-termux.sh
```

- Скрипт можно запускать из любого каталога, с абсолютными/относительными
  путями или через симлинки.
- `SCENEFX_DIR=/path/to/scenefx ./build-termux.sh` использует внешнее дерево
  scenefx; непатченный git checkout получает патч автоматически.
- Скрипт использует release `-O3`, устанавливает `mango`, `mmsg`, `mangonag`,
  `mango-x11-check` и `mango-termux`.
- Создаёт приватные GPU-копии в `$PREFIX/lib/mango-termux`, патчит ссылки
  Android EGL/GLES и готовит `~/.config/mango` для новой установки.
- Установленный `$PREFIX/bin/mango` — обычная сборка с линковкой Mesa/Turnip;
  `$PREFIX/lib/mango-termux/mango` — приватная сборка Android
  EGL/AHardwareBuffer.

### Ручная сборка

- Скрипт рекомендуется, поскольку он также создаёт приватный GPU-бинарник и
  launcher.
- Ручные команды используют те же release-флаги:

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

- Ручная сборка не создаёт `$PREFIX/lib/mango-termux/mango`; используйте
  `./build-termux.sh` для пути AHB/приватного GPU.

### Проверка установки

```bash
mango -v
mango -p -c ~/.config/mango/config.conf
test -x "$PREFIX/bin/mango-termux" && echo launcher-ok
test -x "$PREFIX/lib/mango-termux/mango" && echo private-gpu-ok
```

## 4. Запуск и конфигурация

### Быстрый старт

- Откройте приложение Termux:X11, затем:

```bash
mango-termux
```

- Новые конфигурации получают эффекты автоматически. Существующие конфигурации
  не перезаписываются; при необходимости включите эффекты вручную.
- Запускайте `mango-termux`, а не чистый бинарник `mango`, когда требуется
  окружение рендерера.

### Поведение launcher

- Использует `XDG_RUNTIME_DIR` или `$TMPDIR`; дисплей по умолчанию — `:0` или
  `MANGO_X11_DISPLAY`.
- Переиспользует живой IPC-сокет mango; `--restart` заменяет его.
- Очищает устаревшие Wayland-блокировки/сокеты через `flock`/проверки PID.
- Проверяет X11 через `mango-x11-check`; при необходимости запускает
  Termux:X11; удаляет устаревшие `.X<n>-lock`/сокет и повторяет попытку один
  раз.
- Запускает Termux:X11 с `-ac -noreset` и чистым окружением рендерера.
- Задаёт `WLR_BACKENDS=x11` по умолчанию.
- Выбирает рендерер и бинарник, как описано выше.
- Экспортирует `DISPLAY` вложенного Xwayland дочерним процессам, чтобы
  X11-приложения, запущенные внутри mango, оставались во вложенной сессии.
- Снимает `LD_LIBRARY_PATH` перед exec приватного AHB-бинарника.

### Переменные окружения

| Переменная | Значение |
|---|---|
| `MANGO_BACKEND` | `x11` (по умолчанию), `wayland` или `headless`. |
| `WLR_BACKENDS` | Список бэкендов, передаваемый wlroots; по умолчанию `x11`. |
| `MANGO_X11_DISPLAY` | X-дисплей для Termux:X11; по умолчанию `$DISPLAY` или `:0`. |
| `MANGO_BIN` | Явный путь к бинарнику mango. |
| `MANGO_TERMUX_RENDERER` | `turnip` (по умолчанию), `ahb` или `pixman`. |
| `MANGO_TERMUX_GPU` | Селектор совместимости: `0` = pixman, `1`/`ahb` = ahb, `turnip`/`zink` = turnip. |
| `MANGO_RESTART` | `1` останавливает работающий экземпляр перед запуском. |
| `WLR_XWAYLAND` | Переопределяет путь к серверу Xwayland. |
| `XDG_RUNTIME_DIR` | Каталог runtime Wayland/IPC; по умолчанию `$TMPDIR`. |
| `PREFIX` | Префикс Termux; по умолчанию `/data/data/com.termux/files/usr`. |
| `SCENEFX_DIR` | Внешнее дерево исходников scenefx для сборки. |
| `PROOT_DISTRO_NAME` | Контейнер Arch proot для опциональных скриптов Turnip/бенчмарков. |
| `JOBS`, `MESA_BUILD_DIR` | Параллелизм сборки Arch Turnip и рабочий каталог. |
| `NOCTALIA_GPU` | Опциональный GPU-режим Arch Noctalia; по умолчанию `kgsl`, `0` = llvmpipe, `zink` — устаревший. |

### Примеры

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

### Перезапуск и автозапуск

- Launcher безопасно запускать повторно после открытия Termux заново.
- Если mango ещё работает, он находит `$XDG_RUNTIME_DIR/mango-*.sock`, проверяет
  его через `mmsg get version` и не запускает второй экземпляр.
- Если mango был убит, устаревшие `wayland-*.lock`/сокеты удаляются; живой
  композитор удерживает `flock`.
- Если Termux:X11 был убит, устаревшие `.X0-lock`/сокет удаляются, а сервер
  перезапускается.
- Опциональный автозапуск: создайте `~/.config/mango/autostart`, затем добавьте
  проверку маркера в конфигурацию shell.

Для bash (`~/.bashrc`):

```bash
if [[ $- == *i* && -f "$HOME/.config/mango/autostart" ]]; then
  nohup mango-termux >/dev/null 2>&1 &
fi
```

Для fish (`~/.config/fish/config.fish`):

```fish
if status is-interactive; and test -f "$HOME/.config/mango/autostart"
    nohup mango-termux >/dev/null 2>&1 &
end
```

Удалить автозапуск: `rm ~/.config/mango/autostart`.

### Файлы конфигурации и миграция

- Установленные значения по умолчанию: `$PREFIX/etc/mango/config.conf` и
  `config.toml`.
- Порядок поиска:
  1. `~/.config/mango/config.conf`
  2. `~/.config/mango/config.toml`
  3. `$PREFIX/etc/mango/config.conf`
  4. `$PREFIX/etc/mango/config.toml`
- Если после обновления mango показывает плашку с ошибкой, перенесите старые
  имена ключей:

```bash
./termux-compat/fix-mango-config.sh
mango -p -c ~/.config/mango/config.conf
```

- Скрипт миграции создаёт резервную копию с меткой времени, комментирует
  удалённые опции и безопасен для повторного запуска.
- После миграции перечитайте конфигурацию через `Super+R` или перезапустите
  mango.

### Эффекты

```ini
blur=1
blur_layer=1
shadows=1
layer_shadows=1
border_radius=12
```

- Эффекты выполняются на GPU при запуске через `mango-termux`.
- Проверьте путь Turnip:

```bash
MANGO_TERMUX_RENDERER=turnip mango-termux --restart -d 2>&1 | \
  grep -E 'Zink|Turnip|AHB|FX renderer|pixman'
```

- Принудительный AHB: `MANGO_TERMUX_RENDERER=ahb mango-termux`.
- Принудительный pixman: `MANGO_TERMUX_RENDERER=pixman mango-termux`.
- Прямой `$PREFIX/bin/mango` не задаёт окружение рендерера; используйте
  `mango-termux` или задавайте переменные явно.

### Горячие клавиши

| Комбинация клавиш | Действие |
|---|---|
| `Super+M` | выход из mango |
| `Alt+Return` | запустить `foot` |
| `Alt+Space` | `rofi -show drun` |
| `Super+R` | перечитать конфигурацию |
| `Alt+Q` | закрыть окно |
| `Super+Tab` | следующее окно |
| `Alt+Tab` | переключение jump-label |
| `Alt+F` | fullscreen |

- Установите `foot` и `rofi` отдельно: `pkg install foot rofi`.

### Вложенный Xwayland и окружение дочерних процессов

- `wlr_x11_backend` создаёт окно в Termux:X11 и получает события клавиатуры,
  указателя и touch.
- Клиенты подключаются к mango через `$XDG_RUNTIME_DIR/wayland-0`:

```bash
export XDG_RUNTIME_DIR="$TMPDIR"
export WAYLAND_DISPLAY=wayland-0
foot
```

- При работающем DRI3 используется обычный FX-рендерер scenefx.
- В Termux:X11 у output нет DRI3 DRM fd. Mango рендерит в AHB и выводит через
  SHM.
- Turnip — путь по умолчанию через `mango-termux`; переменные Zink/Vulkan
  ограничены созданием рендерера mango.
- Дочерние GL-клиенты используют приватный нативный Freedreno/KGSL Mesa 27
  (`FD735`), а не глобальный Zink.
- Вложенный Xwayland даёт X11-клиентам DRI3 и нативный KGSL, когда установлен
  пропатченный сервер.
- Приложения, запущенные из shell с внешним `DISPLAY=:0`, всё равно открываются
  вне mango; запускайте их внутри mango или через `mango-termux -s`.

### Бенчмарки

- Установка и запуск:

```bash
pkg install glmark2 libjpeg-turbo patchelf binutils
./termux-compat/build-arch-turnip.sh   # only if Arch Turnip lacks KGSL
./termux-compat/install-benchmark-fixes.sh
glmark2
glmark2-es2
grun --shell vkmark
```

- Установщик исправляет `libjpeg` нативного glmark2, устанавливает обёртки KGSL
  Turnip для `vkmark` и изолирует `glibc-runner` от bionic-переменных Mesa/KGSL.
- `vkmark` может показывать очень высокий FPS; см. раздел устранения неполадок.

### Опциональная интеграция Noctalia

- Noctalia внутри Arch proot необязательна и не требуется для mango-termux.
- Руководства: `TERMUX_NOCTALIA.md` / `TERMUX_NOCTALIA_ru.md`.
- `~/.config/mango/start-noctalia.sh` очищает переменные Mesa/Vulkan/библиотек
  хоста перед входом в proot, чтобы Arch использовал собственную нативную
  Mesa 27 KGSL (`renderer="FD735"`).
- `NOCTALIA_GPU=kgsl` — по умолчанию; `NOCTALIA_GPU=0` принудительно включает
  llvmpipe; `NOCTALIA_GPU=zink` — устаревший режим.
- `MANGO_INSTANCE_SIGNATURE` заставляет Noctalia использовать нативный бэкенд
  рабочих пространств `mango-ipc`.
- Сам host-порт не использует PRoot.

## 5. Устранение неполадок

### Диагностика рендерера: Turnip/KGSL или llvmpipe

- `FD735` означает нативный Freedreno/KGSL для сессии или X11-клиентов.
- `zink Vulkan ... Turnip ...` означает Zink/Turnip; ожидаемо для собственного
  рендерера mango или явной диагностики.
- `llvmpipe` означает программный резервный путь.
- Проверка ускорения X11-клиента изнутри mango:

```sh
DISPLAY=:1 glxinfo -B | grep -E 'Accelerated|OpenGL renderer'
```

- Проверка Freedreno Vulkan ICD:

```sh
VK_ICD_FILENAMES=$PREFIX/share/vulkan/icd.d/freedreno_icd.aarch64.json \
  vulkaninfo --summary
```

- Проверка рендерера композитора:

```sh
MANGO_TERMUX_RENDERER=turnip mango-termux --restart -d 2>&1 | \
  grep -E 'Zink|Turnip|AHB|FX renderer|pixman'
```

- `Termux: Zink/Turnip renderer unavailable`: установите
  `mesa-vulkan-icd-freedreno`, проверьте ICD выше и ожидайте откат на AHB или
  pixman.
- `Termux: AHB/EGL renderer unavailable, falling back to pixman`: пересоберите
  через `./build-termux.sh` и убедитесь, что установлен `patchelf` и существует
  приватный бинарник.
- `Failed to open DRI3` / `Disabling DMA-BUF support`: нормально для output
  Termux:X11; порт использует AHB + SHM.

### Замеры FPS и vkmark

- Результаты `vkmark`/mailbox/immediate могут достигать тысяч FPS. Это измеряет
  пропускную способность отправки GPU, а не частоту обновления дисплея
  Termux:X11.
- Искусственного ограничения 60 Hz нет. `MANGO_X11_FPS` и `-fakescreenfps` не
  поддерживаются.
- Высокий FPS не доказывает плавность пути вывода: копирование AHB→SHM,
  дополненный stride, задержки Present и `glFinish()` могут ограничивать
  видимый frame pacing.
- Оценивайте плавность визуально в Termux:X11 и отдельно сравнивайте `glmark2`,
  `vkmark` и интерактивное поведение.
- Для диагностики используйте `mango-termux -d` и изучайте сообщения
  рендерера/commit/Present.

### Сокеты Wayland и X11

- Wayland-сокет: `$XDG_RUNTIME_DIR/wayland-0` (обычно `$TMPDIR/wayland-0`).
- IPC-сокет mango: `$XDG_RUNTIME_DIR/mango-*.sock`; проверка через
  `mmsg get version`.
- Блокировка/сокет X11: `$TMPDIR/.X0-lock`, `$TMPDIR/.X11-unix/X0`.
- Проверка реального X11 handshake:

```bash
DISPLAY=:0 mango-x11-check; echo $?
```

- Лог Termux:X11: `$TMPDIR/termux-x11.log`.
- Launcher удаляет устаревшие блокировки только после подтверждения, что сервер
  не отвечает; не удаляйте сокет живого сервера вручную.

### Типичные ошибки

- `fatal error: 'gbm.h' file not found`: пакет Termux `mesa` предоставляет
  `gbm.pc`/`libgbm`, но заголовок находится в `mesa-dev`. Выполните
  `pkg install mesa-dev && ./build-termux.sh`; удалять каталог сборки не нужно.
- `X11 error: op 18:0, code 5`: безвредная ошибка `ChangeProperty`/atom при
  запуске X11-бэкенда; композитор заранее интернирует нужные атомы.
- `Failed to connect to Termux:X11`: откройте приложение Termux:X11, изучите
  `$TMPDIR/termux-x11.log` и выполните
  `DISPLAY=:0 mango-x11-check; echo $?`.
- X11-приложения открываются на внешнем рабочем столе Termux:X11: они
  унаследовали `DISPLAY=:0`. Запускайте их из терминала внутри mango или
  используйте `mango-termux -s <app>`; пересоберите текущим скриптом, чтобы
  Xwayland был включён для существующих каталогов сборки.
- Чёрный/пустой экран: убедитесь, что приложение Termux:X11 открыто; запустите
  `mango-termux -d` и изучите лог.
- Медленный рендеринг: уменьшите разрешение Termux:X11, отключите
  анимации/эффекты в `config.conf` или попробуйте `MANGO_TERMUX_RENDERER=ahb` /
  `pixman` для сравнения.
- `couldn't create renderer`: убедитесь, что scenefx собран с
  `scenefx-termux.patch`, установлен в `$PREFIX`, а launcher использует
  ожидаемый бинарник.
- Нет GPU-эффектов: проверьте, что конфигурация включает эффекты, что для пути
  Turnip существует `$PREFIX/opt/mesa-kgsl` и установлен
  `mesa-vulkan-icd-freedreno`.
- `vkmark` завершается с ошибками assimp/Vulkan: запустите
  `termux-compat/install-benchmark-fixes.sh`; для Arch Turnip KGSL запустите
  `termux-compat/build-arch-turnip.sh`.
- `glibc-runner` подхватывает bionic Mesa: повторно запустите установщик
  бенчмарков, чтобы пропатчить `glibc-runner.sh`, или удалите bionic-переменные
  из окружения.

### Пересборка

```bash
cd ~/Projects/mango-termux
./build-termux.sh
```

- Скрипт перенастраивает существующие каталоги сборки scenefx и mango как
  release `-O3` и обновляет установленные бинарники и приватные GPU-копии.
- После пересборки перезапустите сессию: `mango-termux --restart`.
