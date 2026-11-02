# Архитектура репозитория и модульная система

Данный документ подробно описывает устройство personal NixOS флейка, принципы изоляции компонентов, сквозное управление темами и масштабирование на различные аппаратные платформы.

---

## 1. Концепция и философия

* **Single Source of Truth (Единый источник истины):** Репозиторий полностью и исчерпывающе описывает состояние всех управляемых компьютеров. Конфигурация системы — чистая функция от файлов этого репозитория.
* **Multi-Host by Design:** Каждая физическая или виртуальная машина вынесена в отдельную директорию `hosts/<hostname>/`. Файл `flake.nix` автоматически обнаруживает новые хосты при появлении директории.
* **Чистый Multi-Arch:** Конфигурация проектируется с расчетом на гетерогенный парк устройств:
  * Архитектура (`x86_64-linux`, `aarch64-linux`) задается **строго на уровне целевого хоста** (`nixpkgs.hostPlatform`).
  * Все общие системные и пользовательские модули (`modules/`) являются на 100% архитектурно-нейтральными.
* **Принцип «Один инструмент — один файл»:** Пакет, его конфигурационные файлы, переменные окружения и хуки активации (`home.activation`) группируются в одном самодостаточном `.nix`-файле.
* **Автоимпорт без ручных списков (`import-tree`):** Добавление новой программы или системной службы сводится к созданию файла в соответствующей поддиректории. Никаких правок `imports = [ ... ]` не требуется.

---

## 2. Структурная схема проекта

```
.
├── flake.nix                       # Точка входа: inputs, mkHost, mkLive, outputs
├── flake.lock                      # Зафиксированные хеши зависимостей
├── .sops.yaml                      # Маршрутизация шифрования Age для secrets/
│
├── hosts/                          # Специфика конкретных машин
│   ├── common.nix                  # Базовый каркас: системные опции, import-tree, sops, disko
│   ├── dev/                        # Виртуальная машина QEMU/KVM (BIOS/GRUB, virtio, virgl Mesa 3.3)
│   │   ├── default.nix             # Системный профиль хоста dev
│   │   └── home.nix                # Пользовательские переопределения (SPICE vdagent, дисплей)
│   └── thinkpad/                   # Рабочий ноутбук Lenovo ThinkPad P1 Gen 2
│       ├── default.nix             # Системный профиль (UEFI, Disko, NVIDIA RTD3, Throttled, zram)
│       └── home.nix                # Пользовательские переопределения (масштаб eDP-1 1.30x, SSH-ключ)
│
├── modules/
│   ├── core/
│   │   └── settings.nix            # Опции systemSettings (username, git, theme, terminal, sops.enable)
│   ├── disko/                      # Декларативные шаблоны разметки накопителей
│   │   ├── btrfs-uefi.nix          # Шаблон GPT + ESP 1G (/boot) + Btrfs субтомы (@, @home, @nix, @log)
│   │   └── btrfs-bios.nix          # Шаблон GPT + bios_grub 1M (EF02) + Btrfs субтомы
│   ├── installer/                  # Модуль сборки загрузочного Live CD образа
│   │   └── default.nix             # Live-десктоп niri/Noctalia, автологин, лаунчер nixos-installer
│   ├── themes/
│   │   └── everforest-warm/        # Сквозная цветовая палитра Everforest Warm
│   ├── packages/                   # Пользовательские derivations (например, qq.nix)
│   ├── data/                       # Статические шаблоны (starship-base.toml, typora css)
│   ├── nixos/
│   │   ├── core/                   # Системные модули NixOS (АВТОИМПОРТ import-tree)
│   │   │   ├── apps.nix            # Общесистемные базовые GUI/CLI утилиты
│   │   │   ├── audio.nix           # PipeWire, WirePlumber, ALSA, Low-latency
│   │   │   ├── boot.nix            # systemd-boot по умолчанию, Plymouth bgrt splash, параметры ядра
│   │   │   ├── docker.nix          # Docker daemon и права пользователя
│   │   │   ├── fonts.nix           # JetBrainsMono Nerd Font, Noto Fonts, Emoji
│   │   │   ├── greeter.nix         # Noctalia Greeter (greetd)
│   │   │   ├── locale.nix          # Локаль, часовой пояс, раскладки клавиатуры
│   │   │   ├── network.nix         # NetworkManager, firewall, mDNS/Avahi
│   │   │   ├── niri.nix            # Композитор niri (системный модуль, polkit, сессия)
│   │   │   ├── nix.nix             # Настройки nix-daemon, flakes, Lix/Nix оптимизации, gc
│   │   │   ├── portals.nix         # xdg-desktop-portal (gnome, gtk)
│   │   │   ├── shells.nix          # Системная регистрация fish и bash
│   │   │   └── user.nix            # Определение пользователя gosha20777 и групп wheel/video/etc
│   │   └── roles/                  # Опциональные классы оборудования (НЕ автоимпортируются)
│   │       ├── laptop.nix          # Ноутбучная роль (power-profiles-daemon, upower, закрытие крышки)
│   │       └── desktop.nix         # Десктопная роль (fstrim, fwupd)
│   └── home/                       # Пользовательские модули Home-Manager (АВТОИМПОРТ import-tree)
│       ├── agents/                 # AI-агенты: oh-my-pi (декларативные config/models/secrets), herdr
│       ├── apps/                   # typora, thunderbird, libreoffice, nemo, kdenlive
│       ├── cli/                    # eza, bat, fzf, zoxide, starship, jq, ripgrep, yazi, gum, btop...
│       ├── desktop/                # niri binds, noctalia shell, wayland-tools, gtk, swayidle, wallpapers
│       ├── dev/                    # git, gh, lazygit, neovim, vscode, c-toolchain
│       ├── shells/                 # fish, bash
│       ├── system/                 # xdg.nix (структура каталогов, закладки, иконки), sops.nix, mimeapps, face
│       └── terminal/               # kitty (шрифты, паддинги, темы, прозрачность)
│
├── installer/                      # Модульный Python-установщик (MVC/MVVM TUI на Rich)
│   ├── main.py                     # CLI точка входа (--execute, --repo, --mock, --log)
│   ├── config.py                   # Константы путей (/mnt, /etc/iso/repo, gosha20777)
│   ├── models.py                   # Dataclasses: DiskInfo, HostInfo, InstallConfig
│   ├── theme.py                    # Everforest Warm цветовые стили для Rich
│   ├── screens.py                  # Экраны мастера (Welcome, Host, Disk, Key, Password, Summary, Done)
│   ├── progress.py                 # Пайплайн с живым стримингом вывода disko и nixos-install
│   ├── services/                   # Системные сервисы (executor, hardware, host, disko, secrets, nixos, repo)
│   └── tests/                      # 32 безопасных юнит-теста на pytest (dry-run/tmpdir)
│
├── secrets/                        # Зашифрованные sops файлы (ChaCha20-Poly1305)
│   ├── common.yaml                 # Общие токены (OpenRouter, Ollama, Exa, Tavily)
│   └── thinkpad.yaml               # Хостовый приватный SSH-ключ id_ed25519 для ThinkPad
│
└── docs/                           # Исчерпывающая инженерная документация
    ├── architecture.md             # Настоящий документ
    ├── disko-and-storage.md        # Разметка Btrfs, Timeshift, своп в RAM, SSD оптимизация
    ├── secrets-sops-age.md         # Руководство по sops-nix, Age и управлению ключами
    ├── hardware-thinkpad.md        # Тонкая настройка ThinkPad P1, NVIDIA RTD3, энергосбережение
    └── installer-live-cd.md        # Архитектура установщика и процесс сборки Live ISO
```

---

## 3. Механизм автоматического импорта (`import-tree`)

В отличие от классических NixOS конфигураций, где каждый новый файл требует добавления в длинный массив `imports = [ ./foo.nix ./bar.nix ];`, в этом репозитории используется **`import-tree`**:

1. **Системный уровень (`hosts/common.nix`):**
   ```nix
   imports = [
     (inputs.import-tree ../modules/nixos/core)
   ];
   ```
   Любой `.nix` файл, помещенный в `modules/nixos/core/`, немедленно становится частью системной конфигурации всех хостов. Если файл содержит `/_` в пути, он игнорируется (соглашение об опт-ауте).
2. **Пользовательский уровень (`hosts/common.nix`):**
   ```nix
   home-manager.sharedModules = [
     (inputs.import-tree ../modules/home)
   ];
   ```
   Любой файл в `modules/home/` автоматически импортируется в окружение пользователя `gosha20777`.
3. **Изолированные роли (`modules/nixos/roles/`):**
   Модули оборудования (`laptop.nix`, `desktop.nix`) сознательно вынесены за пределы дерева `core/`. Хост импортирует их **явно** по необходимости (например, ThinkPad импортирует `roles/laptop.nix`, а виртуальная машина `dev` — нет).

---

## 4. Слой настроек `systemSettings`

Чтобы избавиться от хардкода имени пользователя, email, темы и терминала в десятках разрозненных файлов, создан унифицированный слой опций `modules/core/settings.nix`:

```nix
options.systemSettings = {
  username    = mkOption { type = types.str;  default = "gosha20777"; };
  gitUsername = mkOption { type = types.str;  default = "gosha20777"; };
  gitEmail    = mkOption { type = types.str;  default = "gosha20777@live.ru"; };
  terminal    = mkOption { type = types.str;  default = "kitty"; };
  theme       = mkOption { type = types.str;  default = "everforest-warm"; };
  timeZone    = mkOption { type = types.str;  default = "Europe/Berlin"; };
  location    = mkOption { type = types.str;  default = "Würzburg, Germany"; };
  sops.enable = mkOption { type = types.bool; default = true; };
};
```

### Потребление опций:
* **В NixOS модулях:** через `config.systemSettings.<опция>`.
* **В Home-Manager модулях:** через автоматически проброшенный аргумент `systemSettings.<опция>` (настроен в `hosts/common.nix` через `home-manager.extraSpecialArgs`).
* **В хостах:** любой хост может переопределить любую опцию простой строкой в `hosts/<name>/default.nix`.

---

## 5. Сквозная палитра и темы: Everforest Warm

Визуальный стиль выдержан в единой теплой палитре **Everforest Warm**:
* **Центральный источник:** `modules/themes/everforest-warm/default.nix`.
* **Noctalia Shell:** палитра подмешивается в генератор стилей через `programs.noctalia.customPalettes.EverforestWarm`.
* **GTK:** тема `Everforest-Dark` с набором иконок `Papirus-Dark`, в котором папки окрашены в зеленый акцент (`papirus-folders -C green`).
* **Курсоры:** `graphite-dark` (размер 24).
* **Терминал Kitty:** включение шаблона Noctalia `include = "themes/noctalia.conf"`, полупрозрачный фон `0.92`, шрифт `JetBrainsMono Nerd Font`.
* **TUI Установщик:** модуль `installer/theme.py` полностью повторяет те же HEX-цвета (фон `#2d353b`, зеленый `#a7c080`, терракотовый `#e69875`, бежевый `#d3c6aa`).

---

## 6. Организация каталогов пользователя (XDG User Dirs)

Модуль `modules/home/system/xdg.nix` декларативно формирует структуру домашнего каталога `~`:

* **Стандартные папки XDG:** `Documents`, `Downloads`, `Pictures`, `Videos`, `Music`.
* **Кастомные папки разработчика:**
  * **`~/Projects`** — каталог под проекты и исходный код. Здесь размещается рабочий клон самого репозитория: `~/Projects/nixos-setup`. Папке назначен контекстный FreeDesktop-значок `folder-development`.
  * **`~/Games`** — каталог под игры и префиксы с контекстным значком `folder-games`.
* **Закладки в файловом менеджере:** В `gtk.gtk3.bookmarks` автоматически добавляются все ключевые папки, поэтому в боковой панели Nemo и диалогах выбора файлов они доступны в один клик.
