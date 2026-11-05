--!nonstrict
-- ============================================================================
-- Quick Web-Search Launcher (Noctalia Shell v5+, движок Luau)
--
-- Launcher Provider ([[launcher_provider]] в plugin.toml) — плагин,
-- расширяющий меню запуска (лаунчер) Noctalia.
--
-- КАК ЭТО РАБОТАЕТ (взаимодействие с провайдерами лаунчера):
--   1. Хост загружает entry-скрипт init.luau и регистрирует провайдера.
--   2. При изменении текста ввода хост вызывает глобальную функцию
--      onQuery(text); провайдер отвечает через launcher.setResults(query, rows).
--   3. При нажатии Enter на элементе хост вызывает глобальную функцию
--      onActivate(id) с id выбранного результата. После успешной активации
--      хост сам закрывает окно лаунчера — отдельного "закрыть" API не нужно.
--
-- Префиксы: ':g ' — Google, ':y ' — YouTube, ':gh ' — GitHub.
-- Манифест объявляет include_in_global_search = true, поэтому onQuery
-- получает весь текст ввода, и префиксы разбираются в этом коде.
-- Активация элемента открывает поисковую ссылку через xdg-open.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Конфигурация поисковых движков
-- ---------------------------------------------------------------------------
-- Порядок важен для понимания: префиксы включают завершающий пробел,
-- поэтому ':g ' не совпадает с ':gh ' (на третьем символе идёт 'h', а не ' ').
local ENGINES = {
	{
		prefix = ":g ",
		label = "Поиск в Google",
		glyph = "brand-google",
		url = "https://www.google.com/search?q=%s",
	},
	{
		prefix = ":y ",
		label = "Поиск на YouTube",
		glyph = "brand-youtube",
		url = "https://www.youtube.com/results?search_query=%s",
	},
	{
		prefix = ":gh ",
		label = "Поиск на GitHub",
		glyph = "brand-github",
		url = "https://github.com/search?q=%s",
	},
}

-- ---------------------------------------------------------------------------
-- Вспомогательные функции
-- ---------------------------------------------------------------------------

--- Простая функция экранирования строки для использования в URL.
--- Алфавитно-цифровые символы, а также '-', '_', '.', '~' остаются как есть;
--- всё остальное заменяется на '%XX' (шестнадцатеричный байт в UTF-8).
--- Пример: "как настроить niri" -> "%D0%BA%D0%B0%D0%BA..."
--- (В API Noctalia также есть встроенный noctalia.string.urlEncode —
--- собственная реализация здесь для портативности и читаемости.)
---@param input string Строка для кодирования
---@return string
local function urlencode(input)
	-- gsub передаёт байты по одному; для кириллицы каждый байт UTF-8
	-- экранируется отдельно, что корректно для поисковых URL.
	local result = input:gsub("[^%w%-_%.~]", function(char)
		return string.format("%%%02X", string.byte(char))
	end)
	return result
end

--- Убирает начальные и конечные пробелы у строки.
---@param s string
---@return string
local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Экранирует строку для безопасной передачи через /bin/sh -c.
---@param s string
---@return string
local function shellQuote(s)
	return "'" .. s:gsub("'", "'\"'\"'") .. "'"
end

--- Разбирает ввод пользователя: ищет один из известных префиксов
--- и возвращает движок поиска + текст запроса после префикса.
---@param text string Полная строка ввода из лаунчера
---@return table? engine Элемент таблицы ENGINES, либо nil
---@return string? query Текст запроса после префикса
local function parseQuery(text)
	local query = trim(text)
	for _, engine in ipairs(ENGINES) do
		if string.sub(query, 1, #engine.prefix) == engine.prefix then
			local rest = trim(string.sub(query, #engine.prefix + 1))
			-- Префикс найден, но запрос пуст (':g   ') — не предлагаем поиск.
			if rest ~= "" then
				return engine, rest
			end
			return nil, nil
		end
	end
	return nil, nil
end

-- ---------------------------------------------------------------------------
-- Колбэк onQuery(text): вызывается хостом при каждом изменении ввода.
-- Провайдер обязан ответить launcher.setResults(query, rows) — с той же
-- строкой запроса, которую он получил.
-- ---------------------------------------------------------------------------
function onQuery(text)
	local engine, query = parseQuery(text)

	-- Префикс не распознан — отдаём пустой список результатов,
	-- чтобы не захламлять общий список лаунчера.
	if engine == nil then
		launcher.setResults(text, {})
		return
	end

	-- Кодируем запрос и собираем готовую ссылку поиска.
	local url = engine.url:format(urlencode(query))

	launcher.setResults(text, {
		{
			-- id элемента — сама ссылка: onActivate получит её напрямую,
			-- и не нужен промежуточный кэш соответствий id -> url.
			id = url,
			title = string.format("%s: %s", engine.label, query),
			subtitle = "Enter — открыть результат в браузере",
			glyph = engine.glyph,
		},
	})
end

-- ---------------------------------------------------------------------------
-- Колбэк onActivate(id): пользователь нажал Enter на элементе.
-- После возврата из этой функции хост закрывает лаунчер самостоятельно.
-- ---------------------------------------------------------------------------
function onActivate(id)
	-- Защита: активация должна прийти ровно на наш URL-элемент.
	if type(id) ~= "string" or id == "" or not string.find(id, "^https?://") then
		noctalia.log("[WebSearch] Активация неизвестного элемента: " .. tostring(id))
		return
	end

	-- Открываем ссылку системным обработчиком URL (детач fire-and-forget:
	-- без callback-а noctalia.runAsync просто запускает процесс).
	local ok = noctalia.runAsync("xdg-open " .. shellQuote(id))
	if not ok then
		noctalia.log("[WebSearch] Не удалось запустить xdg-open для: " .. id)
		return
	end

	noctalia.log("[WebSearch] Открыт URL: " .. id)
end

-- ---------------------------------------------------------------------------
-- Инициализация провайдера (лог при загрузке entry-скрипта хостом).
-- ---------------------------------------------------------------------------
noctalia.log("[WebSearch] Quick Web-Search Launcher загружен (префиксы :g :y :gh)")
