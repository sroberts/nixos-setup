# nixos-setup

Персональный NixOS флейк — единый источник истины (Single Source of Truth) для всех моих компьютеров.  
Репозиторий спроектирован по модульной схеме: добавление новой программы сводится к созданию одного файла, добавление новой машины — к созданию одной папки, а разметка дисков и управление секретами полностью декларативны.

---

## 🌲 Ключевые особенности сборки

* **Тайлинговый оконный композитор Niri:** Быстрый скроллящийся Wayland-композитор с анимациями и кастомными раскладками.
* **Шелл Noctalia (Quickshell v5):** Современный статус-бар, панель уведомлений, интеграция с медиаплеером и системными профилями питания.
* **Сквозная палитра Everforest Warm:** Единая теплая природная тема оформления во всех компонентах: Noctalia, GTK3/4, терминал Kitty, файловый менеджер Nemo, иконки Papirus-Dark (зеленые папки) и TUI-установщик.
* **Декларативная разметка накопителей через Disko:** Отказ от устаревших файлов с UUID разделов. Чистая GPT-разметка, Btrfs с субтомами под Timeshift (`@`, `@home`, `@nix`, `@log`, `@snapshots`), системный ESP на 1 ГБ в `/boot` и `zramSwap` в оперативной памяти (0 байт износа SSD).
* **Безопасные секреты (sops-nix + Age):** Единый персональный мастер-ключ пользователя вместо хрупких хостовых SSH-ключей. Секреты в Git зашифрованы криптографией ChaCha20-Poly1305. Полное отсутствие утечек (Zero-Leak).
* **Автономный Python-установщик (Live CD):** Модульное приложение по паттерну MVC/MVVM с TUI-интерфейсом на Rich в палитре Everforest. Поддерживает dry-run аудит, потоковый вывод команд и сборку полноценного Live ISO.
* **Строгий Multi-Arch:** Архитектура (`x86_64-linux`, `aarch64-linux`) задается исключительно на уровне хоста. Все разделяемые системные и пользовательские модули остаются на 100% архитектурно-нейтральными.

---

## 📁 Структура проекта

```
.
├── flake.nix                       # Точка входа: inputs, mkHost, mkLive, outputs
├── flake.lock                      # Зафиксированные хеши зависимостей
├── .sops.yaml                      # Публичный мастер-ключ Age (&gosha20777) и правила шифрования
│
├── hosts/                          # Конфигурации конкретных компьютеров (автообнаружение)
│   ├── common.nix                  # Общий каркас: системные опции, import-tree, sops, disko
│   ├── dev/                        # Виртуальная машина QEMU/KVM (BIOS/GRUB, virgl Mesa 3.3, Spice)
│   │   ├── default.nix             # Системный профиль хоста dev (disko btrfs-bios)
│   │   └── home.nix                # Пользовательские переопределения (SPICE vdagent)
│   └── thinkpad/                   # Рабочий ноутбук Lenovo ThinkPad P1 Gen 2
│       ├── default.nix             # Системный профиль (UEFI, disko btrfs-uefi, NVIDIA RTD3, Throttled, zram)
│       └── home.nix                # Пользовательские переопределения (масштаб eDP-1 1.30x, SSH-ключ)
│
├── modules/
│   ├── core/
│   │   └── settings.nix            # Опции systemSettings (username, git, theme, terminal, sops.enable)
│   ├── disko/                      # Переиспользуемые шаблоны разметки дисков
│   │   ├── btrfs-uefi.nix          # GPT + 1G ESP (/boot) + Btrfs субтомы (@, @home, @nix, @log, @snapshots)
│   │   └── btrfs-bios.nix          # GPT + 1M bios_grub (EF02) + Btrfs субтомы
│   ├── installer/                  # Модуль Live CD образа (полный рабочий стол, автологин, лаунчер)
│   │   └── default.nix             # nixosConfigurations.live-x86_64
│   ├── themes/
│   │   └── everforest-warm/        # Цветовая палитра темы Everforest Warm
│   ├── packages/                   # Пользовательские derivations (qq.nix)
│   ├── data/                       # Статические конфиги (starship-base.toml, typora css)
│   ├── nixos/
│   │   ├── core/                   # Системные модули NixOS (АВТОИМПОРТ import-tree)
│   │   │   ├── apps.nix            # Общесистемные базовые GUI/CLI программы
│   │   │   ├── audio.nix           # PipeWire, WirePlumber, ALSA
│   │   │   ├── boot.nix            # systemd-boot по умолчанию, Plymouth bgrt, параметры ядра
│   │   │   ├── docker.nix          # Docker daemon и права пользователя
│   │   │   ├── fonts.nix           # JetBrainsMono Nerd Font, Noto Fonts, Emoji
│   │   │   ├── greeter.nix         # Noctalia Greeter (greetd)
│   │   │   ├── locale.nix          # Локаль, часовой пояс, раскладки клавиатуры
│   │   │   ├── network.nix         # NetworkManager, firewall
│   │   │   ├── niri.nix            # Композитор niri (системный модуль, polkit)
│   │   │   ├── nix.nix             # Настройки nix-daemon, flakes, Lix/Nix оптимизации, gc
│   │   │   ├── portals.nix         # xdg-desktop-portal (gnome, gtk)
│   │   │   ├── shells.nix          # Системная регистрация fish и bash
│   │   │   └── user.nix            # Определение пользователя gosha20777
│   │   └── roles/                  # Опциональные классы оборудования (НЕ автоимпортируются)
│   │       ├── laptop.nix          # Ноутбучная роль (power-profiles-daemon, upower, закрытие крышки)
│   │       └── desktop.nix         # Десктопная роль (fstrim, fwupd)
│       ├── agents/                 # AI-агенты: oh-my-pi (декларативные конфиги/секреты), herdr
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
│   ├── models.py                   # Модели данных: DiskInfo, HostInfo, InstallConfig
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
└── docs/                           # Исчерпывающая техническая документация
    ├── architecture.md             # Устройство флейка, import-tree и опции systemSettings
    ├── disko-and-storage.md        # Разметка Btrfs, Timeshift, своп в RAM, SSD оптимизация
    ├── secrets-sops-age.md         # Руководство по sops-nix, Age и управлению ключами
    ├── hardware-thinkpad.md        # Тонкая настройка ThinkPad P1, NVIDIA RTD3, энергосбережение
    └── installer-live-cd.md        # Архитектура установщика и процесс сборки Live ISO
```

---

## ⚙️ Как работает модульная система

1. **Автоимпорт без ручных списков (`import-tree`):**
   * Все системные службы из `modules/nixos/core/` и пользовательские программы из `modules/home/` подхватываются автоматически.
   * **Один инструмент = один файл:** Например, `modules/home/cli/starship.nix` сам подключает пакет, настраивает опции и сидирует файл конфигурации.
2. **Опциональные роли (`modules/nixos/roles/`):**
   * Модули `laptop.nix` и `desktop.nix` **не импортируются** автоматически. Хост подключает их явно в своем `default.nix` при наличии соответствующего «железа».
3. **Параметры `systemSettings` (`modules/core/settings.nix`):**
   * Глобальные параметры (имя пользователя, терминал, тема, git-имя, git-email, активность sops) объявлены в одном месте и доступны везде через `config.systemSettings` (в NixOS) и аргумент `systemSettings` (в Home-Manager).
4. **Автообнаружение хостов:**
   * Каждая поддиректория внутри `hosts/` автоматически становится доступной конфигурацией `nixosConfigurations.<имя>`. Файл `flake.nix` не требует правок при добавлении новых машин.

---

## 💻 Целевые компьютеры (Хосты)

* **`hosts/thinkpad` (Lenovo ThinkPad P1 Gen 2):**
  * Процессор: Intel Core i7-9750H с динамическим аппаратным масштабированием от 800 МГц (Intel EPP `power`, Lenovo `platform_profile = low-power`, служба `throttled`).
  * Графика: Гибридная Intel UHD 630 (отрисовывает интерфейс eDP-1) + NVIDIA Quadro T1000 Turing с технологией **PCIe Runtime D3 (RTD3 / D3Cold)**. В простое видеокарта полностью обесточена (**0 Ватт**), а при необходимости подключается через `nvidia-offload` (утилита `nvidia-smi` доступна всегда).
  * Разметка: Декларативный Btrfs шаблон `btrfs-uefi.nix` с субтомами под Timeshift на NVMe `/dev/nvme0n1`.
  * Дисплей: Встроенный экран 15.6" 1080p с масштабом 1.30x в niri (рассчитан по биометрической формуле).
* **`hosts/dev` (Виртуальная машина QEMU/KVM):**
  * Тестовый полигон. Наследует все общие модули, работает в режиме Legacy BIOS через шаблон `btrfs-bios.nix` на диске `/dev/vda`, виртуальный драйвер Mesa 3.3 и агент SPICE vdagent.
* **`live-x86_64` (Загрузочный образ Live CD):**
  * Полнофункциональный Live-дистрибутив для тестирования системы перед установкой. Загружается сразу в графический рабочий стол Niri/Noctalia с автологином, сетевым менеджером, консольным лаунчером `nixos-installer` и встроенным TUI-мастером установки.

---

## 🔐 Безопасность и секреты (sops-nix + Age)

В репозитории реализована модель **Single User Age Key**:
* Приватный мастер-ключ хранится строго локально на доверенных машинах по пути `~/.config/sops/age/keys.txt` с правами `0600` и **никогда не попадает в Git** (внесен в `.gitignore`).
* В корне репозитория в `.sops.yaml` зафиксирован только публичный ключ `&gosha20777` (`age1...`), предназначенный исключительно для запечатывания данных.
* Резервная копия мастер-ключа хранится в Google Password Manager (Chrome) с двухфакторной аутентификацией (2FA) в записи `age-key.local`.
* При переустановке системы репозиторий Git **не требует перешифрования**: достаточно ввести ключ в мастере установки или положить в `~/.config/sops/age/keys.txt`.

---

## 🛠️ Повседневные команды

Все операции выполняются через Flake-команды из корня репозитория:

```bash
# === Рекомендуемый способ через Nix Helper (nh) ===
# Собрать и применить изменения (автоматически определяет хост и выводит diff пакетов):
nh os switch

# Протестировать изменения без добавления в загрузочное меню:
nh os test

# Собрать конфигурацию для следующей загрузки:
nh os boot

# Очистить старые поколения (оставить ровно 3 последних системных и пользовательских):
nh clean all --keep 3

# === Классический способ через nixos-rebuild ===
# Применить изменения конфигурации к текущей машине:
sudo nixos-rebuild switch --flake .#<host>

# Откатить последнее переключение назад:
sudo nixos-rebuild --rollback switch

# === Обслуживание Flake и тесты ===
# Обновить все зависимости флейка (обновит flake.lock):
nix flake update

# Проверить синтаксис и отформатировать все .nix файлы (nixfmt):
nix fmt .

# Запустить 32 юнит-теста установщика (быстро, в изолированном tmpdir):
nix shell nixpkgs#python3Packages.pytest nixpkgs#python3Packages.rich -c pytest installer/tests/ -q

# Запустить TUI-установщик в безопасном режиме симуляции (Dry-Run):
nix shell nixpkgs#python3Packages.rich -c python3 installer/main.py --mock

# Собрать загрузочный Live CD ISO-образ:
nix build "path:.#nixosConfigurations.live-x86_64.config.system.build.isoImage" -o result-iso

```

---

## 📚 Подробная документация в каталоге `docs/`

* **`docs/architecture.md`** — Модульная архитектура, устройство `flake.nix`, механизм `import-tree`, слой параметров `systemSettings` и стандарт каталогов XDG.
* **`docs/disko-and-storage.md`** — Руководство по разметке Disko, субтомам Btrfs (`@`, `@home`, `@nix`), совместимости с Timeshift, тонким настройкам NVMe SSD и `zramSwap`.
* **`docs/secrets-sops-age.md`** — Исчерпывающий runbook по управлению секретами через `sops-nix`, правила шифрования, восстановление ключей и защита от утечек.
* **`docs/hardware-thinkpad.md`** — Аппаратное включение ThinkPad P1 Gen 2: гибридная графика NVIDIA Turing RTD3 (D3Cold 0W), PRIME offload, `throttled`, Intel Speed Shift и профили питания.
* **`docs/installer-live-cd.md`** — Архитектура модульного Python-установщика (MVC/MVVM), стриминг логов, тестирование и пошаговая установка с флешки.
* **`docs/dictation.md`** — Голосовая диктовка `noctalia-dictation`: пайплайн Whisper → refine-LLM → wtype, самообучение на исправлениях (PRIMARY-выделение, similarity-guard, Agentic Core Memory), уведомления и IPC.
* **`secure-boot.md`** — Пошаговое руководство по включению Secure Boot через `lanzaboote` и `sbctl` (выполняется строго после первой успешной загрузки системы).
* **`display-scaling.md`** — Математическая биометрическая модель расчета масштабирования интерфейса и шрифтов под индивидуальные параметры зрения.
* **`CONTRIBUTING.md`** — Правила работы с ветками, пул-реквестами и критерии проверок перед слиянием.
