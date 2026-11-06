--!nonstrict
-- ============================================================================
-- GitHub Notifications — виджет верхней панели ([[widget]] в plugin.toml).
--
-- Компактная иконка GitHub (+ счётчик непрочитанных при их наличии).
-- Периодически (poll_interval_sec) запрашивает /notifications, обновляет
-- state.json (общий с панелью) и перерисовывает себя через barWidget.render.
-- Клик по виджету открывает панель уведомлений.
-- ============================================================================

-- Общий модуль (require, API 22).
local shared = require("./shared.luau")

local inFlight = false

--- Текущий счётчик непрочитанных.
local unreadCount = 0

--- Описание последней ошибки запроса (nil — ошибки нет).
local lastError = nil

--- Токен из настроек ([[setting]] github_token, читается напрямую,
--- чтобы линтер и хост видели использование настройки в entry-файле).
local function getToken()
	return tostring(noctalia.getConfig("github_token") or "")
end

-- ---------------------------------------------------------------------------
-- Отрисовка виджета: компактная иконка brand-github + счётчик.
-- Цвета берутся из активной палитры Noctalia (с fallback'ами).
-- ---------------------------------------------------------------------------

local function renderWidget()
	local accent = noctalia.getColor("primary") or "#89b4fa"
	local fg = noctalia.getColor("on_surface") or "#cdd6f4"

	-- Токен не задан: нейтральная иконка и подсказка в тултипе.
	if getToken() == "" then
		barWidget.render(ui.glyph({ name = "brand-github", size = 13, color = fg }))
		barWidget.setTooltip("GitHub Notifications: set your token in plugin settings")
		return
	end

	-- Ошибка последнего запроса: приглушённая иконка, причина в тултипе.
	if lastError ~= nil then
		barWidget.render(ui.glyph({ name = "brand-github", size = 13, color = fg }))
		barWidget.setTooltip("GitHub Notifications: " .. lastError)
		return
	end

	-- Нормальное состояние: иконка GitHub; при непрочитанных она
	-- подсвечивается цветом темы, рядом выводится счётчик.
	local children = {
		ui.glyph({
			name = "brand-github",
			size = 16,
			color = unreadCount > 0 and accent or fg,
		}),
	}
	if unreadCount > 0 then
		table.insert(children, ui.label({
			text = tostring(unreadCount),
			fontSize = 11,
			color = accent,
		}))
	end

	barWidget.render(ui.row({ gap = 4, align = "center" }, children))

	if unreadCount > 0 then
		barWidget.setTooltip(("GitHub: %d unread notification(s)"):format(unreadCount))
	else
		barWidget.setTooltip("GitHub: no unread notifications")
	end
end

-- ---------------------------------------------------------------------------
-- Периодический опрос GitHub
-- ---------------------------------------------------------------------------

local function refresh()
	if inFlight then
		return
	end

	-- Без токена просто рисуем «пустой» виджет и не дёргаем API.
	if getToken() == "" then
		unreadCount = 0
		renderWidget()
		return
	end

	inFlight = true
	local started = shared.fetch(getToken(), function(ok, unread, read, err)
		inFlight = false
		if not ok then
			lastError = tostring(err)
			noctalia.log("[GitHub] widget fetch failed: " .. lastError)
			renderWidget()
			return
		end
		lastError = nil

		local state = shared.loadState()
		shared.mergeFetched(state, unread, read)
		shared.saveState(state)

		unreadCount = #state.unread
		renderWidget()
		noctalia.log("[GitHub] widget: " .. tostring(unreadCount) .. " unread")
	end)

	if not started then
		inFlight = false
	end
end

-- ---------------------------------------------------------------------------
-- Точка входа виджета: тик + клик
-- ---------------------------------------------------------------------------

function update()
	refresh()
end

--- Клик по виджету открывает панель уведомлений (id "plugin:panel").
function onClick()
	noctalia.togglePanel("obloble/github-notifications:panel")
end

-- ---------------------------------------------------------------------------
-- Инициализация
-- ---------------------------------------------------------------------------
-- Интервал опроса читаем напрямую из настроек ([[setting]] poll_interval_sec).
local pollSec = tonumber(noctalia.getConfig("poll_interval_sec")) or 120
noctalia.setUpdateInterval(pollSec * 1000)

-- Первый рендер — сразу из сохранённого состояния, не дожидаясь сети.
local state = shared.loadState()
unreadCount = #state.unread
renderWidget()

noctalia.log("[GitHub] Виджет загружен (интервал " .. tostring(pollSec) .. " сек)")
