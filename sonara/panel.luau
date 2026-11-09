--!nonstrict
-- ============================================================================
-- Sonara Player Widget — панель плеера ([[panel]] в plugin.toml).
--
-- Вся графика — встроенная декларативная библиотека ui.*:
--   * обложка       — ui.image (локальные file:// пути; http(s) качает
--                     noctalia.download, см. shared.luau);
--   * полоска прогресса в 3 стилях (настройка progress_style):
--       plain   — прямая полоска с круглой ручкой-«кругляшком»;
--       wavy    — анимированная волна из столбиков, заполненных до позиции;
--       unique  — как plain, но чуть жирнее и с ручкой-«палочкой»;
--   * визуализатор в 3 стилях (настройка viz_style): wave / spectrum /
--     bars — и в двух размещениях (viz_placement): card (карточка) или
--     background (полупрозрачным фоном в верхней части панели);
--   * кнопки в 3 стилях (настройка button_style), нарисованы ui.row-
--     поверхностями (fill/radius/onClick/onHover):
--       m3      — Material 3 Expressive-фигуры: круг + крупный скруглённый
--                 квадрат (морф) + пилюли;
--       classic — квадраты с немного скруглёнными углами и рамкой;
--       round   — идеальные круги;
--   * обновление — update() тик 100 мс (noctalia.setUpdateInterval):
--     анимация волны, экстраполяция позиции, dbus-опрос каждый тик
--     (самоподстраивается через guard _dbusBusy).
--
-- Все стили — настройки плагина (Settings → Plugins → Sonara), читаются
-- в onOpen.
-- ============================================================================

local shared = require("./shared.luau")

-- ---------------------------------------------------------------------------
-- Состояние панели
-- ---------------------------------------------------------------------------

local PANEL_TICK_MS = 100 -- тик анимации и dbus-опроса
local VIZ_W = 48 -- точек волны
local BARS_N = 24 -- столбиков визуализатора
local PROG_N = 40 -- столбиков волнистой полоски

local vizStyle = "wave" -- wave | spectrum | bars
local progressStyle = "plain" -- plain | wavy | unique
local btnStyle = "m3" -- m3 | classic | round
local glassEnabled = true -- эффект стекла на фоне панели
local glassBlur = 24 -- сила размытия (softness)
local glassOpacity = 55 -- прозрачность фона, % непрозрачности

local track = nil -- последний снапшот плеера
local phase = 0 -- фаза анимации
local scrubbing = false -- пользователь тянет полоску (зарезервировано)
local hoveredKey = nil -- клавиша кнопки под курсором
local state = { volume = 1.0, shuffle = "Off", loop = "None" }
local coverPath = nil -- разрешённый локальный путь обложки
local coverKey = "" -- artUrl, для которого path актуален

-- ---------------------------------------------------------------------------
-- Ховеры кнопок (именованный обработчик: получает state и key)
-- ---------------------------------------------------------------------------

function onBtnHover(hoverState, key)
	hoveredKey = (hoverState == "true") and key or nil
	render()
end

-- ---------------------------------------------------------------------------
-- Действия (MPRIS напрямую через gdbus / playerctl в native-режиме)
-- ---------------------------------------------------------------------------

local function refreshState()
	shared.queryState(function(fields)
		state = fields
		render()
	end)
end

function onPrev()
	shared.act("previous")
end
function onNext()
	shared.act("next")
end
function onPlayPause()
	shared.act("play-pause")
end
function onShuffle()
	shared.act("shuffle", state.shuffle ~= "On")
	refreshState()
end
function onLoopNext()
	local order = { None = "Track", Track = "Playlist", Playlist = "None" }
	shared.act("loop", order[state.loop] or "Track")
	refreshState()
end


-- ---------------------------------------------------------------------------
-- Кнопки: рисуем ui.row-поверхностями в выбранном стиле
-- ---------------------------------------------------------------------------

--- Профили стилей. kind: "play" | "side" | "small".
--- Формы Material 3 Expressive: play — крупный скруглённый квадрат (морф),
--- side — круги, small — пилюли.
local function btnProfile(kind)
	if btnStyle == "classic" then
		if kind == "play" then
			return { w = 52, h = 52, r = 8, fill = "primary", hover = "primary/0.85", glyph = "on_primary", gs = 24 }
		elseif kind == "side" then
			return { w = 44, h = 44, r = 6, fill = "surface_container", hover = "surface_container_high", glyph = "on_surface", gs = 19, border = "outline_variant", bw = 1 }
		end
		return { w = 32, h = 32, r = 5, fill = "surface_container", hover = "surface_container_high", glyph = "on_surface_variant", gs = 14, border = "outline_variant", bw = 1 }
	end

	if btnStyle == "round" then
		if kind == "play" then
			return { w = 60, h = 60, r = 30, fill = "primary", hover = "primary/0.85", glyph = "on_primary", gs = 26 }
		elseif kind == "side" then
			return { w = 46, h = 46, r = 23, fill = "surface_container_high", hover = "primary/0.25", glyph = "on_surface", gs = 19 }
		end
		return { w = 34, h = 34, r = 17, fill = "surface_container_high", hover = "primary/0.25", glyph = "on_surface_variant", gs = 15 }
	end

	-- "m3" — Material 3 Expressive: play — большой скруглённый квадрат,
	-- side — круги, small — пилюли.
	if kind == "play" then
		return { w = 66, h = 66, r = 22, fill = "primary", hover = "primary/0.85", glyph = "on_primary", gs = 30 }
	elseif kind == "side" then
		return { w = 48, h = 48, r = 24, fill = "primary/0.15", hover = "primary/0.3", glyph = "primary", gs = 21 }
	end
	return { w = 36, h = 26, r = 13, fill = "primary/0.10", hover = "primary/0.25", glyph = "primary", gs = 15 }
end

--- Поверхность-кнопка: ui.row с fill/radius/onClick/onHover и глифом
--- по центру (row центрирует детей по поперечной оси, justify — по главной).
--- Ключ стабильный и не зависит от глифа: при переключении play/pause нода
--- НЕ пересоздаётся (иначе хост проигрывает анимацию появления — визуальный
--- «скачок/приближение» при нажатии паузы и обратно). Глиф обновляется
--- штатно, проп-ом, на существующей ноде.
local function ctrlButton(key, glyphName, kind, tooltip, handler)
	local p = btnProfile(kind)
	local nodeKey = key .. "-btn"
	-- Сравниваем с тем же ключом, что назначен ноде: раньше сравнивали с
	-- коротким именем ("play"), а хост передаёт ключ ноды — подсветка
	-- ховера никогда не срабатывала.
	local fill = (hoveredKey == nodeKey) and p.hover or p.fill
	local props = {
		key = nodeKey,
		width = p.w,
		height = p.h,
		radius = p.r,
		fill = fill,
		align = "center",
		justify = "center",
		onClick = handler,
		onHover = "onBtnHover",
		tooltip = tooltip,
	}
	if p.border then
		props.border = p.border
		props.borderWidth = p.bw or 1
	end
	return ui.row(props, {
		ui.glyph({ name = glyphName, size = p.gs, color = p.glyph }),
	})
end

-- Транспорт: prev — круг, play — фигура стиля, next — круг.
local function transportRow()
	local playGlyph = (track ~= nil and track.playing) and "player-pause" or "player-play"
	return ui.row({ gap = 14, align = "center", justify = "center" }, {
		ctrlButton("prev", "player-track-prev", "side", "Previous", "onPrev"),
		ctrlButton("play", playGlyph, "play", "Play / Pause", "onPlayPause"),
		ctrlButton("next", "player-track-next", "side", "Next", "onNext"),
	})
end

-- Ряд режимов: shuffle/loop.
local function togglesRow()
	return ui.row({ gap = 6, align = "center", justify = "center" }, {
		ctrlButton("shuf", "shuffle", "small", "Shuffle: " .. tostring(state.shuffle), "onShuffle"),
		ctrlButton("loop", "repeat", "small", "Loop: " .. tostring(state.loop), "onLoopNext"),
	})
end

-- ---------------------------------------------------------------------------
-- Полоска прогресса в 3 стилях (настройка progress_style)
-- ---------------------------------------------------------------------------

local PROG_W = 396

--- plain/unique: track + fill + ручка (круглая у plain, «палочка» у unique).
local function straightProgress(frac)
	local thick = (progressStyle == "unique") and 8 or 5 -- unique чуть жирнее
	local rowH = (progressStyle == "unique") and 22 or 14
	local knobW = (progressStyle == "unique") and 5 or 12
	local knobH = (progressStyle == "unique") and 20 or 12
	local fillW = math.floor(frac * (PROG_W - knobW) + 0.5)
	local restW = math.max(0, PROG_W - fillW - knobW)

	return ui.row({ gap = 0, align = "center", width = PROG_W, height = rowH, flexGrow = 1 }, {
		ui.box({
			key = "pb-fill",
			width = fillW,
			height = thick,
			radius = thick / 2,
			fill = "primary",
		}),
		ui.box({
			key = "pb-knob",
			width = knobW,
			height = knobH,
			radius = (progressStyle == "unique") and 2 or knobW / 2, -- палочка vs кругляшок
			fill = "primary",
		}),
		ui.box({
			key = "pb-rest",
			width = restW,
			height = thick,
			radius = thick / 2,
			fill = "surface_container_high",
		}),
	})
end

--- wavy: анимированная волна из столбиков, заполненных до текущей позиции.
local function wavyProgress(frac)
	local gap = 2
	local bw = math.floor((PROG_W - (PROG_N - 1) * gap) / PROG_N)
	local hs = shared.barHeights(phase, track ~= nil and track.playing or false, PROG_N)
	local bars = {}
	for i = 1, PROG_N do
		local filled = (i - 0.5) / PROG_N <= frac
		bars[#bars + 1] = ui.box({
			key = "pw-" .. tostring(i),
			width = bw,
			height = 4 + math.floor(hs[i] * 12 + 0.5),
			radius = 2,
			fill = filled and "primary" or "surface_container_high",
		})
	end
	return ui.row({ gap = gap, align = "end", justify = "center", width = PROG_W, height = 20, flexGrow = 1 }, bars)
end

local function progressBlock()
	local len = (track and track.lenSec) or 0
	local pos = (track and track.posSec) or 0
	local frac = (len > 0) and (pos / len) or 0
	if frac > 1 then
		frac = 1
	end

	local bar
	if progressStyle == "wavy" then
		bar = wavyProgress(frac)
	else
		bar = straightProgress(frac)
	end

	-- Подписи времени: прошедшее слева, остаток справа (раньше было
	-- «0:00  /  3:45» одной строкой по центру). Фиксированная ширина меток
	-- не даёт цифрам «плясать» при тиканье секунд.
	local elapsed = shared.fmtTime(pos)
	local remaining = "-" .. shared.fmtTime(math.max(0, len - pos))
	local sideW = math.max(34, #elapsed * 5)
	return ui.column({ gap = 2, align = "center" }, {
		bar,
		ui.row({ gap = 0, width = PROG_W, height = 14, flexGrow = 1 }, {
			ui.label({
				key = "t-elapsed",
				text = elapsed,
				fontSize = 10,
				color = "on_surface_variant",
				width = sideW,
				textAlign = "start",
			}),
			ui.row({ flexGrow = 1 }, {}),
			ui.label({
				key = "t-remaining",
				text = remaining,
				fontSize = 10,
				color = "on_surface_variant/0.85",
				width = sideW,
				textAlign = "end",
			}),
		}),
	})
end

-- ---------------------------------------------------------------------------
-- Визуализатор: wave / spectrum (ui.graph), bars (ui.box)
-- ---------------------------------------------------------------------------

local function vizGraph()
	local values, values2 = shared.waveValues(vizStyle, phase, track ~= nil and track.playing or false, VIZ_W)
	local lineWidth, fillOpacity = 2.5, 0.25

	local props = {
		values = values,
		color = "primary",
		lineWidth = lineWidth,
		fillOpacity = fillOpacity,
		width = 396,
		height = 88,
		flexGrow = 1,
	}
	if values2 then
		props.values2 = values2
		props.color2 = "tertiary"
		props.fillOpacity = 0.12
	end
	return ui.graph(props)
end

local function vizCard()
	local h = 88
	local inner
	if vizStyle == "bars" then
		local heights = shared.barHeights(phase, track ~= nil and track.playing or false, BARS_N)
		local bars = {}
		for i, v in ipairs(heights) do
			bars[#bars + 1] = ui.box({
				key = "bar-" .. tostring(i),
				width = 9,
				height = math.max(4, math.floor(v * h + 0.5)),
				fill = "primary",
				radius = 4,
				opacity = 0.55 + 0.45 * v,
			})
		end
		inner = ui.row({ gap = 5, align = "end", justify = "center", width = 396, height = h, flexGrow = 1 }, bars)
	else
		inner = vizGraph()
	end
	return ui.row({
		fill = "surface_container/0.5",
		radius = 16,
		border = "primary/0.12",
		borderWidth = 1,
		padding = 10,
		paddingH = 12,
		align = "center",
	}, { inner })
end

-- ---------------------------------------------------------------------------
-- Эффект стекла: полупрозрачный размытый фон панели (ui softness)
-- ---------------------------------------------------------------------------

--- Свойства корневого фона с учётом настроек стекла.
local function rootProps()
	local p = {
		fill = "surface",
		radius = 18,
		padding = 12,
		gap = 12,
	}
	if glassEnabled then
		local alpha = math.max(5, math.min(95, glassOpacity)) / 100
		p.fill = "surface/" .. string.format("%.2f", alpha)
		p.softness = glassBlur
	end
	return p
end

-- ---------------------------------------------------------------------------
-- Обложка, заголовок
-- ---------------------------------------------------------------------------

local function coverNode()
	local size = 208
	-- Рамка-подложка вокруг обложки: аккуратный «паспарту» с тонким
	-- контуром цвета primary. key на рамке — нода стабильна между тиками,
	-- путь изображения обновляется проп-ом без пересоздания.
	if coverPath ~= nil then
		return ui.row({
			key = "cover-frame-" .. coverKey,
			width = size + 12,
			height = size + 12,
			radius = 20,
			fill = "surface_container/0.35",
			border = "primary/0.25",
			borderWidth = 1,
			align = "center",
			justify = "center",
		}, {
			ui.image({
				path = coverPath,
				width = size,
				height = size,
				radius = 14,
				fit = "cover",
			}),
		})
	end
	return ui.row({
		width = size + 12,
		height = size + 12,
		radius = 20,
		fill = "surface_container/0.35",
		border = "primary/0.25",
		borderWidth = 1,
		align = "center",
		justify = "center",
	}, {
		ui.glyph({ name = "music", size = 76, color = "primary/0.7" }),
	})
end

local function trackLabels()
	local title = (track and track.title) or ""
	-- Статус паузы показывают кнопка play/pause и тултип. Раньше к заголовку
	-- добавлялся "  ⏸": текст (а с ним и layout панели) менялся при каждом
	-- нажатии паузы — лишний визуальный скачок.
	local rows = {
		ui.label({
			text = title,
			fontSize = 18,
			fontWeight = "semibold",
			color = "on_surface",
			maxWidth = 420,
			textAlign = "center",
		}),
		ui.label({
			text = (track and track.artist) or "",
			fontSize = 13,
			fontWeight = "medium",
			color = "primary/0.9",
			maxWidth = 420,
			textAlign = "center",
		}),
	}
	if track ~= nil and track.album ~= "" then
		rows[#rows + 1] = ui.label({
			text = track.album,
			fontSize = 11,
			color = "on_surface_variant/0.85",
			maxWidth = 420,
			textAlign = "center",
		})
	end
	return ui.column({ gap = 4, align = "center" }, rows)
end

-- ---------------------------------------------------------------------------
-- Полный рендер (группы: шапка → фон/обложка → текст → прогресс →
-- визуализатор → транспорт → secondary)
-- ---------------------------------------------------------------------------

function render()
	local children = {}

	-- Шапка: логотип, имя плагина, имя плеера.
	children[#children + 1] = ui.row({ gap = 8, align = "center" }, {
		ui.glyph({ name = "playlist", size = 16, color = "primary" }),
		ui.label({ text = "Sonara", fontSize = 14, fontWeight = "semibold", color = "on_surface", flexGrow = 1 }),
		ui.label({
			text = (track ~= nil and track.identity ~= "") and track.identity or "—",
			fontSize = 10,
			color = "on_surface_variant",
		}),
	})

	if track == nil then
		-- Пустое состояние.
		children[#children + 1] = ui.column({ padding = 24, gap = 8, align = "center" }, {
			ui.glyph({ name = "music-off", size = 40, color = "on_surface_variant" }),
			ui.label({ text = "Nothing is playing", fontSize = 13, color = "on_surface", textAlign = "center" }),
			ui.label({
				text = "Sonara reads MPRIS players directly (gdbus).\nStart any media player (firefox, mpv, Riff…).",
				fontSize = 11,
				color = "on_surface_variant",
				textAlign = "center",
			}),
		})
		children[#children + 1] = vizCard()
		children[#children + 1] = transportRow()
		children[#children + 1] = togglesRow()

		panel.render(ui.column(rootProps(), children))
		return
	end

	-- Разрешаем обложку (может докачаться асинхронно и перерисовать).
	if track.artUrl == "" and coverKey ~= "" then
		-- У нового трека обложки нет — сбрасываем старую (раньше висела).
		coverKey = ""
		coverPath = nil
	elseif track.artUrl ~= "" and track.artUrl ~= coverKey then
		coverKey = track.artUrl
		coverPath = nil
		-- Без колбэка: панель перерисовывается каждый кадр/тик, и как только
		-- загрузка завершится (путь попадёт в кэш shared), он придёт отсюда
		-- синхронно. Раньше каждый кадр добавлял новый колбэк в очередь.
		coverPath = shared.coverPath(track)
	end

	local content = {
		ui.row({ gap = 0, align = "center", justify = "center" }, { coverNode() }),
		trackLabels(),
		progressBlock(),
		vizCard(),
	}

	content[#content + 1] = transportRow()
	content[#content + 1] = togglesRow()

	children[#children + 1] = ui.scroll({ flexGrow = 1, gap = 8 }, {
		ui.column({ gap = 8, align = "center" }, content),
	})

	panel.render(ui.column(rootProps(), children))
end

-- ---------------------------------------------------------------------------
-- Тик панели: анимация + чтение данных + периодический dbus-опрос
-- (update() — надёжно на всех версиях хоста, включая 5.4.1)
-- ---------------------------------------------------------------------------

local frameSeq = 0
local lastSeenFrame = 0
local tickCount = 0

function update()
	if frameSeq == lastSeenFrame then
		-- Кадров не было: маленький шаг фазы, но только когда что-то
		-- играет (на паузе волна замирает — как и положено).
		if track == nil or track.playing then
			phase = phase + 0.12
		end
	end
	lastSeenFrame = frameSeq
	tickCount = tickCount + 1

	-- dbus-опрос каждый тик (100 мс → ~10 раз/сек): позиция и статус
	-- обновляются мгновенно. Guard M._dbusBusy в shared не даёт накапливать
	-- процессы: пока предыдущий gdbus-скрипт не завершился, новый не
	-- запускается, так что реальная частота самоподстраивается.
	if shared.mode() == "dbus" then
		shared.refresh(nil)
	end

	track = shared.player()

	-- dbus-режим: volume/shuffle/loop уже в снапшоте — синхронизируем
	-- состояние кнопок (раньше тултипы показывали устаревшие значения).
	if shared.mode() == "dbus" and track ~= nil then
		if track.shuffle ~= nil then
			state.shuffle = track.shuffle
		end
		if track.loop ~= nil then
			state.loop = track.loop
		end
		if track.volume ~= nil then
			state.volume = track.volume
		end
	end

	-- native-режим: периодический опрос состояния (~1 раз в 2 с) — громкость,
	-- shuffle и loop могут меняться снаружи панели (клавиатура, плеер).
	if shared.mode() == "native" and tickCount % 20 == 0 then
		refreshState()
	end

	render()
end

-- ---------------------------------------------------------------------------
-- Жизненный цикл
-- ---------------------------------------------------------------------------

function onOpen(context)
	-- Все стили — настройки плагина (Settings → Plugins → Sonara).
	-- Значения валидируются по белым спискам: мусор в конфиге больше не
	-- проваливается в необработанную ветку рендера.
	local function pick(v, allowed, def)
		for _, s in ipairs(allowed) do
			if v == s then
				return s
			end
		end
		return def
	end
	vizStyle = pick(tostring(noctalia.getConfig("viz_style") or "wave"), { "wave", "spectrum", "bars" }, "wave")
	progressStyle = pick(
		tostring(noctalia.getConfig("progress_style") or "plain"),
		{ "plain", "wavy", "unique" },
		"plain"
	)
	btnStyle = pick(tostring(noctalia.getConfig("button_style") or "m3"), { "m3", "classic", "round" }, "m3")
	glassEnabled = noctalia.getConfig("glass_enabled") ~= false
	glassBlur = tonumber(noctalia.getConfig("glass_blur")) or 24
	glassOpacity = tonumber(noctalia.getConfig("glass_opacity")) or 55

	coverKey = ""
	coverPath = nil
	phase = 0
	frameSeq = 0
	lastSeenFrame = 0
	tickCount = 0
	state = { volume = 1.0, shuffle = "Off", loop = "None" }

	-- Тики панели: update() на границах секунд (данные) + кадры (плавная
	-- волна). На хостах без frame-tick данные всё равно обновляются.
	panel.setWantsSecondTicks(true)
	panel.setNeedsFrameTick(true)
	noctalia.setUpdateInterval(PANEL_TICK_MS)

	-- Настоящий спектр: cava, если установлен; иначе синтетическая волна.
	if shared.startCava() then
		noctalia.log("[Sonara] Настоящий спектр: cava запущен")
	else
		noctalia.log("[Sonara] cava не найден — визуализатор синтетический (pacman -S cava)")
	end

	shared.refresh(function(t)
		track = t
		render()
		refreshState()
	end)
end

function onFrameTick(deltaMs)
	-- Кадровые тики: плавное движение волны + свежие данные каждый кадр
	-- (снапшот плеера дёшев; cava-спектр приходит своим стримом).
	frameSeq = frameSeq + 1
	track = shared.player()
	if track ~= nil and track.playing then
		phase = phase + (tonumber(deltaMs) or 16) / 1000
	end
	render()
end

function onClose()
	shared.stopCava()
end

noctalia.log("[Sonara] Панель загружена (viz: " .. vizStyle
	.. ", progress: " .. progressStyle .. ", buttons: " .. btnStyle .. ")")
