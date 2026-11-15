[English](TERMUX_NOCTALIA.md) | [Русский](TERMUX_NOCTALIA_ru.md)

# Noctalia в Termux + MangoWM (нативно, без proot)

## 0. Быстрый старт

### 0.1 Что настраивает это руководство

Это руководство настраивает Noctalia 5.4.1 как нативный процесс Termux и как
Wayland-клиент вложенной сессии MangoWM. Сам MangoWM работает внутри
Termux:X11; Noctalia — клиент внутри этого вложенного Wayland-композитора.

Arch Linux ARM rootfs используется только как источник ELF-файла Noctalia и его
ресурсных файлов. Во время выполнения лаунчер не запускает процессы `proot` или
`proot-distro`. Rootfs не является тюрьмой (jail), и процесс Noctalia не
выполняется внутри неё. `proot-distro` используется только для установки или
обновления rootfs в разделах 2 и 10.

Итоговая сессия обеспечивает:

- нативное выполнение ELF-файла Noctalia с загрузчиком glibc из Termux;
- приватные пути rootfs для Mesa 27, EGL, Vulkan и DRI без глобальных ссылок
  `libxml2.so.2`;
- нативный IPC MangoWM через `MANGO_INSTANCE_SIGNATURE`, поэтому бэкенд рабочих
  пространств — `mango-ipc`;
- панели и бары layer-shell без дополнительной конфигурации MangoWM;
- автозапуск через `~/.config/mango/mics.conf`;
- нативные дочерние приложения Termux, такие как терминалы и Firefox.

### 0.2 Быстрый путь

Если MangoWM, Arch rootfs, Noctalia и нативный лаунчер уже установлены,
перезапустите сессию:

```sh
mango-termux --restart
```

MangoWM запускает Noctalia из `mics.conf`. Используйте разделы 6 и 7, когда
требуется интеграция или проверка.

## 1. Требования

### 1.1 Termux и MangoWM

Termux должен быть установлен из актуальной сборки APT. Установите пакет
Termux:X11:

```sh
pkg update
pkg install x11-repo
pkg update
pkg install termux-x11-nightly
```

Соберите и установите MangoWM для Termux:

```sh
git clone https://github.com/OceanSt0ne/mango-termux.git
cd mango-termux
./build-termux.sh
```

`build-termux.sh` устанавливает MangoWM, `mango-termux`, `mmsg` и нативный
лаунчер `mango-noctalia`. Он также запускает `mango-integrate`, если не задана
переменная `MANGO_SKIP_INTEGRATIONS=1`. На этапе сборки rootfs не требуется; при
следующем запуске MangoWM применяется интеграция Noctalia, если доступен
пригодный rootfs.

MangoWM работает как вложенный Wayland-композитор поверх Termux:X11. Его
каталог времени выполнения — `$PREFIX/tmp`, а Wayland-сокет — `wayland-0`.

### 1.2 Arch rootfs и Noctalia

Arch Linux ARM rootfs предоставляет во время выполнения несколько файлов:

- `usr/bin/noctalia` — ELF-файл Noctalia;
- `lib/ld-linux-aarch64.so.1` — загрузчик rootfs; он нужен для проверки, но не
  выполняется напрямую;
- `usr/lib/libstdc++.so.6` — среда выполнения C++, закреплённая в нативной
  копии.

Лаунчер автоматически обнаруживает rootfs в
`$PREFIX/var/lib/proot-distro/installed-rootfs/*` и
`$PREFIX/var/lib/proot-distro/containers/*/rootfs`. Задайте `NOCTALIA_ROOTFS`,
чтобы переопределить обнаружение. Далее в руководстве `ROOTFS` обозначает
выбранное дерево:

```sh
ROOTFS="${NOCTALIA_ROOTFS:-$PREFIX/var/lib/proot-distro/containers/archlinuxarm/rootfs}"
ls -l "$ROOTFS/usr/bin/noctalia"
```

Перед подготовкой чего-либо лаунчер проверяет `usr/bin/noctalia`,
`lib/ld-linux-aarch64.so.1` и `usr/lib/libstdc++.so.6`. Загрузчик rootfs
никогда не используется как интерпретатор процесса; раздел 3.2 объясняет
почему.

### 1.3 Нативные инструменты

Установите нативные инструменты, используемые лаунчером:

```sh
pkg install patchelf dbus
```

`patchelf` обязателен. Он задаёт интерпретатор и RPATH для приватной копии
Noctalia и закрепляет `libstdc++.so.6` из rootfs. Без `patchelf` лаунчер
завершается с ошибкой.

`dbus` — реализация сессионной шины Termux. Noctalia использует нативный D-Bus
Termux, а не D-Bus Arch. Если сессионная шина уже присутствует, Noctalia
наследует `DBUS_SESSION_BUS_ADDRESS`; иначе лаунчер повторно запускает себя под
`dbus-run-session`.

## 2. Установка Noctalia в rootfs

### 2.1 Подготовка rootfs

Установите контейнер Arch Linux ARM и откройте в нём оболочку:

```sh
proot-distro install archlinuxarm
proot-distro login archlinuxarm
```

Установка и обновление rootfs — единственные этапы, где используется
`proot-distro`. Установленный rootfs обычно находится по пути
`$PREFIX/var/lib/proot-distro/containers/archlinuxarm/rootfs`; в старых схемах он
может располагаться в `installed-rootfs/archlinuxarm`.

### 2.2 Пакет Noctalia

Внутри контейнера обновите базу пакетов и установите Noctalia:

```sh
pacman -Syu --noconfirm
pacman -S --needed --noconfirm noctalia
exit
```

Noctalia 5.4.1 доступна из репозитория `extra` Arch Linux ARM. Пакет
предоставляет один ELF-файл по пути `/usr/bin/noctalia`. Он не предоставляет
отдельного процесса quickshell, `qs` или QML, и у бинарника нет библиотек Qt в
`NEEDED`. Пакет — лишь полезная нагрузка для нативного лаунчера.

Не устанавливайте Arch `dbus` для сессионной шины. Лаунчер использует нативный
D-Bus Termux.

### 2.3 Mesa 27 и KGSL

Rootfs должен предоставлять стек Mesa 27 с драйвером KGSL Freedreno.
Соответствующие файлы: `libEGL_mesa.so.0`, `libgallium-27...`, `libLLVM.so.23.1`,
`libxml2.so.16` и `dri/kgsl_dri.so`. Проверьте их:

```sh
ls -l "$ROOTFS/usr/lib/libEGL_mesa.so.0" "$ROOTFS/usr/lib"/libgallium-27* "$ROOTFS/usr/lib/dri/kgsl_dri.so"
```

Лаунчер использует этот стек Mesa 27 из rootfs и отображает его библиотеки
через приватный каталог. Он никогда не использует устаревшую цепочку библиотек
Mesa 24.2.6 из Termux-glibc. Лаунчер также не задаёт `NOCTALIA_GPU`; этот
селектор удалён. Рендеринг опирается на стек Mesa/KGSL из rootfs и приватный
манифест EGL, описанный в разделе 4.

## 3. Архитектура нативного запуска

### 3.1 Обнаружение rootfs

Обнаружение выполняется автоматически. Лаунчер ищет в обеих схемах rootfs:

```sh
find "$PREFIX/var/lib/proot-distro/installed-rootfs" "$PREFIX/var/lib/proot-distro/containers" -path '*/usr/bin/noctalia' -type f 2>/dev/null
```

Для каждого кандидата он требует `usr/bin/noctalia`, `lib/ld-linux-aarch64.so.1`
и `usr/lib/libstdc++.so.6`. Выбирается первый подходящий кандидат. Задайте
`NOCTALIA_ROOTFS` с путём к rootfs, чтобы обойти поиск; переопределение, в
котором отсутствует любой обязательный файл, отклоняется.

Rootfs — только источник бинарников и ресурсов. Лаунчер не вызывает `proot` или
`proot-distro` для запуска Noctalia, и во время выполнения не запускается ни
один процесс rootfs.

### 3.2 Пропатченный нативный бинарник

Лаунчер копирует ELF-файл из rootfs в
`$PREFIX/libexec/mango-termux/noctalia-native` и патчит эту копию с помощью
`patchelf`:

- интерпретатор: `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`;
- RPATH:
  `$PREFIX/libexec/mango-termux/rootfs-libs:$PREFIX/glibc/lib:$ROOTFS/usr/lib:$ROOTFS/lib`;
- дополнительные записи RPATH при наличии:
  `$ROOTFS/usr/lib/aarch64-linux-gnu` и
  `$ROOTFS/lib/aarch64-linux-gnu`;
- запись `NEEDED` `libstdc++.so.6` заменена абсолютным путём к
  `libstdc++.so.6` в rootfs.

Результат — постоянный эквивалент запуска ELF-файла через
`ld-linux --library-path`. Проверьте установленную копию:

```sh
patchelf --print-interpreter "$PREFIX/libexec/mango-termux/noctalia-native"
patchelf --print-rpath "$PREFIX/libexec/mango-termux/noctalia-native"
```

Прямое выполнение через загрузчик rootfs не используется. Android seccomp
убивает запуск Arch glibc сигналом `SIGSYS` на `set_robust_list`. Пропатченная
копия использует загрузчик glibc из Termux и также переживает self-reexec
Noctalia.

Приватная копия кэшируется. Она пересобирается, когда бинарник `noctalia` в
rootfs, `libstdc++.so.6` в rootfs, загрузчик Termux или обёртка `mango-noctalia`
новее кэшированного бинарника, либо когда меняется выбранный rootfs.

Noctalia 5.4.1 — единый ELF-файл. Отдельного процесса quickshell, `qs` или QML
нет, и у бинарника нет библиотек Qt в `NEEDED`. Поэтому лаунчер запускает один
процесс, `noctalia-native`, а не дерево среды выполнения QML.

### 3.3 Окружение выполнения

Когда нативная копия готова, лаунчер выполняет её в контролируемом окружении.
Прочитайте окружение работающего процесса:

```sh
pid=$(pgrep -f 'libexec/mango-termux/noctalia-native' | head -1)
tr '\0' '\n' < "/proc/$pid/environ" | grep -E '^(HOME|PREFIX|PATH|SHELL|XDG_|WAYLAND|DBUS|MANGO|LD_|__EGL|VK_|LIBGL|GBM)'
```

Лаунчер подключает `$PREFIX/tmp/mango-session.env`, если он существует, поэтому
значения Wayland, D-Bus, GPU и сессии от `mango-termux` доступны. Затем он
вызывает `clear_foreign_env`, который удаляет переменные `LD_*`, Mesa, EGL,
Vulkan и `PROOT_*`, и применяет приватные пути rootfs.

`LD_LIBRARY_PATH` и `LD_PRELOAD` не экспортируются. Noctalia находит свои
библиотеки через пропатченный RPATH и приватные символические ссылки rootfs.
Лаунчер также не запускает процесс proot, поэтому в окружении Noctalia нет
переменных `PROOT_*`.

Нативные дочерние процессы наследуют `HOME`, `PREFIX`,
`PATH=$PREFIX/bin:/system/bin:/system/xbin`, `SHELL=$PREFIX/bin/fish` с запасным
вариантом bash, а также нативные пути XDG для конфигурации, состояния и данных.
Дочерние процессы Termux (bionic) игнорируют переменные EGL и Vulkan для glibc.

## 4. Графика и ресурсы

### 4.1 Mesa 27 и EGL vendor

Лаунчер записывает приватный манифест EGL vendor в
`$PREFIX/libexec/mango-termux/egl_vendor.d/50_mesa.json`. Его `library_path` —
абсолютный путь к `libEGL_mesa.so.0` в rootfs:

```sh
cat "$PREFIX/libexec/mango-termux/egl_vendor.d/50_mesa.json"
```

`__EGL_VENDOR_LIBRARY_DIRS` указывает на этот приватный каталог. Приватный
каталог `rootfs-libs` также предшествует каталогам Termux glibc в RPATH
Noctalia, поэтому библиотеки Mesa 27 из rootfs имеют приоритет над любой Mesa из
Termux-glibc.

Исходная ошибка была вызвана устаревшей Mesa 24.2.6 из Termux-glibc, которой
требовался `libxml2.so.2`, тогда как текущий rootfs предоставляет только
`libxml2.so.16`. Не создавайте глобальный `libxml2.so.2` и не изменяйте rootfs.
Абсолютный манифест EGL вместе с приватным RPATH устраняют несоответствие без
глобальных изменений.

### 4.2 libxml2 и multiarch

`rootfs-libs` — приватный набор символических ссылок. Он охватывает `libgbm`,
`libgallium`, `libLLVM`, `libxml2.so.16`, `libstdc++`, клиентские и серверные
библиотеки Wayland, `libdrm`, `libexpat` и другие зависимости rootfs,
используемые Noctalia. Проверьте две характерные ссылки:

```sh
readlink -f "$PREFIX/libexec/mango-termux/rootfs-libs/libgbm.so.1"
readlink -f "$PREFIX/libexec/mango-termux/rootfs-libs/libxml2.so.16"
```

Обе должны разрешаться внутри `$ROOTFS`. Лаунчер связывает каждое имя из
`$ROOTFS/usr/lib` или `$ROOTFS/usr/lib/aarch64-linux-gnu`, если файл существует.
Он также добавляет существующие каталоги multiarch в RPATH, поэтому
поддерживается rootfs с раскладкой multiarch в стиле Debian.

Поэтому глобальный `libxml2.so.2` не нужен. Цепочка Mesa из Termux-glibc не
загружается, а `libxml2.so.16` из rootfs разрешается из приватного каталога
раньше путей Termux glibc.

### 4.3 Vulkan и DRI

Лаунчер записывает приватный ICD Vulkan Freedreno, чей `library_path` —
абсолютный путь к `libvulkan_freedreno.so` в rootfs:

```sh
cat "$PREFIX/libexec/mango-termux/vulkan/icd.d/freedreno_icd.aarch64.json"
```

И `VK_ICD_FILENAMES`, и `VK_DRIVER_FILES` указывают на этот манифест.
`LIBGL_DRIVERS_PATH` указывает на `$ROOTFS/usr/lib/dri`, где находится драйвер
KGSL Gallium. `GBM_BACKENDS_PATH` задаётся как `$ROOTFS/usr/lib/gbm`, если этот
каталог существует.

Эти переменные действуют только для процесса Noctalia и его нативных дочерних
процессов. Дочерние процессы Termux (bionic) игнорируют переменные EGL и Vulkan
для glibc.

### 4.4 Замечание о QML и Qt

Текущий лаунчер не задаёт переменные QML или Qt, поскольку в Noctalia 5.4.1 нет
компонента Qt или QML. Нет процесса `quickshell`, `qs` или QML для запуска, и у
ELF-файла нет библиотек Qt в `NEEDED`. Не экспортируются `QML2_IMPORT_PATH`,
`QML_IMPORT_PATH`, `QT_PLUGIN_PATH` или `QT_QPA_PLATFORM_PLUGIN_PATH`.

Если будущая сборка Noctalia или Quickshell будет использовать Qt,
соответствующие значения были бы такими:
`QML2_IMPORT_PATH="$ROOTFS/usr/lib/qt6/qml"`, `QML_IMPORT_PATH` с тем же
значением, `QT_PLUGIN_PATH="$ROOTFS/usr/lib/qt6/plugins"` и
`QT_QPA_PLATFORM_PLUGIN_PATH="$ROOTFS/usr/lib/qt6/plugins/platforms"`. Это
гипотетические значения для будущей сборки, а не переменные, задаваемые текущим
лаунчером.

### 4.5 Шрифты, ресурсы и пути XDG

Нативный лаунчер задаёт пути к ресурсам напрямую. Проверьте соответствующие
присваивания:

```sh
grep -n 'XDG_DATA_DIRS\|XDG_CONFIG_DIRS\|NOCTALIA_ASSETS_DIR\|FONTCONFIG_PATH' "$PREFIX/bin/mango-noctalia"
```

Действующие значения:

- `XDG_DATA_DIRS="$PREFIX/share:$ROOTFS/usr/share"` — сначала нативные
  desktop-записи Termux, затем данные rootfs;
- `XDG_CONFIG_DIRS="$PREFIX/etc/xdg:$ROOTFS/etc/xdg"` — сначала нативная
  конфигурация XDG, затем конфигурация rootfs;
- `NOCTALIA_ASSETS_DIR="$ROOTFS/usr/share/noctalia/assets"` — ресурсы Noctalia;
- `FONTCONFIG_PATH=$PREFIX/etc/fonts` — нативный fontconfig Termux, если этот
  каталог существует.

Noctalia также использует нативные `XDG_CONFIG_HOME=$HOME/.config`,
`XDG_STATE_HOME=$HOME/.local/state` и `XDG_DATA_HOME=$HOME/.local/share`.
Поэтому конфигурация и состояние находятся в домашнем каталоге Termux, а не в
rootfs.

## 5. Интеграция с MangoWM

### 5.1 mango-ipc

MangoWM создаёт IPC-сокет в `$XDG_RUNTIME_DIR/mango-<pid>.sock` и задаёт
`MANGO_INSTANCE_SIGNATURE` внутри собственного процесса. Поскольку Noctalia
запускается MangoWM, она наследует эту переменную и подключает бэкенд рабочих
пространств к `mango-ipc`, а не только к общему протоколу `ext-workspace`.

Покажите сокет:

```sh
ls -l "$PREFIX/tmp"/mango-*.sock
```

`XDG_RUNTIME_DIR` — это `$PREFIX/tmp`, поэтому путь к сокету находится под
префиксом Termux. `MANGO_INSTANCE_SIGNATURE` — наследуемое значение окружения;
это не proot-bind, и оно не зависит от bind-монтирования.

Когда команда оболочки должна обратиться к MangoWM вне контекста автозапуска,
явно экспортируйте подпись:
`MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"`.

### 5.2 Layer-shell и панели

Noctalia использует `wlr-layer-shell` для своих панелей и баров. MangoWM
поддерживает протокол layer-shell, поэтому панели размещаются композитором без
дополнительной конфигурации MangoWM. Для панелей layer-shell не требуется
запись в `mics.conf`, правило вывода или специальная настройка поверхности.

Noctalia — обычный Wayland-клиент вложенного композитора MangoWM. Она не
создаёт второй композитор и не работает внутри proot-тюрьмы.

### 5.3 Автозапуск и привязки клавиш

`~/.config/mango/mics.conf` должен содержать одну строку нативного автозапуска:

```ini
exec=noctalia
```

`mango-integrate` переписывает старую строку `exec=...start-noctalia.sh` в
`exec=noctalia` и заменяет proot-скрипт `start-noctalia.sh` на нативный шим,
выполняющий `$PREFIX/bin/noctalia`. Резервные копии используют суффикс
`.mango-bak`.

Привязки клавиш вызывают нативную команду `noctalia`. Типичные записи включают
`noctalia msg panel-toggle launcher`, `noctalia msg panel-toggle wallpaper` и
команды громкости или яркости. Исполняемый файл `noctalia` на хосте — нативный
лаунчер, а не proot-прокси. Проверьте настроенные привязки:

```sh
grep -n 'noctalia msg' ~/.config/mango/binds.conf
```

## 6. Конфигурация и миграция

### 6.1 Сборка и интеграция

Пересборка устанавливает текущий нативный лаунчер и повторно применяет
интеграции:

```sh
./build-termux.sh
"$PREFIX/bin/mango-integrate" --check
```

`build-termux.sh` устанавливает `mango-noctalia` и запускает `mango-integrate`.
`MANGO_SKIP_INTEGRATIONS=1` пропускает этап интеграции.
`MANGO_SKIP_FIREFOX_FIX=1` передаёт `--no-firefox` помощнику интеграции. На
этапе сборки rootfs необязателен; при следующем запуске MangoWM применяется
интеграция Noctalia, когда rootfs становится доступен.

`mango-integrate --check` работает только на чтение. Он возвращает ноль, когда
обёртки, нативный лаунчер Noctalia, записи Firefox, лаунчер Firefox и записи
терминалов согласованы. Ненулевой результат указывает на отсутствующий элемент.

### 6.2 Конфигурация, состояние и обои

Идемпотентно примените интеграции и проверьте устаревшие корневые пути:

```sh
"$PREFIX/bin/mango-integrate"
grep -R '/root/' ~/.local/state/noctalia ~/.config/noctalia 2>/dev/null || true
```

`mango-integrate` выполняет следующую нативную миграцию:

- устанавливает `$PREFIX/bin/noctalia` как копию `$PREFIX/bin/mango-noctalia`;
- сохраняет существующий старый прокси как `$PREFIX/bin/noctalia.proot-bak`;
- перемещает `root/.config/noctalia`, `root/.local/state/noctalia` и
  `root/.local/share/noctalia` из rootfs в нативные пути `$HOME/...` только
  когда нативный путь ещё не существует;
- копирует отсутствующие файлы из `root/Walls` (в rootfs) в `$HOME/Walls`;
- переписывает `/root/` на нативный домашний каталог в нативных файлах
  `settings.toml` и создаёт резервные копии `.mango-bak`;
- восстанавливает desktop-записи терминалов до прямых `Exec=kitty` или
  `Exec=foot`;
- направляет записи Firefox на `$PREFIX/bin/mango-firefox`;
- удаляет старый мост хоста.

`mango-host-run` и `install-noctalia-host-bridge.sh` больше не устанавливаются.
Для Noctalia нет обёртки или моста.

### 6.3 Ручная проверка лаунчера

Проверьте установленный лаунчер напрямую:

```sh
"$PREFIX/bin/noctalia" --version
```

Ожидаемый вывод — `noctalia v5.4.1`. Команда подготавливает или повторно
использует приватный нативный бинарник и сообщает версию Noctalia. Команды IPC,
такие как `noctalia msg`, требуют работающей сессии и правильных
`XDG_RUNTIME_DIR` и `WAYLAND_DISPLAY`.

## 7. Проверка

### 7.1 Дерево процессов и окружение

Проверьте соответствующие процессы:

```sh
ps -A -o pid,stat,comm,args | grep -E 'mango|noctalia|proot'
```

Ожидаемое дерево — `mango -> dbus-run-session -> noctalia-native`. Этап
`dbus-run-session` появляется, когда сессионная шина не была унаследована.
Процесс `proot` или `proot-distro` отсутствует.

Имя процесса Noctalia — `noctalia-native`. Остановите его командой
`pkill -f 'libexec/mango-termux/noctalia-native'`. Не используйте
`pkill -x noctalia`; точное имя процесса — `noctalia-native`.

Прочитайте `/proc/<pid>/environ` работающего процесса. В нём не должно быть
`LD_LIBRARY_PATH` или `LD_PRELOAD`. Раздел 3.3 показывает запрос окружения.

### 7.2 EGL и рендерер

Перезапустите с логированием и отфильтруйте важные строки:

```sh
mango-termux --restart > "$PREFIX/tmp/mango.log" 2>&1
grep -E 'gl initialized|connected compositor|workspace backend|connected to session bus|fatal|ERR' "$PREFIX/tmp/mango.log"
```

Успешный запуск сообщает `gl initialized EGL`, `connected compositor`,
`workspace backend=mango-ipc` и `connected to session bus`. Отфильтрованный
вывод не должен содержать `fatal` или `ERR`.

Также проверьте, что в журнале нет `eglGetDisplay failed`, запроса
`libxml2.so.2` и предупреждения `/root/Walls`. Рендерер Freedreno указывает на
путь Mesa/KGSL из rootfs; `llvmpipe` указывает на программный запасной вариант,
описанный в разделе 9.6.

### 7.3 IPC и рабочие пространства

При работающей сессии проверьте нативный путь IPC:

```sh
export MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"
mmsg get version
noctalia msg color-scheme-get
noctalia msg workspace-switch next
mmsg get tags X11-1
```

`mmsg get version` подтверждает IPC MangoWM. `noctalia msg color-scheme-get`
возвращает встроенную схему Noctalia. `workspace-switch next` переключает
текущее рабочее пространство, и результат `mmsg get tags X11-1` отражает
изменение.

## 8. Нативные дочерние приложения

### 8.1 Desktop-записи

Noctalia видит и нативные desktop-записи Termux, и записи rootfs через
`XDG_DATA_DIRS`. Проверьте действующие команды терминалов и Firefox:

```sh
grep -H '^Exec=' "$PREFIX/share/applications/kitty.desktop" "$PREFIX/share/applications/foot.desktop" "$PREFIX/share/applications/com.mitchellh.ghostty.desktop" "$PREFIX/share/applications/firefox.desktop"
```

Записи терминалов должны вызывать `kitty`, `foot` или `ghostty` напрямую.
`mango-integrate` восстанавливает записи, которые ранее направлялись через
старый мост хоста. Записи Firefox должны вызывать `$PREFIX/bin/mango-firefox`
напрямую.

Нативные дочерние приложения — процессы Termux (bionic). Они подключаются к
вложенной сессии через `wayland-0` и наследуют окружение нативной сессии.

### 8.2 fish и терминалы

Нативный лаунчер задаёт `SHELL=$PREFIX/bin/fish` и переходит на
`$PREFIX/bin/bash`, если fish не исполняем. Он также задаёт
`PATH=$PREFIX/bin:/system/bin:/system/xbin`. Проверьте активную оболочку и
конфигурацию оболочки терминала:

```sh
printf '%s\n' "$SHELL"
grep -R '^shell' ~/.config/kitty ~/.config/foot 2>/dev/null || true
```

`mango-integrate` создаёт отсутствующие конфигурации терминалов, использующие ту
же оболочку: `~/.config/kitty/kitty.conf`, `~/.config/foot/foot.ini` и
`~/.config/ghostty/config.ghostty`. Когда эти файлы создаются интеграцией,
соответствующий терминал запускается с fish или bash, если fish недоступен.

### 8.3 Firefox

Firefox использует нативную обёртку Termux. Проверьте desktop-запись:

```sh
grep -n 'mango-firefox' "$PREFIX/share/applications/firefox.desktop"
```

Значение `Exec=` должно указывать напрямую на `$PREFIX/bin/mango-firefox`, а не
на proot-мост. Firefox — bionic-приложение и игнорирует переменные EGL и Vulkan
для glibc, используемые Noctalia.

## 9. Устранение неполадок

### 9.1 Noctalia не запускается

Сначала проверьте установленные компоненты:

```sh
"$PREFIX/bin/noctalia" --version
"$PREFIX/bin/mango-integrate" --check
ls -l "$PREFIX/bin/noctalia" "$PREFIX/bin/mango-noctalia" "$PREFIX/libexec/mango-termux/noctalia-native"
```

Частые причины:

- нет пригодного rootfs: установите Arch rootfs с `usr/bin/noctalia` или задайте
  `NOCTALIA_ROOTFS`;
- отсутствует `patchelf`: выполните `pkg install patchelf`;
- отсутствует загрузчик glibc Termux: проверьте
  `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`;
- отсутствует `libstdc++.so.6` в rootfs: rootfs неполон.

Сообщение `noctalia: already running` означает, что существующий экземпляр
Noctalia владеет конечной точкой IPC. Остановите нативный процесс командой
`pkill -f 'libexec/mango-termux/noctalia-native'` и перезапустите сессию.

### 9.2 EGL, libxml2 и eglGetDisplay

Проверьте приватный манифест EGL и ссылку GBM в rootfs:

```sh
cat "$PREFIX/libexec/mango-termux/egl_vendor.d/50_mesa.json"
readlink -f "$PREFIX/libexec/mango-termux/rootfs-libs/libgbm.so.1"
rm -rf "$PREFIX/libexec/mango-termux"
"$PREFIX/bin/noctalia" --version
```

Манифест должен указывать на абсолютный путь к `libEGL_mesa.so.0` в rootfs, а
ссылка GBM должна разрешаться внутри rootfs. Удаление
`$PREFIX/libexec/mango-termux` удаляет кэшированный нативный бинарник,
символические ссылки и манифесты; следующий запуск `noctalia` пересоздаст их.

Не создавайте глобальный `libxml2.so.2` и не изменяйте rootfs. Если журнал
по-прежнему сообщает `eglGetDisplay failed` или запрашивает `libxml2.so.2`,
приватный кэш устарел или в rootfs отсутствует Mesa 27; пересоберите кэш и
проверьте раздел 2.3.

### 9.3 Предупреждение об обоях /root/Walls

Повторно примените нативную миграцию и проверьте результат:

```sh
"$PREFIX/bin/mango-integrate"
grep -R '/root/' ~/.local/state/noctalia ~/.config/noctalia 2>/dev/null || true
ls -l ~/Walls
```

`mango-integrate` копирует отсутствующие обои из `root/Walls` (в rootfs) в
`$HOME/Walls` и переписывает пути `/root/` в нативных файлах `settings.toml`.
Резервные копии используют суффикс `.mango-bak`. Оставшаяся ссылка `/root/`
может означать, что нативная конфигурация не была мигрирована, поскольку
нативный путь уже существовал; проверьте файл и резервную копию вместо удаления
данных rootfs.

### 9.4 mango-ipc не используется

Проверьте, унаследовал ли работающий процесс подпись MangoWM:

```sh
pid=$(pgrep -f 'libexec/mango-termux/noctalia-native' | head -1)
tr '\0' '\n' < "/proc/$pid/environ" | grep MANGO_INSTANCE_SIGNATURE
```

Если переменная отсутствует, Noctalia была запущена вне контекста автозапуска
MangoWM. При ручном запуске сначала экспортируйте
`MANGO_INSTANCE_SIGNATURE="$(ls "$PREFIX/tmp"/mango-*.sock | head -1)"`. При
автозапуске MangoWM предоставляет значение напрямую. `MANGO_INSTANCE_SIGNATURE`
— не proot-bind; это наследуемая переменная окружения.

Строка журнала `workspace backend=ext-workspace` вместо
`workspace backend=mango-ipc` подтверждает, что подпись отсутствовала.

### 9.5 Wayland и D-Bus

Проверьте Wayland-сокет и нативный помощник D-Bus:

```sh
ls -l "$PREFIX/tmp"/wayland-*
command -v dbus-run-session
```

`XDG_RUNTIME_DIR` должен быть `$PREFIX/tmp`, а `WAYLAND_DISPLAY` — `wayland-0`.
Если `DBUS_SESSION_BUS_ADDRESS` уже задана, Noctalia наследует её. Иначе лаунчер
повторно запускает себя под нативным `dbus-run-session` Termux, когда эта
команда существует.

Используйте нативный D-Bus Termux, а не D-Bus Arch. Системные службы D-Bus,
такие как upower, NetworkManager, logind и polkit, недоступны в этой сессии
Termux. Интеграция звука PipeWire и связки ключей Secret Service необязательна и
зависит от отдельных нативных служб.

### 9.6 llvmpipe или чёрный экран

Проверьте устройство KGSL и драйвер KGSL в rootfs:

```sh
ls -l /dev/kgsl-3d0 "$ROOTFS/usr/lib/dri/kgsl_dri.so"
```

Оба должны существовать. Лаунчер не задаёт `NOCTALIA_GPU`; этот селектор
удалён. Рендеринг использует стек Mesa 27 из rootfs и приватный манифест EGL.
Если `/dev/kgsl-3d0` недоступен или в rootfs нет `dri/kgsl_dri.so`, Noctalia не
может использовать KGSL и может перейти на llvmpipe или отрисовать чёрную
поверхность.

### 9.7 Нативные приложения не отображаются

Проверьте, что нативные приложения установлены в Termux:

```sh
command -v kitty foot ghostty firefox
```

Noctalia находит desktop-записи через
`XDG_DATA_DIRS="$PREFIX/share:$ROOTFS/usr/share"`. Отсутствующие приложения
Termux не могут появиться в лаунчере. Если приложения существуют, но их записи
отсутствуют, запустите `mango-integrate`; он восстанавливает записи терминалов и
лаунчер Firefox.

### 9.8 Ручное восстановление

Пересоберите нативную среду выполнения, повторно примените интеграции и
перезапустите:

```sh
rm -rf "$PREFIX/libexec/mango-termux"
"$PREFIX/bin/mango-integrate"
mango-termux --restart
```

Это удаляет кэшированный нативный бинарник, приватные библиотеки, манифест EGL и
ICD Vulkan. Следующий запуск пересоздаст их из обнаруженного rootfs. Не трогайте
rootfs; он остаётся источником ELF-файла и ресурсов.

## 10. Обновление и удаление

### 10.1 Обновление

Обновите пакет в rootfs, повторно примените интеграции и перезапустите:

```sh
proot-distro login archlinuxarm -- pacman -Syu --noconfirm
"$PREFIX/bin/mango-integrate"
mango-termux --restart
```

`proot-distro` используется только для обновления пакета. Перезапуск по-прежнему
запускает Noctalia нативно. Более новый бинарник `noctalia` или
`libstdc++.so.6` в rootfs делает приватную нативную копию недействительной,
поэтому лаунчер пересобирает её перед запуском.

### 10.2 Сброс нативного состояния

Сбросьте нативную конфигурацию и состояние Noctalia, сохранив резервные копии:

```sh
mv ~/.config/noctalia ~/.config/noctalia.bak 2>/dev/null || true
mv ~/.local/state/noctalia ~/.local/state/noctalia.bak 2>/dev/null || true
mango-termux --restart
```

Следующий запуск создаст свежую нативную конфигурацию. Обои в `$HOME/Walls` не
удаляются этим сбросом.

### 10.3 Удаление

Удалите нативный лаунчер и его приватную среду выполнения:

```sh
rm -f "$PREFIX/bin/noctalia" "$PREFIX/bin/mango-noctalia"
rm -rf "$PREFIX/libexec/mango-termux"
```

Затем удалите строку `exec=noctalia` из `~/.config/mango/mics.conf`. Чтобы также
удалить пакет из rootfs, используйте
`proot-distro login archlinuxarm -- pacman -Rns noctalia`.

Не восстанавливайте старый proot-прокси. Файл `$PREFIX/bin/noctalia.proot-bak`,
если он присутствует, — лишь устаревшая резервная копия удалённого прокси.

## 11. Справочник по окружению

Нативный лаунчер и путь автозапуска используют следующие значения. Пути в этом
списке — действующие значения после того, как `mango-noctalia` применит своё
окружение.

- `NOCTALIA_ROOTFS` — необязательное явное переопределение rootfs. Если не
  задано, лаунчер ищет в `installed-rootfs/*` и `containers/*/rootfs`.
- `ROOTFS` — выбранный rootfs для текущей оболочки или сессии руководства; он
  не экспортируется самим лаунчером.
- `HOME` — нативный домашний каталог Termux, обычно
  `/data/data/com.termux/files/home`.
- `PREFIX` — нативный префикс Termux, обычно
  `/data/data/com.termux/files/usr`.
- `PATH` — `$PREFIX/bin:/system/bin:/system/xbin`.
- `SHELL` — `$PREFIX/bin/fish`, с `$PREFIX/bin/bash` в качестве запасного
  варианта.
- `TMPDIR` — `$PREFIX/tmp`.
- `XDG_RUNTIME_DIR` — `$PREFIX/tmp`.
- `WAYLAND_DISPLAY` — `wayland-0` по умолчанию.
- `DISPLAY` — `:0` по умолчанию для вложенных дочерних процессов Xwayland.
- `XDG_CONFIG_HOME` — `$HOME/.config`.
- `XDG_STATE_HOME` — `$HOME/.local/state`.
- `XDG_DATA_HOME` — `$HOME/.local/share`.
- `XDG_DATA_DIRS` — `$PREFIX/share:$ROOTFS/usr/share`, с добавлением любых
  существующих записей.
- `XDG_CONFIG_DIRS` — `$PREFIX/etc/xdg:$ROOTFS/etc/xdg`, с добавлением любых
  существующих записей.
- `NOCTALIA_ASSETS_DIR` — `$ROOTFS/usr/share/noctalia/assets`.
- `FONTCONFIG_PATH` — `$PREFIX/etc/fonts`, если этот каталог существует.
- `__EGL_VENDOR_LIBRARY_DIRS` —
  `$PREFIX/libexec/mango-termux/egl_vendor.d`.
- `VK_ICD_FILENAMES` и `VK_DRIVER_FILES` — абсолютный манифест ICD Freedreno из
  rootfs в `$PREFIX/libexec/mango-termux/vulkan/icd.d`.
- `LIBGL_DRIVERS_PATH` — `$ROOTFS/usr/lib/dri`, если этот каталог существует.
- `GBM_BACKENDS_PATH` — `$ROOTFS/usr/lib/gbm`, если этот каталог существует.
- `DBUS_SESSION_BUS_ADDRESS` — наследуется, если присутствует; иначе нативная
  сессионная шина Termux запускается с `dbus-run-session`.
- `MANGO_INSTANCE_SIGNATURE` — наследуется от MangoWM. Включает бэкенд рабочих
  пространств `mango-ipc`. Он не задаётся лаунчером Noctalia и не является
  proot-bind.
- `MANGO_NOCTALIA_DBUS_WRAPPED` — внутренний флаг, устанавливаемый в `1` во
  время повторного запуска через `dbus-run-session` для предотвращения
  рекурсии.
- `NOCTALIA_GPU` — удалён и не читается. Лаунчер его не задаёт.

Лаунчер очищает `LD_LIBRARY_PATH`, `LD_PRELOAD`,
`MESA_LOADER_DRIVER_OVERRIDE`, `GALLIUM_DRIVER`,
`__EGL_VENDOR_LIBRARY_FILENAMES`, `EGL_PLATFORM`, `FD_KGSL_DMABUF` и все
переменные `PROOT_*`. Он не экспортирует `LD_LIBRARY_PATH` или `LD_PRELOAD`.
Разрешение библиотек опирается на пропатченный RPATH и приватный каталог
`rootfs-libs`.

Переменные QML и Qt не задаются. Текущий бинарник Noctalia 5.4.1 не имеет
компонента Qt или QML. Гипотетические значения в разделе 4.4 относятся только к
будущей сборке Quickshell или Qt.
