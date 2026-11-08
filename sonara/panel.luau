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
--   * обновление — update() тик 120 мс (noctalia.setUpdateInterval):
--     анимация волны, экстраполяция позиции, dbus-опрос ~1 раз/сек.
--
-- Все стили — настройки плагина (Settings → Plugins → Sonara), читаются
-- в onOpen.
-- ============================================================================

local shared = require("./shared.luau")

-- ---------------------------------------------------------------------------
-- Состояние панели
-- ---------------------------------------------------------------------------

local PANEL_TICK_MS = 120 -- тик анимации
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
local function ctrlButton(key, glyphName, kind, tooltip, handler)
	local p = btnProfile(kind)
	local fill = (hoveredKey == key) and p.hover or p.fill
	local props = {
		key = key .. "-" .. glyphName, -- ключ зависит от глифа: play/pause обновляется
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
	local hs = shared.barHeights(phase, true, PROG_N)
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

	return ui.column({ gap = 2, align = "center" }, {
		bar,
		ui.label({
			text = shared.fmtTime(pos) .. "  /  " .. shared.fmtTime(len),
			fontSize = 10,
			color = "on_surface_variant",
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

local function vizBars()
	local heights = shared.barHeights(phase, track ~= nil and track.playing or false, BARS_N)
	local bars = {}
	for i, v in ipairs(heights) do
		table.insert(bars, ui.box({
			key = "bar-" .. tostring(i),
			width = 9,
			height = math.max(4, math.floor(v * 88 + 0.5)),
			fill = "primary",
			radius = 4,
			opacity = 0.55 + 0.45 * v,
		}))
	end
	return ui.row({ gap = 5, align = "end", justify = "center", width = 396, height = 88, flexGrow = 1 }, bars)
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
		radius = 14,
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
		gap = 10,
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
	if coverPath ~= nil then
		return ui.image({
			key = "cover-" .. coverKey,
			path = coverPath,
			width = size,
			height = size,
			radius = 16,
			fit = "cover",
		})
	end
	return ui.row({
		width = size,
		height = size,
		radius = 16,
		fill = "surface_container",
		align = "center",
		justify = "center",
	}, {
		ui.glyph({ name = "music", size = 76, color = "primary/0.7" }),
	})
end

local function trackLabels()
	local title = (track and track.title) or ""
	if track and not track.playing then
		title = title .. "  ⏸"
	end
	local rows = {
		ui.label({
			text = title,
			fontSize = 17,
			fontWeight = "semibold",
			color = "on_surface",
			maxWidth = 420,
			textAlign = "center",
		}),
		ui.label({
			text = (track and track.artist) or "",
			fontSize = 13,
			color = "primary",
			maxWidth = 420,
			textAlign = "center",
		}),
	}
	if track ~= nil and track.album ~= "" then
		rows[#rows + 1] = ui.label({
			text = track.album,
			fontSize = 11,
			color = "on_surface_variant",
			maxWidth = 420,
			textAlign = "center",
		})
	end
	return ui.column({ gap = 3, align = "center" }, rows)
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
	if track.artUrl ~= "" and track.artUrl ~= coverKey then
		coverKey = track.artUrl
		coverPath = nil
		coverPath = shared.coverPath(track, function(p)
			if p then
				coverPath = p
				render()
			end
		end)
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

-- Фаза анимации: двигает onFrameTick (плавно). Если кадровые тики на хосте
-- не идут, update() подкрашивает фазу маленьким шагом — без рывков.
-- Фаза анимации: плавно двигает onFrameTick. Если кадровые тики на хосте
-- не приходят, update() подкрашивает фазу маленьким шагом — без рывков.
local frameSeq = 0
local lastSeenFrame = 0

function update()
	if frameSeq == lastSeenFrame then
		phase = phase + 0.12 -- кадров не было: маленький шаг
	end
	lastSeenFrame = frameSeq

	-- dbus-опрос ~1 раз/сек.
	if shared.mode() == "dbus" then
		shared.refresh(nil)
	end

	track = shared.player()
	render()
end

-- ---------------------------------------------------------------------------
-- Жизненный цикл
-- ---------------------------------------------------------------------------

function onOpen(context)
	-- Все стили — настройки плагина (Settings → Plugins → Sonara).
	vizStyle = tostring(noctalia.getConfig("viz_style") or "wave")
	progressStyle = tostring(noctalia.getConfig("progress_style") or "plain")
	btnStyle = tostring(noctalia.getConfig("button_style") or "m3")
	glassEnabled = noctalia.getConfig("glass_enabled") ~= false
	glassBlur = tonumber(noctalia.getConfig("glass_blur")) or 24
	glassOpacity = tonumber(noctalia.getConfig("glass_opacity")) or 55

	coverKey = ""
	coverPath = nil
	phase = 0
	frameSeq = 0
	lastSeenFrame = 0

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
