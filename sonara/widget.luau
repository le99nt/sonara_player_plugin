--!nonstrict
-- ============================================================================
-- Sonara Player Widget — виджет верхней панели ([[widget]] в plugin.toml).
--
-- По умолчанию: обложка трека (barWidget.setImage, если получилось получить
-- локальный файл; иначе глиф-нота) + название трека. Клик открывает панель.
--
-- Данные: shared.refresh() — native noctalia.mediaPlayer(), либо D-Bus
-- fallback через gdbus (Noctalia 5.4.1). Обложки по http(s) скачиваются
-- noctalia.download (shared.luau). Тик 1000 мс.
-- ============================================================================

local shared = require("./shared.luau")

local showArt = noctalia.getConfig("show_art_in_bar") ~= false
local maxW = tonumber(noctalia.getConfig("bar_title_width")) or 26

-- Последние установленные значения: barWidget не дёргается одинаковыми
-- данными каждый тик (раньше setImage/setTooltip шли каждую секунду,
-- что могло вызывать мерцание обложки и текста).
local lastText, lastTooltip, lastImage, lastGlyph

local function setText(t)
	if t ~= lastText then
		lastText = t
		barWidget.setText(t)
	end
end

local function setTooltip(t)
	if t ~= lastTooltip then
		lastTooltip = t
		barWidget.setTooltip(t)
	end
end

local function setImage(p)
	if p ~= nil and p ~= lastImage then
		lastImage = p
		lastGlyph = nil
		barWidget.setImage(p)
	end
end

local function setGlyph(g)
	if g ~= lastGlyph then
		lastGlyph = g
		lastImage = nil
		barWidget.setGlyph(g)
	end
end

local function renderBar(track)
	if track == nil then
		setGlyph("music-off")
		setText("")
		setTooltip("Sonara: ничего не играет")
		return
	end

	setText(shared.trunc(track.title, maxW))

	if showArt and track.artUrl ~= "" then
		local path = shared.coverPath(track, function(p)
			if p then
				setImage(p)
			end
		end)
		if path then
			setImage(path)
		else
			setGlyph("music")
		end
	else
		setGlyph("music")
	end

	setTooltip(string.format(
		"Sonara: %s — %s%s",
		track.title,
		track.artist,
		track.playing and "  ▶" or "  ⏸"
	))
end

function update()
	shared.refresh(function(track)
		renderBar(track)
	end)
end

function onClick()
	noctalia.togglePanel("obloble/sonara:panel")
end

noctalia.setUpdateInterval(1000)

shared.refresh(function(track)
	renderBar(track)
end)

noctalia.log("[Sonara] Виджет загружен")
