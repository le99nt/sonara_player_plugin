--!nonstrict
-- ============================================================================
-- GitHub Notifications — панель ([[panel]] в plugin.toml).
--
-- Открывается по клику на виджет. Показывает список непрочитанных
-- уведомлений и историю прочитанных. Возможности:
--   * обновить список (fetch /notifications);
--   * отметить одно уведомление прочитанным (PATCH threads/{id});
--   * отметить все прочитанными (PUT /notifications);
--   * открыть уведомление на github.com (xdg-open);
--   * переключение вкладок Unread / History.
--
-- Жизненный цикл панели: хост вызывает onOpen(context) при открытии и
-- onClose() при закрытии. Содержимое рисуется через panel.render(ui-дерево).
-- ============================================================================

-- Общий модуль (require, API 22).
local shared = require("shared.luau")

-- ---------------------------------------------------------------------------
-- Локальное состояние панели (живёт, пока жив runtime entry)
-- ---------------------------------------------------------------------------
local mode = "unread" -- текущая вкладка: "unread" | "history"
local statusText = "" -- строка статуса внизу/вверху панели
local busy = false -- выполняется сетевой запрос
local state = shared.loadState() -- данные из state.json

-- ---------------------------------------------------------------------------
-- Утилиты UI
-- ---------------------------------------------------------------------------

--- Цветовая палитра из темы Noctalia с безопасными fallback'ами.
local function color(role, fallback)
	return noctalia.getColor(role) or fallback
end

--- Дерево-обёртка «карточка уведомления»: иконка типа, репозиторий,
--- заголовок, время, кнопки Open / Mark read.
---@param e table Запись уведомления
---@param showActions boolean Показывать ли кнопки (для истории — только Open)
---@return table UiNode
local function notificationCard(e, showActions)
	local onSurface = color("on_surface", "#cdd6f4")
	local muted = color("on_surface", "#a6adc8")

	local actionButtons = {}

	-- Кнопка «Открыть на github.com».
	table.insert(actionButtons, ui.button({
		text = "Open",
		variant = "outline",
		controlSize = "sm",
		onClick = function()
			noctalia.runAsync("xdg-open " .. shared.shellQuote(shared.toHtmlUrl(e.apiUrl)))
		end,
	}))

	-- Кнопка «Прочитано» (только для непрочитанных).
	if showActions then
		table.insert(actionButtons, ui.button({
			glyph = "check",
			variant = "ghost",
			controlSize = "sm",
			tooltip = "Mark as read",
			onClick = function()
				markOneRead(e)
			end,
		}))
	end

	return ui.row({
		padding = 8,
		gap = 8,
		fill = color("surface", "#1e1e2e"),
		radius = 8,
		align = "center",
	}, {
		-- Иконка типа уведомления.
		ui.glyph({
			name = shared.kindGlyph(e.kind),
			size = 18,
			color = color("primary", "#89b4fa"),
		}),
		-- Текстовый блок: репозиторий + заголовок + время.
		ui.column({
			flexGrow = 1,
			gap = 2,
		}, {
			ui.label({
				text = e.repo .. " · " .. e.kind,
				fontSize = 11,
				color = muted,
			}),
			ui.label({
				text = e.title,
				fontSize = 13,
				color = onSurface,
				maxWidth = 380,
			}),
		}),
		-- Возраст уведомления.
		ui.label({
			text = shared.fmtAgo(e.updated),
			fontSize = 11,
			color = muted,
		}),
		-- Кнопки действий.
		ui.row({
			gap = 4,
			align = "center",
		}, actionButtons),
	})
end

--- Заголовок панели: название, кнопки Refresh / Mark all / Open GitHub.
---@return table UiNode
local function headerRow()
	local unreadLabel = ("Unread (%d)"):format(#state.unread)
	local historyLabel = ("History (%d)"):format(#state.history)

	return ui.row({
		gap = 6,
		align = "center",
	}, {
		ui.glyph({ name = "bell", size = 20, color = color("primary", "#89b4fa") }),
		ui.label({ text = "GitHub Notifications", fontSize = 16, flexGrow = 1 }),
		-- Переключатель вкладок.
		ui.button({
			text = unreadLabel,
			variant = mode == "unread" and "primary" or "ghost",
			controlSize = "sm",
			onClick = function()
				mode = "unread"
				render()
			end,
		}),
		ui.button({
			text = historyLabel,
			variant = mode == "history" and "primary" or "ghost",
			controlSize = "sm",
			onClick = function()
				mode = "history"
				render()
			end,
		}),
		-- Обновить список.
		ui.button({
			glyph = "refresh",
			variant = "ghost",
			controlSize = "sm",
			tooltip = "Refresh",
			onClick = function()
				fetchNow()
			end,
		}),
		-- Отметить все прочитанными (только во вкладке Unread).
		ui.button({
			glyph = "checks",
			variant = "ghost",
			controlSize = "sm",
			tooltip = "Mark all as read",
			onClick = function()
				markAllRead()
			end,
		}),
		-- Открыть github.com/notifications в браузере.
		ui.button({
			glyph = "external-link",
			variant = "ghost",
			controlSize = "sm",
			tooltip = "Open github.com/notifications",
			onClick = function()
				noctalia.runAsync("xdg-open 'https://github.com/notifications'")
			end,
		}),
	})
end

--- Строка статуса (индикатор busy / ошибки / результата).
---@return table UiNode
local function statusRow()
	if statusText == "" then
		return ui.label({ text = "", fontSize = 11 })
	end
	return ui.label({
		text = (busy and "⏳ " or "") .. statusText,
		fontSize = 11,
		color = color("on_surface", "#a6adc8"),
	})
end

--- Полный рендер панели.
function render()
	local children = {}

	table.insert(children, headerRow())
	table.insert(children, statusRow())

	-- Токен не настроен: показываем инструкцию вместо списка.
	if shared.getToken() == "" then
		table.insert(children, ui.column({ padding = 16, gap = 10 }, {
			ui.glyph({ name = "bell-off", size = 32, color = color("on_surface", "#a6adc8") }),
			ui.label({
				text = "No GitHub token configured",
				fontSize = 14,
				color = color("on_surface", "#cdd6f4"),
			}),
			ui.label({
				text = "Create a classic token with the 'notifications' scope\nat github.com/settings/tokens, then paste it in\nNoctalia Settings → Plugins → GitHub Notifications.",
				fontSize = 12,
				color = color("on_surface", "#a6adc8"),
			}),
			ui.button({
				text = "Open plugin settings",
				variant = "primary",
				controlSize = "sm",
				onClick = function()
					noctalia.openSettings()
				end,
			}),
		}))
		panel.render(ui.column({ fill = color("surface", "#11111b"), padding = 12, gap = 10 }, children))
		return
	end

	-- Список уведомлений по текущей вкладке.
	local items = mode == "unread" and state.unread or state.history
	local listChildren = {}

	if #items == 0 then
		table.insert(listChildren, ui.column({ padding = 20, gap = 8 }, {
			ui.glyph({
				name = mode == "unread" and "check" or "history",
				size = 28,
				color = color("on_surface", "#a6adc8"),
			}),
			ui.label({
				text = mode == "unread" and "No unread notifications" or "History is empty",
				fontSize = 13,
				color = color("on_surface", "#a6adc8"),
			}),
		}))
	else
		for _, e in ipairs(items) do
			table.insert(listChildren, notificationCard(e, mode == "unread"))
		end
	end

	table.insert(children, ui.scroll({
		flexGrow = 1,
		gap = 6,
	}, listChildren))

	panel.render(ui.column({
		fill = color("surface", "#11111b"),
		padding = 12,
		gap = 10,
	}, children))
end

-- ---------------------------------------------------------------------------
-- Сетевые действия
-- ---------------------------------------------------------------------------

--- Обновить список уведомлений с GitHub прямо из панели.
function fetchNow()
	if busy then
		return
	end
	local token = shared.getToken()
	if token == "" then
		render()
		return
	end

	busy = true
	statusText = "Refreshing…"
	render()

	local started = shared.fetch(token, function(ok, unread, read, err)
		busy = false
		if not ok then
			statusText = "Error: " .. tostring(err)
		else
			state = shared.loadState()
			shared.mergeFetched(state, unread, read)
			shared.saveState(state)
			statusText = ("Updated: %d unread, %d in history"):format(#state.unread, #state.history)
		end
		render()
	end)

	if not started then
		busy = false
		statusText = "Request could not start"
		render()
	end
end

--- Отметить одно уведомление прочитанным.
---@param e table
function markOneRead(e)
	if busy then
		return
	end
	local token = shared.getToken()

	busy = true
	statusText = "Marking as read…"
	render()

	local started = shared.markRead(token, e.id, function(ok, err)
		busy = false
		if ok then
			shared.moveToHistory(state, e.id)
			shared.saveState(state)
			statusText = "Marked as read: " .. e.title
		else
			statusText = "Failed: " .. tostring(err)
		end
		render()
	end)

	if not started then
		busy = false
		render()
	end
end

--- Отметить все уведомления прочитанными.
function markAllRead()
	if busy or #state.unread == 0 then
		return
	end
	local token = shared.getToken()

	busy = true
	statusText = "Marking all as read…"
	render()

	local started = shared.markAllRead(token, function(ok, err)
		busy = false
		if ok then
			-- Локально переносим всё в историю; сервер подтвердит при след. fetch.
			-- moveToHistory удаляет по одному элементу — идём, пока список не пуст.
			while #state.unread > 0 do
				shared.moveToHistory(state, state.unread[1].id)
			end
			shared.saveState(state)
			statusText = "All notifications marked as read"
		else
			statusText = "Failed: " .. tostring(err)
		end
		render()
	end)

	if not started then
		busy = false
		render()
	end
end

-- ---------------------------------------------------------------------------
-- Жизненный цикл панели
-- ---------------------------------------------------------------------------

--- Открытие панели: перечитываем state.json (виджет мог обновить данные)
--- и сразу запрашиваем свежие уведомления.
function onOpen(context)
	mode = "unread"
	statusText = ""
	state = shared.loadState()
	render()
	fetchNow()
end

--- Закрытие панели: ничего дополнительного не требуется.
function onClose()
end

noctalia.log("[GitHub] Панель уведомлений загружена")
