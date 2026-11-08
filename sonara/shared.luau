--!nonstrict
-- ============================================================================
-- Sonara Player Widget — общий модуль (подключается через require, API 43).
--
-- ДВА РЕЖИМА ПОЛУЧЕНИЯ ДАННЫХ О ТРЕКЕ:
--
-- 1) native — noctalia.mediaPlayer() (встроенный MPRIS-снапшот хоста,
--    позиция проецируется на момент вызова). Используется, если хост
--    экспортирует этот API (новые версии Noctalia).
--
-- 2) dbus — fallback для хостов без mediaPlayer() (например Noctalia 5.4.1):
--    sonara-dbus.sh (пишется в папку данных плагина) через gdbus находит
--    активный MPRIS-игрок (предпочитает Playing), печатает снапшот —
--    метаданные, позицию, громкость, shuffle/loop, timestamp. Запускается
--    noctalia.runAsync(cmd, cb) (один sh-процесс на опрос, ~1 раз/сек),
--    вывод парсится в Luau. Позиция экстраполируется между опросами.
--
-- Управление: sonara-act.sh (play-pause/next/previous/seek/volume/shuffle/
-- loop) через тот же gdbus; в native-режиме — playerctl.
--
-- Обложки: file:// пути отдаются сразу; http(s) качаются noctalia.download
-- в папку данных плагина и кэшируются по URL.
--
-- Визуализатор: генераторы значений 0..1 для ui.graph (волновые стили) и
-- высот столбиков ui.box (спектр).
-- ============================================================================

local M = {}

M.WAVE_STYLES = { "wavy", "line", "unique", "spectrum", "bars" }
M.WAVE_LABELS = {
	wavy = "Волнистая",
	line = "Обычная",
	unique = "Уникальная",
	spectrum = "Спектр",
	bars = "Столбики",
}
M.BTN_STYLES = { "m3", "classic", "round" }
M.BTN_LABELS = { m3 = "Material 3", classic = "Классические", round = "Круглые" }

-- ---------------------------------------------------------------------------
-- Мелкие утилиты
-- ---------------------------------------------------------------------------

function M.trunc(s, n)
	s = tostring(s or "")
	if #s <= n then
		return s
	end
	local cut = string.sub(s, 1, n)
	local i = #cut
	while i > 0 do
		local b = string.byte(cut, i)
		if b < 0x80 then
			break
		end
		if b >= 0xC0 then
			i = i - 1
			break
		end
		i = i - 1
	end
	if i <= 0 then
		return "…"
	end
	return string.sub(cut, 1, i) .. "…"
end

function M.fmtTime(sec)
	if not sec or sec ~= sec or sec < 0 then
		sec = 0
	end
	return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

function M.urlDecode(s)
	return (s:gsub("%%(%x%x)", function(h)
		return string.char(tonumber(h, 16))
	end))
end

function M.hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

--- Экранирует строку для /bin/sh.
function M.shellQuote(s)
	return "'" .. tostring(s):gsub("'", "'\"'\"'") .. "'"
end

-- ---------------------------------------------------------------------------
-- Режим: native (mediaPlayer) или dbus (gdbus-скрипты)
-- ---------------------------------------------------------------------------

M._mode = nil -- "native" | "dbus"
M._cache = nil -- последний снапшот dbus-опроса

--- Определяет (и кэширует) режим.
---@return string "native" | "dbus"
function M.mode()
	if M._mode == nil then
		if type(noctalia.mediaPlayer) == "function" then
			M._mode = "native"
			noctalia.log("[Sonara] Режим данных: native noctalia.mediaPlayer()")
		else
			M._mode = "dbus"
			noctalia.log("[Sonara] Режим данных: D-Bus fallback (gdbus) — mediaPlayer() недоступен в этой версии хоста")
		end
	end
	return M._mode
end

-- ---------------------------------------------------------------------------
-- native: noctalia.mediaPlayer()
-- ---------------------------------------------------------------------------

local function fromNative(p)
	local artists = {}
	if type(p.artists) == "table" then
		for _, a in ipairs(p.artists) do
			table.insert(artists, tostring(a))
		end
	end
	local title = tostring(p.title or "")
	if title == "" then
		title = "Unknown title"
	end
	return {
		title = title,
		artist = #artists > 0 and table.concat(artists, ", ") or "Unknown artist",
		album = tostring(p.album or ""),
		artUrl = tostring(p.artUrl or ""),
		status = tostring(p.status or "Stopped"),
		playing = p.status == "Playing",
		posSec = (tonumber(p.positionMs) or 0) / 1000,
		lenSec = (tonumber(p.lengthMs) or 0) / 1000,
		volume = nil,
		shuffle = nil,
		loop = nil,
		trackId = tostring(p.trackId or ""),
		identity = tostring(p.identity or ""),
	}
end

-- ---------------------------------------------------------------------------
-- dbus: sonara-dbus.sh + парсинг вывода gdbus
-- ---------------------------------------------------------------------------

function M.scriptPath()
	local dir = noctalia.pluginDataDir()
	if not dir then
		return nil
	end
	return dir
end

--- Пишет sh-скрипты опроса и управления (дёшево, вызывается лениво).
---@return boolean
function M.ensureScripts()
	local dir = M.scriptPath()
	if not dir then
		return false
	end

	local query = [[#!/bin/sh
names=$(gdbus call --session --dest org.freedesktop.DBus \
  -o /org/freedesktop/DBus -m org.freedesktop.DBus.ListNames 2>/dev/null \
  | tr ',' '\n' | grep -o "org\.mpris\.MediaPlayer2[^'\", ]*")
dest=""
pst=""
for d in $names; do
  st=$(gdbus call --session --dest "$d" -o /org/mpris/MediaPlayer2 \
    -m org.freedesktop.DBus.Properties.Get org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null)
  case "$st" in
    *Playing*) dest="$d"; pst="$st"; break ;;
  esac
  if [ -z "$dest" ]; then dest="$d"; pst="$st"; fi
done
[ -z "$dest" ] && exit 0
P="org.mpris.MediaPlayer2.Player"
echo "DEST $dest"
echo "ST $pst"
echo "META"
gdbus call --session --dest "$dest" -o /org/mpris/MediaPlayer2 -m org.freedesktop.DBus.Properties.Get "$P" Metadata 2>/dev/null
echo "POS"
gdbus call --session --dest "$dest" -o /org/mpris/MediaPlayer2 -m org.freedesktop.DBus.Properties.Get "$P" Position 2>/dev/null
echo "VOL"
gdbus call --session --dest "$dest" -o /org/mpris/MediaPlayer2 -m org.freedesktop.DBus.Properties.Get "$P" Volume 2>/dev/null
echo "SHUF"
gdbus call --session --dest "$dest" -o /org/mpris/MediaPlayer2 -m org.freedesktop.DBus.Properties.Get "$P" Shuffle 2>/dev/null
echo "LOOP"
gdbus call --session --dest "$dest" -o /org/mpris/MediaPlayer2 -m org.freedesktop.DBus.Properties.Get "$P" LoopStatus 2>/dev/null
echo "TS $(date +%s)"
]]

	local act = [[#!/bin/sh
ACTION="$1"; shift
names=$(gdbus call --session --dest org.freedesktop.DBus \
  -o /org/freedesktop/DBus -m org.freedesktop.DBus.ListNames 2>/dev/null \
  | tr ',' '\n' | grep -o "org\.mpris\.MediaPlayer2[^'\", ]*")
dest=""
for d in $names; do
  st=$(gdbus call --session --dest "$d" -o /org/mpris/MediaPlayer2 \
    -m org.freedesktop.DBus.Properties.Get org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null)
  case "$st" in
    *Playing*) dest="$d"; break ;;
  esac
  if [ -z "$dest" ]; then dest="$d"; fi
done
[ -z "$dest" ] && exit 1
P="org.mpris.MediaPlayer2.Player"
BASE="gdbus call --session --dest $dest -o /org/mpris/MediaPlayer2"
case "$ACTION" in
  play-pause) $BASE -m $P.PlayPause >/dev/null 2>&1 ;;
  next)       $BASE -m $P.Next >/dev/null 2>&1 ;;
  previous)   $BASE -m $P.Previous >/dev/null 2>&1 ;;
  seek-rel)   $BASE -m $P.Seek int64 "$1" >/dev/null 2>&1 ;;
  seek-abs)   $BASE -m $P.SetPosition "objectpath '$1'" int64 "$2" >/dev/null 2>&1 ;;
  volume)     $BASE -m org.freedesktop.DBus.Properties.Set $P Volume "<double $1>" >/dev/null 2>&1 ;;
  shuffle)    $BASE -m org.freedesktop.DBus.Properties.Set $P Shuffle "<$1>" >/dev/null 2>&1 ;;
  loop)       $BASE -m org.freedesktop.DBus.Properties.Set $P LoopStatus "<'$1'>" >/dev/null 2>&1 ;;
esac
]]

	local ok1 = noctalia.writeFile(dir .. "/sonara-dbus.sh", query)
	local ok2 = noctalia.writeFile(dir .. "/sonara-act.sh", act)
	return ok1 and ok2
end

--- Парсит вывод sonara-dbus.sh. nil — плеера нет.
---@param out string
---@return table?
local function parseDbus(out)
	local dest = out:match("DEST (%S+)")
	if not dest then
		return nil
	end

	local meta = out:match("META\n(.-)\nPOS\n") or ""
	local track = {
		title = "Unknown title",
		artist = "Unknown artist",
		album = "",
		artUrl = "",
		status = "Stopped",
		playing = false,
		lenSec = 0,
		volume = nil,
		shuffle = nil,
		loop = nil,
		trackId = "",
		identity = dest:gsub("^org%.mpris%.MediaPlayer2%.", ""):gsub("%.instance%d+$", ""),
	}

	track.status = out:match("ST %(<'(.-)'%>,%)") or "Stopped"
	track.playing = track.status == "Playing"

	-- Значения gdbus экранирует; наиболее частые случаи разбираем напрямую.
	track.title = meta:match("'xesam:title': <'(.-)'>") or track.title
	local artistRaw = meta:match("'xesam:artist': <(%b[])>") or ""
	track.artist = artistRaw:match("'(.-)'") or track.artist
	track.album = meta:match("'xesam:album': <'(.-)'>") or track.album
	track.artUrl = meta:match("'mpris:artUrl': <'(.-)'>") or track.artUrl
	track.lenSec = (tonumber(meta:match("'mpris:length': <int64 (.-)>")) or 0) / 1e6
	track.trackId = meta:match("'mpris:trackid': <objectpath '(.-)'>") or track.trackId

	track.posUs = tonumber(out:match("POS\n%(<int64 (.-)>,%)")) or 0
	local vol = tonumber(out:match("VOL\n%(<([^>]*)>,%)"))
	if vol then
		track.volume = vol
	end
	local shuf = out:match("SHUF\n%(<([^>]*)>,%)")
	if shuf then
		track.shuffle = shuf == "true" and "On" or "Off"
	end
	local loop = out:match("LOOP\n%(<'([^>]*)'>,%)")
	if loop then
		track.loop = loop
	end
	track.fetchedAt = tonumber(out:match("TS (%d+)")) or os.time()

	track.posSec = track.posUs / 1e6
	if track.playing then
		track.posSec = track.posSec + math.max(0, os.time() - track.fetchedAt)
	end
	return track
end

M._dbusBusy = false

--- Асинхронный опрос плеера. cb(track) опционален.
---@param cb function?
---@return boolean
function M.refresh(cb)
	if M.mode() == "native" then
		local t = M.player()
		if cb then
			cb(t)
		end
		return t ~= nil
	end

	if M._dbusBusy then
		if cb then
			cb(M.player())
		end
		return M._cache ~= nil
	end

	local dir = M.scriptPath()
	if not dir or not M.ensureScripts() then
		if cb then
			cb(nil)
		end
		return false
	end

	M._dbusBusy = true
	local started = noctalia.runAsync("sh " .. M.shellQuote(dir .. "/sonara-dbus.sh"), function(r)
		M._dbusBusy = false
		M._cache = parseDbus(r.stdout or "")
		if cb then
			cb(M.player())
		end
	end)
	if not started then
		M._dbusBusy = false
		if cb then
			cb(M.player())
		end
		return false
	end
	return true
end

--- Синхронный снапшот: native — напрямую; dbus — кэш с экстраполяцией позиции.
---@return table?
function M.player()
	if M.mode() == "native" then
		local ok, p = pcall(noctalia.mediaPlayer)
		if not ok or type(p) ~= "table" then
			return nil
		end
		return fromNative(p)
	end

	local t = M._cache
	if not t then
		return nil
	end
	-- Экстраполяция позиции между опросами.
	if t.playing and t.fetchedAt then
		t.posSec = t.posUs / 1e6 + math.max(0, os.time() - t.fetchedAt)
	end
	return t
end

-- ---------------------------------------------------------------------------
-- Управление
-- ---------------------------------------------------------------------------

--- Команда плееру. Примеры: ("play-pause"), ("next"), ("seek-rel", us),
--- ("seek-abs", trackId, us), ("volume", 0.85), ("shuffle", true),
--- ("loop", "Track"). cb(result) опционален.
---@param action string
---@param a any?
---@param b any?
---@param cb function?
---@return boolean
function M.act(action, a, b, cb)
	if M.mode() == "native" then
		-- playerctl: только константные команды.
		local map = {
			["play-pause"] = "play-pause",
			next = "next",
			previous = "previous",
			["seek-rel"] = "position " .. tostring(a) .. "-",
			["seek-fwd"] = "position " .. tostring(a) .. "+",
			["seek-abs"] = "position " .. tostring(b),
			["volume"] = "volume " .. tostring(a),
			["shuffle"] = "shuffle " .. (a and "on" or "off"),
			["loop"] = "loop " .. string.lower(tostring(a)),
		}
		local cmd = map[action]
		if not cmd then
			return false
		end
		if cb then
			return noctalia.runAsync("playerctl " .. cmd, cb)
		end
		return noctalia.runAsync("playerctl " .. cmd)
	end

	local dir = M.scriptPath()
	if not dir or not M.ensureScripts() then
		return false
	end
	local args = " " .. M.shellQuote(tostring(action))
	if a ~= nil then
		args = args .. " " .. M.shellQuote(tostring(a))
	end
	if b ~= nil then
		args = args .. " " .. M.shellQuote(tostring(b))
	end
	local cmd = "sh " .. M.shellQuote(dir .. "/sonara-act.sh") .. args
	if cb then
		return noctalia.runAsync(cmd, cb)
	end
	return noctalia.runAsync(cmd)
end

--- Состояние volume/shuffle/loop. cb(fields).
---@param cb function
---@return boolean
function M.queryState(cb)
	if M.mode() == "native" then
		local pending = 3
		local fields = { volume = 1.0, shuffle = "Off", loop = "None" }
		local function done()
			pending = pending - 1
			if pending == 0 then
				cb(fields)
			end
		end
		local started = 0
		local q = function(args, fn)
			if noctalia.runAsync("playerctl " .. args, function(r)
				if r.exitCode == 0 then
					fn((r.stdout:gsub("%s+", "")))
				end
				done()
			end) then
				started = started + 1
			end
		end
		q("volume", function(v)
			fields.volume = tonumber(v) or 1.0
		end)
		q("shuffle", function(v)
			fields.shuffle = (v ~= "Off") and "On" or "Off"
		end)
		q("loop", function(v)
			fields.loop = v
		end)
		if started == 0 then
			cb(fields)
			return false
		end
		return true
	end

	-- dbus-режим: состояние уже в кэше.
	cb({
		volume = (M._cache and M._cache.volume) or 1.0,
		shuffle = (M._cache and M._cache.shuffle) or "Off",
		loop = (M._cache and M._cache.loop) or "None",
	})
	return true
end

-- ---------------------------------------------------------------------------
-- Обложки: file:// отдаётся сразу, http(s) качается и кэшируется
-- ---------------------------------------------------------------------------

local coverCache = {} -- artUrl -> локальный путь

---@param track table
---@param cb function?
---@return string?
function M.coverPath(track, cb)
	local url = tostring((track and track.artUrl) or "")
	if url == "" then
		return nil
	end
	if string.find(url, "^file://") then
		return M.urlDecode(url:gsub("^file://", ""))
	end
	if string.find(url, "^/") then
		return url
	end
	if coverCache[url] then
		return coverCache[url]
	end
	local dir = noctalia.pluginDataDir()
	if not dir then
		return nil
	end
	local ext = string.find(url, "%.png", 1, false) and ".png" or ".jpg"
	local dest = dir .. "/cover-" .. tostring(M.hash(url)) .. ext
	coverCache[url] = dest
	local started = noctalia.download(url, dest, function(ok)
		if not ok then
			coverCache[url] = nil
		end
		if cb then
			cb(ok and dest or nil)
		end
	end)
	if not started then
		coverCache[url] = nil
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Визуализатор
-- ---------------------------------------------------------------------------

local TWO_PI = math.pi * 2

---@param style string
-- ---------------------------------------------------------------------------
-- Настоящий спектр: cava (PipeWire capture) в режиме raw/ascii.
-- cava запускается noctalia.runStream (долгоживущий процесс), каждая строка
-- stdout — кадр "v1;v2;…;vN" со значениями 0..ascii_max_range (100).
-- Если cava не установлен — волна остаётся синтетической.
-- ---------------------------------------------------------------------------

M.CAVA_BARS = 16
M.cavaLevels = nil -- последний настоящий спектр: { number } 0..1
M.cavaActive = false

function M.cavaConfigPath()
	local dir = M.scriptPath()
	if not dir then
		return nil
	end
	return dir .. "/sonara-cava.conf"
end

function M.ensureCavaConfig()
	local path = M.cavaConfigPath()
	if not path then
		return false
	end
	local conf = "# Sonara cava config\n"
		.. "[general]\n"
		.. "bars = " .. tostring(M.CAVA_BARS) .. "\n"
		.. "autosens = 1\n"
		.. "[output]\n"
		.. "method = raw\n"
		.. "raw_target = /dev/stdout\n"
		.. "data_format = ascii\n"
		.. "ascii_max_range = 100\n"
		.. "bar_delimiter = 59\n"
	return noctalia.writeFile(path, conf)
end

--- Запускает cava (если он есть на PATH) и слушает спектр.
---@return boolean
function M.startCava()
	if M.cavaActive then
		return true
	end
	if type(noctalia.commandExists) ~= "function" or not noctalia.commandExists("cava") then
		return false
	end
	local path = M.cavaConfigPath()
	if not path or not M.ensureCavaConfig() then
		return false
	end
	M.cavaActive = true
	local started = noctalia.runStream("cava -p " .. M.shellQuote(path), function(line)
		local levels, sum, count = {}, 0, 0
		for v in line:gmatch("%d+") do
			local x = (tonumber(v) or 0) / 100
			levels[#levels + 1] = x
			sum = sum + x
			count = count + 1
		end
		if count > 0 then
			M.cavaLevels = levels
			M.cavaAvg = sum / count
		end
	end)
	if not started then
		M.cavaActive = false
	end
	return M.cavaActive
end

--- Останавливает cava (процесс матчится по уникальному имени конфига).
function M.stopCava()
	if not M.cavaActive then
		return
	end
	M.cavaActive = false
	M.cavaLevels = nil
	noctalia.runAsync("pkill -f " .. M.shellQuote("sonara-cava.conf") .. " 2>/dev/null")
end

--- Линейная интерполяция массива уровней до n точек.
---@param levels { number }
---@param n number
---@return { number }
local function interp(levels, n)
	local m = #levels
	if m == 0 then
		return {}
	end
	local out = {}
	for i = 1, n do
		local x = (i - 1) / (n - 1) * (m - 1) + 1
		local i0 = math.floor(x)
		local i1 = math.min(m, i0 + 1)
		local f = x - i0
		out[i] = levels[i0] * (1 - f) + levels[i1] * f
	end
	return out
end

---@param phase number
---@param playing boolean
---@param n number?
---@return { number } values
---@return { number }? values2
function M.waveValues(style, phase, playing, n)
	n = n or 48

	-- Настоящий спектр от cava: значения — реальные уровни полос.
	-- Для wave — дополнительно сглаженные (экспоненциальное сглаживание
	-- делает движение плавным, без дёрганья сырого спектра).
	if M.cavaLevels and #M.cavaLevels > 0 then
		local src = M.cavaLevels
		if style == "wave" or style == "line" or style == "unique" then
			if M.cavaSmooth == nil or #M.cavaSmooth ~= #src then
				M.cavaSmooth = {}
				for i = 1, #src do
					M.cavaSmooth[i] = src[i]
				end
			end
			for i = 1, #src do
				M.cavaSmooth[i] = M.cavaSmooth[i] * 0.72 + src[i] * 0.28
			end
			src = M.cavaSmooth
		end
		local values = interp(src, n)
		local values2 = nil
		if style == "spectrum" then
			-- Вторая серия — зеркальный спектр (высокие частоты).
			local rev = {}
			for i = #M.cavaLevels, 1, -1 do
				rev[#rev + 1] = M.cavaLevels[i]
			end
			values2 = interp(rev, n)
		end
		for i = 1, n do
			if values[i] < 0.02 then
				values[i] = 0.02
			end
			if values[i] > 1 then
				values[i] = 1
			end
		end
		if values2 then
			for i = 1, n do
				if values2[i] < 0.02 then
					values2[i] = 0.02
				end
			end
		end
		return values, values2
	end

	-- Синтетический fallback (cava не установлен).
	local amp = playing and 1.0 or 0.05
	local values, values2 = {}, nil

	if style == "spectrum" then
		values2 = {}
		for i = 1, n do
			local a = math.abs(math.sin(i * 0.9 + phase * 3.1))
			local b = math.abs(math.sin(i * 1.3 - phase * 2.4))
			local env = math.sin(i / n * math.pi)
			table.insert(values, math.min(1, (a * 0.7 + 0.3) * env * amp + 0.03))
			table.insert(values2, math.min(1, (b * 0.7 + 0.3) * env * amp + 0.03))
		end
		return values, values2
	end

	for i = 1, n do
		local t = (i - 1) / (n - 1) * TWO_PI
		local v = 0.5
			+ 0.32 * math.sin(t * 2 + phase * 2.4) * (0.6 + 0.4 * math.sin(phase * 1.1))
			+ 0.18 * math.sin(t * 3.7 - phase * 3.3)
		v = 0.5 + (v - 0.5) * amp
		if v < 0.02 then
			v = 0.02
		end
		if v > 1 then
			v = 1
		end
		table.insert(values, v)
	end
	return values, nil
end

---@param phase number
---@param playing boolean
---@param n number?
---@return { number }
function M.barHeights(phase, playing, n)
	n = n or 24
	-- Настоящие уровни от cava (интерполированные к n столбикам).
	if M.cavaLevels and #M.cavaLevels > 0 then
		return interp(M.cavaLevels, n)
	end
	local amp = playing and 1.0 or 0.05
	local out = {}
	for i = 1, n do
		local base = math.abs(math.sin(i * 1.7 + phase * 2.1))
		local jitter = math.abs(math.sin(i * 4.9 + phase * 6.3)) * 0.35
		local env = 0.35 + 0.65 * math.sin(i / n * math.pi)
		local v = math.min(1, (base * 0.65 + jitter) * env * amp + 0.03)
		table.insert(out, v)
	end
	return out
end

return M
