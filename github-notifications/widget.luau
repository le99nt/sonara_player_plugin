--!nonstrict
-- ============================================================================
-- GitHub Notifications — виджет верхней панели ([[widget]] в plugin.toml).
--
-- Колокольчик + счётчик непрочитанных уведомлений GitHub.
-- Периодически (poll_interval_sec) запрашивает /notifications, обновляет
-- state.json (общий с панелью) и перерисовывает себя через barWidget.*.
-- Клик по виджету открывает панель уведомлений.
-- ============================================================================

-- Общий модуль (require, API 22).
local shared = require("shared.luau")

local inFlight = false

--- Токен из настроек ([[setting]] github_token, читается напрямую,
--- чтобы линтер и хост видели использование настройки в entry-файле).
local function getToken()
	return tostring(noctalia.getConfig("github_token") or "")
end

--- Текущий счётчик непрочитанных (для тултипа/логики).
local unreadCount = 0

-- ---------------------------------------------------------------------------
-- Отрисовка виджета
-- ---------------------------------------------------------------------------

local function renderIcon()
	if getToken() == "" then
		-- Токен не задан: серый колокольчик и подсказка в тултипе.
		barWidget.setGlyph("bell-off")
		barWidget.setText("")
		barWidget.setColor("on_surface")
		barWidget.setTooltip("GitHub Notifications: set your token in plugin settings")
		return
	end

	barWidget.setGlyph("bell")
	if unreadCount > 0 then
		barWidget.setText(tostring(unreadCount))
		barWidget.setColor("primary")
		barWidget.setTooltip(("GitHub: %d unread notification(s)"):format(unreadCount))
	else
		barWidget.setText("")
		barWidget.setColor("on_surface")
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
		renderIcon()
		return
	end

	inFlight = true
	local started = shared.fetch(getToken(), function(ok, unread, read, err)
		inFlight = false
		if not ok then
			noctalia.log("[GitHub] widget fetch failed: " .. tostring(err))
			barWidget.setGlyph("bell-off")
			barWidget.setText("")
			barWidget.setTooltip("GitHub Notifications: fetch failed (" .. tostring(err) .. ")")
			return
		end

		local state = shared.loadState()
		shared.mergeFetched(state, unread, read)
		shared.saveState(state)

		unreadCount = #state.unread
		renderIcon()
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
renderIcon()

noctalia.log("[GitHub] Виджет загружен (интервал " .. tostring(pollSec) .. " сек)")
