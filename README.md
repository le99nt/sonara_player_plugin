при# 🎵 Sonara Player Widget

[🇷🇺 Русский](#-русский) · [🇬🇧 English](#-english)

![Noctalia](https://img.shields.io/badge/Noctalia%20Shell-v5+-6C5CE7)
![Luau](https://img.shields.io/badge/engine-Luau-0060AC)
![API](https://img.shields.io/badge/plugin__api-43-blue)
![Version](https://img.shields.io/badge/version-2.0.0-success)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## 🇷🇺 Русский

Виджет-плеер для верхней панели **Noctalia Shell** (v5+). На панели — обложка и название текущего трека; клик открывает панель с обложкой, названием/артистом, живым анимированным визуализатором и кнопками управления, нарисованными средствами встроенной графической библиотеки `ui.*`.

Работает с любым MPRIS-плеером через встроенный API **`noctalia.mediaPlayer()`** (Firefox, mpv, Strawberry, spotify-player,…) — идеально сочетается с **Niri WM**.

### 💡 Зачем это нужно

Всегда видно, что играет: не нужно открывать плеер, чтобы узнать трек, поставить на паузу или переключить. Позиция проецируется хостом и обновляется каждый кадр.

### ✨ Возможности

- 🖼️ Виджет на панели: **обложка** (`barWidget.setImage`, обложки по http(s) скачиваются автоматически) + название трека, индикатор ⏸
- 🎛️ Панель по клику: обложка 208px (закруглённая, `ui.image`), название, артист, альбом
- 🌊 **Волна в 3 стилях** (`ui.graph`, живая анимация покадрово):
  - **Волнистая** — плавная кривая с заливкой;
  - **Обычная** — тонкая линия;
  - **Уникальная** — та же форма, но жирная линия-«палка» без заливки.
- 📊 **Визуализатор ещё в 2 стилях**: **Спектр** (двухсерийный `ui.graph`) и **Столбики** (анимированные `ui.box`)
- 🔘 **Кнопки в 3 стилях** (нарисованы `ui.row`-поверхностями с `fill`/`radius`/`onClick`/`onHover`):
  - **Material 3 Expressive** — крупные пилюли, play — большой круг;
  - **Классические** — квадратные с немного скруглёнными углами и рамкой;
  - **Круглые** — идеальные окружности.
- ⏩ Слайдер перемотки (`ui.slider` + `onDragEnd`), перемотка ±10 с
- 🔊 Громкость ±5%, 🔀 shuffle, 🔁 loop (None → Track → Playlist)
- 🎨 Цвета — токены палитры Noctalia (`primary`, `surface_container`, …), тема отслеживается живьём

### 📦 Установка

```bash
# Для локальной разработки: подключить источник плагинов
noctalia msg plugins source add local path /путь/к/plugin

# Включить плагин
noctalia msg plugins enable obloble/sonara
```

### 🔑 Зависимости

- **Данные и управление** — MPRIS напрямую через `gdbus` (glib, есть в любой системе) либо встроенный `noctalia.mediaPlayer()` на новых версиях хоста. **Ничего ставить не нужно.**
- Если плеера нет — виджет показывает нейтральную иконку, а панель — пустое состояние.

### ⚙️ Настройки

| Параметр | По умолчанию | Варианты | Описание |
|---|---|---|---|
| Visualizer style | `wave` | wave / spectrum / bars | Стиль визуализатора |
| Visualizer placement | `card` | card / background | Карточкой или полупрозрачным фоном вверху панели |
| Progress bar style | `plain` | plain / wavy / unique | Полоска времени: обычная / волнистая / уникальная (жирнее, ручка-«палочка») |
| Button style | `m3` | m3 / classic / round | Стиль кнопок управления |
| Show cover in the bar | `true` | bool | Обложка на верхней панели |
| Bar title width | 26 | 8–60 | Максимум символов названия на панели |

Все стили — в **Settings → Plugins → Sonara** (применяются при следующем открытии панели).

### 🛠 Как это работает

- **Данные** ([`shared.luau`](shared.luau)): два режима — native `noctalia.mediaPlayer()` (новые хосты) и D-Bus fallback через `gdbus`: `sonara-dbus.sh` находит активный MPRIS-игрок (предпочитает Playing), снимает метаданные/позицию/громкость/shuffle/loop, позиция экстраполируется между опросами (~1 раз/сек).
- **Виджет** ([`widget.luau`](widget.luau)): тик 1000 мс → `shared.refresh()` → `barWidget.setText/setImage/setGlyph`. Клик → `noctalia.togglePanel("obloble/sonara:panel")`.
- **Панель** ([`panel.luau`](panel.luau)): `update()`-тик 120 мс (работает на всех версиях хоста) — анимация волны, экстраполяция позиции, dbus-опрос ~1 раз/сек. Неизменённое дерево диффится бесплатно.
- **Полоска прогресса**: `plain` — прямая с круглой ручкой; `wavy` — анимированная волна из столбиков, заполненных до позиции; `unique` — как plain, но жирнее и с ручкой-«палочкой».
- **Кнопки M3 Expressive**: play — крупный скруглённый квадрат (морф), prev/next — круги, мелкие — пилюли.
- **Управление**: `sonara-act.sh` (play-pause/next/previous/Seek/SetPosition/Volume/Shuffle/LoopStatus) через тот же gdbus.
- **Обложки** ([`shared.luau`](shared.luau)): `file://` пути отдаются сразу; http(s) скачиваются через `noctalia.download` в папку данных плагина и кэшируются по URL.
- **Волна**: значения 0..1 генерируются детерминированной суперпозицией синусов (`shared.waveValues`) и отдаются в `ui.graph` (`values`/`values2`, `lineWidth`, `fillOpacity`). «Столбики» — 24 `ui.box` с анимированной высотой.
- **Кнопки**: три профиля размеров/радиусов/заливок в `panel.luau` (`btnProfile`): m3 — пилюли `radius = h/2`, classic — `radius 6–8` + рамка `outline_variant`, round — круги. Ховер подсвечивает кнопку через `onHover`.

### 📁 Структура

```
sonara/
├── plugin.toml        # Манифест: [[widget]], [[panel]], [[setting]]
├── shared.luau        # mediaPlayer(), обложки, генераторы волны, утилиты (require-модуль)
├── widget.luau        # Виджет на верхней панели
├── panel.luau         # Панель плеера (графика ui.*)
└── translations/en.json
```

### 🧪 Проверка перед установкой

```bash
noctalia plugins lint sonara   # 0 errors, 0 warnings
```

---

## 🇬🇧 English

A media player widget for the **Noctalia Shell** (v5+) top bar. The bar shows the current track's cover and title; a click opens a panel with the cover, title/artist, a live animated visualizer and transport buttons drawn with Noctalia's built-in `ui.*` graphics library.

Works with any MPRIS player through the built-in **`noctalia.mediaPlayer()`** API (Firefox, mpv, Strawberry, spotify-player,…) — a great fit for **Niri WM**.

### ✨ Features

- 🖼️ Bar widget: **cover** (`barWidget.setImage`, http(s) art is downloaded automatically) + track title
- 🎛️ Click panel: 208px rounded cover (`ui.image`), title, artist, album
- 🌊 **Wave in 3 styles** (`ui.graph`, per-frame animation): **Wavy** (filled curve), **Plain** (thin line), **Unique** (same shape, bold stick line, no fill)
- 📊 **Visualizer in 2 more styles**: **Spectrum** (dual-series `ui.graph`) and **Bars** (animated `ui.box` columns)
- 🔘 **Buttons in 3 styles** (drawn as `ui.row` surfaces with `fill`/`radius`/`onClick`/`onHover`): **Material 3 Expressive** pills, **Classic** squares with slightly rounded corners, **Round** circles
- ⏩ Seek slider (`ui.slider` + `onDragEnd`), seek ±10 s
- 🔊 Volume ±5%, 🔀 shuffle, 🔁 loop (None → Track → Playlist)
- 🎨 Colors are palette tokens (`primary`, `surface_container`, …), tracked live

### 📦 Installation

```bash
noctalia msg plugins source add local path /path/to/plugin
noctalia msg plugins enable obloble/sonara
```

### 🔑 Dependencies

- **Data & controls** — MPRIS directly via `gdbus` (glib, present everywhere) or the built-in `noctalia.mediaPlayer()` on newer hosts. **Nothing to install.**
- Without a player the widget shows a neutral icon and the panel shows an empty state.

### ⚙️ Settings

| Option | Default | Choices | Description |
|---|---|---|---|
| Visualizer style | `wavy` | wavy / line / unique / spectrum / bars | Starting wave/visualizer style |
| Button style | `m3` | m3 / classic / round | Starting button style |
| Show cover in the bar | `true` | bool | Album art in the top bar widget |
| Bar title width | 26 | 8–60 | Max title characters in the bar |

Styles can also be switched live in the panel.

### 🛠 How it works

- **Widget** ([`widget.luau`](widget.luau)): 1000 ms tick → `noctalia.mediaPlayer()` → `barWidget.setText/setImage/setGlyph`. Click → `noctalia.togglePanel("obloble/sonara:panel")`.
- **Panel** ([`panel.luau`](panel.luau)): `onOpen` enables `panel.setNeedsFrameTick(true)`; `onFrameTick` polls `noctalia.mediaPlayer()` every frame (cheap, host-projected position) and advances the visualizer phase. Unchanged trees diff for free.
- **Covers** ([`shared.luau`](shared.luau)): `file://` paths resolve immediately; http(s) art is downloaded via `noctalia.download` into the plugin data dir and cached per URL.
- **Wave**: deterministic multi-sine values (`shared.waveValues`) fed to `ui.graph` (`values`/`values2`, `lineWidth`, `fillOpacity`); Bars — 24 `ui.box` columns with animated heights.
- **Buttons**: three size/radius/fill profiles (`btnProfile`): m3 — pills with `radius = h/2`, classic — `radius 6–8` + `outline_variant` border, round — circles. Hover highlight via `onHover`.

### 📁 Structure

```
sonara/
├── plugin.toml        # Manifest: [[widget]], [[panel]], [[setting]]
├── shared.luau        # mediaPlayer(), covers, wave generators, helpers (require module)
├── widget.luau        # Top bar widget
├── panel.luau         # Player panel (ui.* graphics)
└── translations/en.json
```

### 🧪 Pre-install check

```bash
noctalia plugins lint sonara   # 0 errors, 0 warnings
```

---

## 📄 Лицензия / License

MIT © [obloble](https://github.com/le99nt)
