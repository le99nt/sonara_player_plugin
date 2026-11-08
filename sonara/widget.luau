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

local function renderBar(track)
	if track == nil then
		barWidget.setGlyph("music-off")
		barWidget.setText("")
		barWidget.setTooltip("Sonara: ничего не играет")
		return
	end

	barWidget.setText(shared.trunc(track.title, maxW))

	if showArt and track.artUrl ~= "" then
		local path = shared.coverPath(track, function(p)
			if p then
				barWidget.setImage(p)
			end
		end)
		if path then
			barWidget.setImage(path)
		else
			barWidget.setGlyph("music")
		end
	else
		barWidget.setGlyph("music")
	end

	barWidget.setTooltip(string.format(
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
