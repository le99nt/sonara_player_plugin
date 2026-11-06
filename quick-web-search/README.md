# 🔎 Quick Web-Search Launcher

[🇷🇺 Русский](#-русский) · [🇬🇧 English](#-english)

![Noctalia](https://img.shields.io/badge/Noctalia%20Shell-v5+-6C5CE7)
![Luau](https://img.shields.io/badge/engine-Luau-0060AC)
![Version](https://img.shields.io/badge/version-1.0.0-success)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## 🇷🇺 Русский

Плагин-провайдер для встроенного лаунчера **Noctalia Shell**: быстрый веб-поиск прямо из меню запуска. Введите `:g`, `:y` или `:gh`, свой запрос — нажмите Enter — ссылка откроется в браузере.

### 💡 Зачем это нужно

Не нужно сначала открывать браузер, потом вкладку, потом набирать запрос. Лаунчер и так открыт — начните вводить:

```
:g как настроить niri          →  Поиск в Google
:y lofi study playlist         →  Поиск на YouTube
:gh niri session lock          →  Поиск на GitHub
```

### ✨ Возможности

- ⚡ Мгновенный поиск в трёх сервисах прямо из лаунчера
- 🔤 Корректная обработка **кириллицы и любых символов** (собственный RFC-совместимый URL-encoder)
- 🎯 Один результат без «мусора» в списке: плагин молчит, пока ввод не начинается с префикса
- 🚀 Открытие через `xdg-open` — работает с любым браузером по умолчанию
- 🪶 Лёгкий: один файл Luau, ноль внешних зависимостей

### 📦 Установка

Требуется **Noctalia Shell v5+** (лаунчер открывается по вашей привязке клавиш, например `Mod+Ctrl+Return` → `noctalia msg panel-toggle launcher`).

```bash
# Подключить источник плагинов
noctalia msg plugins source add obloble git https://github.com/le99nt/noctalia-plugins

# Включить плагин
noctalia msg plugins enable obloble/quick-web-search
```

Для локальной разработки:

```bash
noctalia msg plugins source add local path /путь/к/репозиторию
noctalia msg plugins enable obloble/quick-web-search
```

### 🎮 Использование

| Ввод в лаунчере | Результат | Куда откроет |
|---|---|---|
| `:g как настроить niri` | Поиск в Google: как настроить niri | google.com |
| `:y synthwave mix` | Поиск на YouTube: synthwave mix | youtube.com |
| `:gh fuzzy finder` | Поиск на GitHub: fuzzy finder | github.com |

1. Откройте лаунчер Noctalia
2. Введите префикс, пробел и запрос
3. Нажмите **Enter** — ссылка откроется в браузере, лаунчер закроется сам

> ⚠️ Префикс отделяется **пробелом**: `:g запрос`, а не `:gзапрос`.

### 🛠 Как это работает

```
ввод ":g запрос"
      │
      ▼
onQuery(text)  ── хост Noctalia вызывает при каждом нажатии клавиши
      │
      ├─ префикс не распознан → launcher.setResults(text, {}) — тихо
      │
      └─ префикс ":g " найден
             │
             ▼
        urlencode("запрос")            ← собственный %XX-энкодер
             │
             ▼
        launcher.setResults(...)       ← строка «Поиск в Google: …» с иконкой
             │
        Enter ▼
        onActivate(url)                ← хост передаёт id результата (это URL)
             │
             ▼
        noctalia.runAsync("xdg-open '<url>'")
             │
             └─ браузер открыт, лаунчер закрыт хостом автоматически
```

### 📁 Структура

```
quick-web-search/
├── plugin.toml        # Манифест: метаданные, [[launcher_provider]]
└── init.luau          # Логика провайдера (onQuery / onActivate)
```

### 🧪 Проверка перед установкой

```bash
noctalia plugins lint quick-web-search   # 0 errors, 0 warnings
```

---

## 🇬🇧 English

A launcher provider plugin for the built-in launcher of **Noctalia Shell**: instant web search right from the app launcher. Type `:g`, `:y` or `:gh`, your query, press Enter — and the link opens in your browser.

### 💡 Why you need it

No need to open a browser first, then a new tab, then type your query. The launcher is already open — just start typing:

```
:g how to configure niri       →  Google search
:y lofi study playlist         →  YouTube search
:gh niri session lock          →  GitHub search
```

### ✨ Features

- ⚡ Instant search in three services right from the launcher
- 🔤 Correct handling of **Cyrillic and any characters** (own RFC-compliant URL encoder)
- 🎯 A single clean result: the plugin stays silent until the input starts with a prefix
- 🚀 Opens via `xdg-open` — works with any default browser
- 🪶 Lightweight: one Luau file, zero external dependencies

### 📦 Installation

Requires **Noctalia Shell v5+** (the launcher opens via your keybind, e.g. `Mod+Ctrl+Return` → `noctalia msg panel-toggle launcher`).

```bash
# Add the plugin source
noctalia msg plugins source add obloble git https://github.com/le99nt/noctalia-plugins

# Enable the plugin
noctalia msg plugins enable obloble/quick-web-search
```

For local development:

```bash
noctalia msg plugins source add local path /path/to/repo
noctalia msg plugins enable obloble/quick-web-search
```

### 🎮 Usage

| Launcher input | Result | Opens |
|---|---|---|
| `:g how to configure niri` | Search in Google: how to configure niri | google.com |
| `:y synthwave mix` | Search on YouTube: synthwave mix | youtube.com |
| `:gh fuzzy finder` | Search on GitHub: fuzzy finder | github.com |

1. Open the Noctalia launcher
2. Type a prefix, a space and your query
3. Press **Enter** — the link opens in your browser and the launcher closes itself

> ⚠️ The prefix must be followed by a **space**: `:g query`, not `:gquery`.

### 🛠 How it works

```
input ":g query"
      │
      ▼
onQuery(text)  ── the Noctalia host calls this on every keystroke
      │
      ├─ unrecognized prefix → launcher.setResults(text, {}) — silent
      │
      └─ prefix ":g " matched
             │
             ▼
        urlencode("query")             ← own %XX-encoder
             │
             ▼
        launcher.setResults(...)       ← "Search in Google: …" row with an icon
             │
        Enter ▼
        onActivate(url)                ← the host passes the result id (the URL)
             │
             ▼
        noctalia.runAsync("xdg-open '<url>'")
             │
             └─ browser opened, launcher closed by the host automatically
```

### 📁 Structure

```
quick-web-search/
├── plugin.toml        # Manifest: metadata, [[launcher_provider]]
└── init.luau          # Provider logic (onQuery / onActivate)
```

### 🧪 Pre-install check

```bash
noctalia plugins lint quick-web-search   # 0 errors, 0 warnings
```

---

## 📄 Лицензия / License

MIT © [obloble](https://github.com/le99nt)
