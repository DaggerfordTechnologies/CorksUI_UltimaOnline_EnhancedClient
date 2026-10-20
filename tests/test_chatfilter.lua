-- Tests for Source/CorksChatFilter.lua outside the game.
--
-- Run from the CorksUI folder:  lua5.1 tests/test_chatfilter.lua
--
-- Stand-ins for the client API below are as strict as the real ones where that has
-- caught bugs before (WStringToString on a number errors in the client), and the
-- chat log is tested both 0-based (what the client does) and 1-based (what the
-- docs say).

local here = string.match(arg[0], "^(.*)[/\\]") or "."
local SOURCE = arg[1] or (here .. "/../Source/CorksChatFilter.lua")

local function fail(base, msg)
	print("FAIL (first index " .. base .. "): " .. msg)
	os.exit(1)
end

-- Sets up the client stand-ins and loads a fresh copy of the filter.
-- base: the index TextLogGetEntry uses for the oldest entry.
local function load(base)
	function L(s) return s end
	wstring = string
	function WStringToString(s)
		if type(s) ~= "string" then
			error("WStringToString needs a wstring")
		end
		return s
	end
	function StringToWString(s) return s end
	function GetStringFromTid(id) return "tid" .. id end
	function DoesWindowNameExist() return true end
	function LabelSetText() end

	SystemData = { ChatLogFilters = { SYSTEM = 1, SAY = 2, GUILD = 3 }, Text = nil, TextID = 0, TextChannelID = 0 }
	ChatSettings = { Channels = { [1] = {}, [2] = {}, [3] = {} } }

	local saved = {}
	Interface = {}
	function Interface.LoadBoolean(name, default)
		if saved[name] == nil then
			return default
		end
		return saved[name]
	end
	Interface.LoadNumber = Interface.LoadBoolean
	Interface.LoadWString = Interface.LoadBoolean
	function Interface.SaveBoolean(name, value) saved[name] = value end
	Interface.SaveNumber = Interface.SaveBoolean
	Interface.SaveWString = Interface.SaveBoolean
	function Interface.DeleteSetting(name) saved[name] = nil end

	printed = {}
	WindowUtils = { ChatPrint = function(text) table.insert(printed, text) end }

	overheadShown = {}
	OverheadText = { ShowOverheadText = function() table.insert(overheadShown, SystemData.Text) end }

	-- Text logs. "Chat" holds LIMIT entries, so old lines drop off the top.
	local LIMIT = 6
	local clock = 0
	logs = { Chat = { entries = {}, filters = {} } }
	function TextLogCreate(name) logs[name] = logs[name] or { entries = {}, filters = {} } end
	function TextLogSetEnabled() end
	function TextLogSetIncrementalSaving() end
	function TextLogClear(name) logs[name].entries = {} end
	function TextLogAddFilterType(name, id) logs[name].filters[id] = true end
	function TextLogAddEntry(name, filterType, text)
		local log = logs[name]
		clock = clock + 1
		table.insert(log.entries, { timestamp = "[t" .. math.floor(clock / 3) .. "]", filterType = filterType, text = text })
		if name == "Chat" and #log.entries > LIMIT then
			table.remove(log.entries, 1)
		end
	end
	function TextLogGetNumEntries(name) return #logs[name].entries end
	function TextLogGetEntry(name, index)
		local entry = logs[name].entries[index - base + 1]
		if not entry then
			return nil
		end
		return entry.timestamp, entry.filterType, entry.text
	end

	-- Log displays: which logs each chat tab shows.
	displays = { Tab1 = { Chat = true } }
	function LogDisplayAddLog(display, log) displays[display][log] = true end
	function LogDisplayRemoveLog(display, log) displays[display][log] = nil end
	function LogDisplaySetFilterState() end
	function LogDisplayGetFilterState() return true end
	function LogDisplaySetFilterColor() end
	function LogDisplayGetFilterColor() return 1, 2, 3 end
	ChatWindow = { Windows = { { Tabs = { { tabWindow = "Tab1" } } } } }

	dofile(SOURCE)
	local filter = CorksChatFilter
	filter.Initialized = true
	filter.HookOverhead()
	filter.Entries = {
		{ id = 500119, text = "You must wait to perform another action.", on = true, preset = true },
		{ id = 501240, text = "You have hidden yourself well.", on = true, preset = true },
	}
	filter.UpdateMatches()
	return filter
end

local function copied()
	local texts = {}
	for _, entry in ipairs(logs.CorksChat.entries) do
		table.insert(texts, entry.text)
	end
	return table.concat(texts, " | ")
end

local function run(base)
	local filter = load(base)

	-- A message as the client delivers it: the message event (which also draws
	-- overhead text) and the chat log line, in either order.
	local function message(channel, text, id, eventFirst, logPrefix)
		SystemData.Text, SystemData.TextID, SystemData.TextChannelID = text, id or 0, channel
		if eventFirst then
			filter.OnChatText()
			OverheadText.ShowOverheadText()
		end
		TextLogAddEntry("Chat", channel, (logPrefix or "") .. text)
		if not eventFirst then
			filter.OnLogUpdate(0.016)
			filter.OnChatText()
			OverheadText.ShowOverheadText()
		end
		filter.OnLogUpdate(0.016)
	end

	TextLogAddEntry("Chat", 2, "Bob: old line")
	filter.StartCopy()
	if #printed > 0 then fail(base, "start failed: " .. printed[1]) end
	if not filter.Copying then fail(base, "not copying") end
	if not displays.Tab1.CorksChat or displays.Tab1.Chat then fail(base, "chat tab not moved to the copy") end

	message(2, "Bob: hello")
	message(1, "You must wait to perform another action.", 500119, true)
	message(1, "You must wait to perform another action.", 500119, false)
	message(1, "You see: a chest", 0, false)
	message(3, "Guild: hi")
	-- The log is past its limit from here on.
	message(1, "You must wait to perform another action.", 500119, true)
	-- A game message on the say channel, logged with the character's name in front.
	message(2, "You have hidden yourself well.", 501240, false, "[Mystic]: ")
	message(2, "You have hidden yourself well.", 501240, true, "[Mystic]: ")
	message(2, "Bob: again")
	if filter.LastText ~= "You see: a chest" then
		fail(base, "last game message was " .. tostring(filter.LastText))
	end
	message(2, "Bob: again 2")
	-- A line with no message event (printed by the UI) shows once the hold runs out.
	TextLogAddEntry("Chat", 1, "Printed by UI")
	for _ = 1, 40 do
		filter.OnLogUpdate(0.016)
	end

	local want = "Bob: old line | Bob: hello | You see: a chest | Guild: hi | Bob: again | Bob: again 2 | Printed by UI"
	if copied() ~= want then fail(base, "copy was:\n  " .. copied() .. "\nwanted:\n  " .. want) end
	if #printed > 0 then fail(base, "error printed: " .. printed[1]) end

	for _, text in ipairs(overheadShown) do
		if text:find("must wait") or text:find("hidden yourself") then
			fail(base, "blocked message drawn overhead: " .. text)
		end
	end
	if #overheadShown ~= 5 then fail(base, #overheadShown .. " messages drawn overhead, wanted 5") end

	-- While copying, the chat window's calls for "Chat" go to the copy.
	LogDisplayAddLog("Tab1", "Chat")
	if displays.Tab1.Chat then fail(base, "LogDisplayAddLog wasn't redirected") end

	filter.SetEnabled(false)
	if not displays.Tab1.Chat or displays.Tab1.CorksChat then fail(base, "chat tab not moved back") end
	print("PASS (first index " .. base .. ")")
end

run(0)
run(1)
