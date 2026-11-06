--!nonstrict
-- ============================================================================
-- GitHub Notifications — общий модуль (подключается через require, API 22).
--
-- Содержит: работу с GitHub Notifications REST API, конвертацию ссылок
-- API -> html, разбор времени, а также сохранение/загрузку состояния
-- (непрочитанные + история) в персональную папку данных плагина
-- (noctalia.pluginDataDir). Виджет и панель — отдельные runtime'ы,
-- поэтому state.json служит «мостом» данных между ними.
-- ============================================================================

local M = {}

M.API_BASE = "https://api.github.com"
M.STATE_FILE = "state.json"

--- Максимальный размер истории уведомлений.
M.HISTORY_LIMIT = 50

-- ---------------------------------------------------------------------------
-- Токен и HTTP-заголовки
-- ---------------------------------------------------------------------------

--- Возвращает токен из настроек плагина ([[setting]] github_token).
---@return string
function M.getToken()
	return tostring(noctalia.getConfig("github_token") or "")
end

--- Возвращает интервал опроса из настроек (с fallback на 120 сек).
---@return number
function M.getPollIntervalSec()
	return tonumber(noctalia.getConfig("poll_interval_sec")) or 120
end

--- Заголовки для запросов к GitHub REST API.
---@param token string Персональный токен доступа
---@return { string }
function M.headers(token)
	return {
		"Authorization: Bearer " .. token,
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: noctalia-github-notifications",
	}
end

-- ---------------------------------------------------------------------------
-- Нормализация данных
-- ---------------------------------------------------------------------------

--- Преобразует элемент ответа /notifications в компактную запись.
---@param n table Элемент из ответа GitHub API
---@return table
function M.toEntry(n)
	local subject = n.subject or {}
	local repo = n.repository or {}
	return {
		id = tostring(n.id or ""),
		title = tostring(subject.title or "(no title)"),
		kind = tostring(subject.type or "Unknown"), -- Issue | PullRequest | Release | ...
		repo = tostring(repo.full_name or ""),
		reason = tostring(n.reason or ""),
		updated = tostring(n.updated_at or ""),
		apiUrl = tostring(subject.url or ""),
		unread = n.unread == true,
	}
end

--- Конвертирует URL API в человекочитаемый URL github.com.
--- https://api.github.com/repos/owner/repo/issues/1 -> https://github.com/owner/repo/issues/1
---@param apiUrl string
---@return string
function M.toHtmlUrl(apiUrl)
	return (apiUrl:gsub("^https://api%.github%.com/repos/", "https://github.com/"))
end

--- Иконка для типа уведомления.
---@param kind string Issue | PullRequest | Release | ...
---@return string
function M.kindGlyph(kind)
	local map = {
		PullRequest = "git-pull-request",
		Issue = "circle-dot",
		Release = "package",
		CheckSuite = "cloud-check",
		Discussion = "message",
		RepositoryInvitation = "mail",
		Commit = "git-commit",
	}
	return map[kind] or "bell"
end

-- ---------------------------------------------------------------------------
-- Время
-- ---------------------------------------------------------------------------

--- Парсит ISO 8601 ("2026-01-01T12:00:00Z") в unix-время.
---@param iso string
---@return number?
function M.parseIso(iso)
	if type(iso) ~= "string" then
		return nil
	end
	local y, mo, d, h, mi, s = iso:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	return os.time({
		year = tonumber(y),
		month = tonumber(mo),
		day = tonumber(d),
		hour = tonumber(h),
		min = tonumber(mi),
		sec = tonumber(s),
	})
end

--- Короткий относительный возраст ("5m", "3h", "2d").
---@param iso string
---@return string
function M.fmtAgo(iso)
	local t = M.parseIso(iso)
	if not t then
		return ""
	end
	local delta = os.time() - t
	if delta < 0 then
		delta = 0
	end
	if delta < 60 then
		return delta .. "s"
	end
	if delta < 3600 then
		return math.floor(delta / 60) .. "m"
	end
	if delta < 86400 then
		return math.floor(delta / 3600) .. "h"
	end
	return math.floor(delta / 86400) .. "d"
end

-- ---------------------------------------------------------------------------
-- Запрос уведомлений
-- ---------------------------------------------------------------------------

--- Асинхронно запрашивает непрочитанные + прочитанные уведомления.
--- callback(ok, unread, read, err). Использует noctalia.http (API базовый).
---@param token string
---@param callback fun(ok: boolean, unread: { table }?, read: { table }?, err: string?)
---@return boolean started -- false, если токена нет или запрос не стартовал
function M.fetch(token, callback)
	if token == "" then
		callback(false, nil, nil, "no-token")
		return false
	end

	return noctalia.http({
		url = M.API_BASE .. "/notifications?per_page=30",
		method = "GET",
		headers = M.headers(token),
	}, function(response)
		if not response.ok then
			callback(false, nil, nil, "network error")
			return
		end
		if response.status ~= 200 then
			callback(false, nil, nil, "HTTP " .. tostring(response.status))
			return
		end

		local items, err = noctalia.json.decode(response.body)
		if err ~= nil or type(items) ~= "table" then
			callback(false, nil, nil, "JSON error: " .. tostring(err))
			return
		end

		local unread, read = {}, {}
		for _, n in ipairs(items) do
			local entry = M.toEntry(n)
			if entry.unread then
				table.insert(unread, entry)
			else
				table.insert(read, entry)
			end
		end
		callback(true, unread, read, nil)
	end)
end

--- Отмечает одно уведомление как прочитанное (PATCH threads/{id}).
---@param token string
---@param threadId string
---@param callback fun(ok: boolean, err: string?)
---@return boolean
function M.markRead(token, threadId, callback)
	return noctalia.http({
		url = M.API_BASE .. "/notifications/threads/" .. threadId,
		method = "PATCH",
		headers = M.headers(token),
	}, function(response)
		callback(response.ok and (response.status == 204 or response.status == 200), "HTTP " .. tostring(response.status))
	end)
end

--- Отмечает ВСЕ уведомления как прочитанные (PUT /notifications).
---@param token string
---@param callback fun(ok: boolean, err: string?)
---@return boolean
function M.markAllRead(token, callback)
	return noctalia.http({
		url = M.API_BASE .. "/notifications",
		method = "PUT",
		headers = M.headers(token),
	}, function(response)
		callback(response.ok and (response.status == 202 or response.status == 205 or response.status == 200), "HTTP " .. tostring(response.status))
	end)
end

-- ---------------------------------------------------------------------------
-- Состояние: непрочитанные + история (плагинная папка данных)
-- ---------------------------------------------------------------------------

--- Путь к state.json в персональной папке данных плагина.
---@return string?
function M.statePath()
	local dir = noctalia.pluginDataDir()
	if not dir then
		return nil
	end
	return dir .. "/" .. M.STATE_FILE
end

--- Загружает состояние; при любой ошибке возвращает чистую структуру.
---@return table { unread = { table }, history = { table } }
function M.loadState()
	local path = M.statePath()
	local empty = { unread = {}, history = {} }
	if not path then
		return empty
	end
	local data, err = noctalia.readFile(path)
	if not data then
		-- Файла может ещё не быть — это не ошибка.
		return empty
	end
	local state, jerr = noctalia.json.decode(data)
	if jerr ~= nil or type(state) ~= "table" then
		noctalia.log("[GitHub] Повреждён state.json, начинаем с чистого состояния")
		return empty
	end
	state.unread = type(state.unread) == "table" and state.unread or {}
	state.history = type(state.history) == "table" and state.history or {}
	return state
end

--- Сохраняет состояние на диск (JSON).
---@param state table
---@return boolean
function M.saveState(state)
	local path = M.statePath()
	if not path then
		return false
	end
	local str = noctalia.json.encode(state)
	if not str then
		return false
	end
	local ok = noctalia.writeFile(path, str)
	return ok
end

--- Встраивает результат fetch в состояние: заменяет непрочитанные,
--- добавляет новые прочитанные в начало истории (без дублей),
--- обрезает историю до HISTORY_LIMIT.
---@param state table
---@param unread { table }
---@param read { table }
function M.mergeFetched(state, unread, read)
	-- Непрочитанные: берём как есть из свежего ответа сервера.
	state.unread = unread

	-- История: добавляем прочитанные, которых ещё нет (новые в начало).
	local seen = {}
	for _, e in ipairs(state.history) do
		seen[e.id] = true
	end
	for _, e in ipairs(read) do
		if not seen[e.id] then
			table.insert(state.history, 1, e)
			seen[e.id] = true
		end
	end

	-- Обрезаем историю до лимита.
	while #state.history > M.HISTORY_LIMIT do
		table.remove(state.history)
	end

	state.lastChecked = os.time()
end

--- Переносит уведомление из непрочитанных в начало истории
--- (после локального «прочитать»).
---@param state table
---@param id string
function M.moveToHistory(state, id)
	for i, e in ipairs(state.unread) do
		if e.id == id then
			table.remove(state.unread, i)
			-- Убираем старую копию из истории, если была, и кладём свежую.
			for j, h in ipairs(state.history) do
				if h.id == id then
					table.remove(state.history, j)
					break
				end
			end
			table.insert(state.history, 1, e)
			while #state.history > M.HISTORY_LIMIT do
				table.remove(state.history)
			end
			return
		end
	end
end

--- Экранирует строку для безопасной передачи через /bin/sh -c.
---@param s string
---@return string
function M.shellQuote(s)
	return "'" .. s:gsub("'", "'\"'\"'") .. "'"
end

return M
