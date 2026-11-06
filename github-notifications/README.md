# 🔔 GitHub Notifications

[🇷🇺 Русский](#-русский) · [🇬🇧 English](#-english)

![Noctalia](https://img.shields.io/badge/Noctalia%20Shell-v5+-6C5CE7)
![Luau](https://img.shields.io/badge/engine-Luau-0060AC)
![Version](https://img.shields.io/badge/version-1.0.0-success)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## 🇷🇺 Русский

Виджет для верхней панели **Noctalia Shell**: счётчик непрочитанных уведомлений GitHub в виде колокольчика и панель со списком уведомлений и историей.

### 💡 Зачем это нужно

Не открывайте GitHub «на всякий случай» — виджет покажет колокольчик со счётчиком, как только появятся новые уведомления. Клик — и перед вами весь список: кто, куда и когда упомянул вас.

### ✨ Возможности

- 🔔 Колокольчик на панели с счётчиком непрочитанных (подсвечивается при наличии новых)
- 📋 Панель с двумя вкладками: **Unread** (непрочитанные) и **History** (история прочитанных, до 50 записей)
- ✔️ Отметка «прочитано»: по одному (кнопка ✓) или все сразу
- 🔄 Обновление по клику + фоновый опрос каждые 2 минуты (настраивается)
- 🔗 Открытие уведомления на github.com (issue, PR, release — иконка по типу)
- 🧠 История хранится локально в папке данных плагина и переживает перезагрузки
- 🎨 Иконки и цвета подстраиваются под тему Noctalia

### 📦 Установка

```bash
# Подключить источник плагинов
noctalia msg plugins source add github-notifications git https://github.com/le99nt/github_notifications_plugin

# Включить плагин
noctalia msg plugins enable obloble/github-notifications
```

Для локальной разработки:

```bash
noctalia msg plugins source add local path /путь/к/репозиторию
noctalia msg plugins enable obloble/github-notifications
```

### 🔑 Требуется токен GitHub

1. Откройте [github.com/settings/tokens](https://github.com/settings/tokens)
2. Создайте **classic token** со скоупом **`notifications`** (достаточно только его)
3. Вставьте токен в **Настройки → Плагины → GitHub Notifications → GitHub personal access token**

Без токена виджет показывает серый колокольчик, а панель — инструкцию с кнопкой перехода в настройки.

### ⚙️ Настройки

| Параметр | По умолчанию | Диапазон | Описание |
|---|---|---|---|
| GitHub token | — | — | Classic PAT со скоупом `notifications` |
| Интервал опроса | 120 сек | 60–600 сек | Частота проверки. API уведомлений ограничен ~50 запросами/час |

### 🛠 Как это работает

- **Виджет** (`widget.luau`): тик каждые `poll_interval_sec` → `GET /notifications` через `noctalia.http` → обновление `state.json` в папке данных плагина → отрисовка `barWidget.setGlyph/setText/setColor`.
- **Панель** (`panel.luau`): при открытии (`onOpen`) читает `state.json`, рисует список через `panel.render(ui-дерево)`, может сама выполнять запросы (обновить / отметить прочитанным / отметить все).
- `state.json` — «мост» между виджетом и панелью, которые являются отдельными runtime'ами.
- История пополняется автоматически: прочитанные уведомления попадают в неё без дублей, лимит — 50 записей.

### 📁 Структура

```
github-notifications/
├── plugin.toml        # Манифест: [[widget]], [[panel]], [[setting]]
├── shared.luau        # GitHub API, история, утилиты (require-модуль)
├── widget.luau        # Виджет-колокольчик на панели
├── panel.luau         # Панель уведомлений и истории
└── translations/en.json
```

### 🧪 Проверка перед установкой

```bash
noctalia plugins lint github-notifications   # 0 errors, 0 warnings
```

---

## 🇬🇧 English

A bar widget for **Noctalia Shell**: a GitHub unread-notifications bell with a counter and a panel with the notification list and history.

### 💡 Why you need it

Stop opening GitHub "just in case" — the widget shows a bell with a counter as soon as new notifications arrive. One click, and you see everything: who mentioned you, where and when.

### ✨ Features

- 🔔 Bar bell widget with an unread counter (highlighted when there are new items)
- 📋 Panel with two tabs: **Unread** and **History** (up to 50 read items)
- ✔️ Mark as read: one by one (✓ button) or all at once
- 🔄 Manual refresh + background polling every 2 minutes (configurable)
- 🔗 Open a notification on github.com (issue, PR, release — icon by type)
- 🧠 History persists locally in the plugin data dir across reloads
- 🎨 Icons and colors follow the Noctalia theme palette

### 📦 Installation

```bash
# Add the plugin source
noctalia msg plugins source add github-notifications git https://github.com/le99nt/github_notifications_plugin

# Enable the plugin
noctalia msg plugins enable obloble/github-notifications
```

For local development:

```bash
noctalia msg plugins source add local path /path/to/repo
noctalia msg plugins enable obloble/github-notifications
```

### 🔑 Requires a GitHub token

1. Open [github.com/settings/tokens](https://github.com/settings/tokens)
2. Create a **classic token** with the **`notifications`** scope (that one is enough)
3. Paste it in **Settings → Plugins → GitHub Notifications → GitHub personal access token**

Without a token the widget shows a dimmed bell, and the panel shows instructions with a button to open plugin settings.

### ⚙️ Settings

| Option | Default | Range | Description |
|---|---|---|---|
| GitHub token | — | — | Classic PAT with the `notifications` scope |
| Poll interval | 120 s | 60–600 s | How often to check. The notifications API is limited to ~50 requests/hour |

### 🛠 How it works

- **Widget** (`widget.luau`): ticks every `poll_interval_sec` → `GET /notifications` via `noctalia.http` → updates `state.json` in the plugin data dir → redraws itself with `barWidget.setGlyph/setText/setColor`.
- **Panel** (`panel.luau`): on open (`onOpen`) reads `state.json`, renders the list via `panel.render(ui tree)`, and can perform its own requests (refresh / mark read / mark all).
- `state.json` is the "bridge" between the widget and the panel, which run in separate runtimes.
- History grows automatically: read notifications are deduplicated and appended, capped at 50 entries.

### 📁 Structure

```
github-notifications/
├── plugin.toml        # Manifest: [[widget]], [[panel]], [[setting]]
├── shared.luau        # GitHub API, history, helpers (require module)
├── widget.luau        # Bar bell widget
├── panel.luau         # Notifications & history panel
└── translations/en.json
```

### 🧪 Pre-install check

```bash
noctalia plugins lint github-notifications   # 0 errors, 0 warnings
```

---

## 📄 Лицензия / License

MIT © [obloble](https://github.com/le99nt)
