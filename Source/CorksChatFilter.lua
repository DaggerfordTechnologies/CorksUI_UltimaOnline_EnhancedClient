----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksChatFilter = {}

-- Messages listed in the window from the start, unchecked until the player picks them.
-- They're matched by cliloc number, so the row shows the client's own text for that
-- number; label is only used if the client has no text for it.
CorksChatFilter.Presets = {
	{ id = 500119, label = L"You must wait to perform another action." },
	{ id = 500118, label = L"You must wait a few moments to use another skill." },
	{ id = 500235, label = L"You must wait a few seconds before using another healing potion." },
	{ id = 502625, label = L"Insufficient mana for this spell." },
	{ id = 501240, label = L"You have hidden yourself well." },
	{ id = 500956, label = L"You begin applying the bandages." },
	{ id = 500969, label = L"You finish applying the bandages." },
}

-- Every row in the list, presets first, then the ones the player added.
-- id ~= 0 matches that cliloc number (text is only shown in the row);
-- id == 0 matches any system message containing text (case-insensitive).
CorksChatFilter.Entries = {}

-- Built from the checked entries by UpdateMatches, so each message is a table lookup.
CorksChatFilter.BlockedIds = {}
CorksChatFilter.BlockedTexts = {}

-- Last system message that reached chat, for the Block Last button.
CorksChatFilter.LastId = 0
CorksChatFilter.LastText = nil

-- Rows defined in CorksChatFilter.xml, presets included.
CorksChatFilter.MAX_ROWS = 30
CorksChatFilter.ROW_HEIGHT = 24
CorksChatFilter.ROW_WIDTH = 350
CorksChatFilter.SavedCount = 0

-- A check button changes its own pressed flag, possibly after our click handler runs,
-- so clicks only mark the list dirty and OnUpdate reads the buttons next frame.
CorksChatFilter.Dirty = false
CorksChatFilter.Initialized = false

-- The client's chat window shows the game's "Chat" log, and Lua can't take lines out
-- of it. While the filter is on, the log is copied into LOG without the blocked
-- messages and the chat window tabs show the copy instead (see the LogDisplay
-- wrappers at the bottom of this file).
CorksChatFilter.SOURCE_LOG = "Chat"
CorksChatFilter.LOG = "CorksChat"
CorksChatFilter.LOG_LIMIT = 1000
CorksChatFilter.Enabled = true
CorksChatFilter.Copying = false

-- Last "Chat" entry copied or skipped, and its index at the time.
CorksChatFilter.LastEntry = nil
CorksChatFilter.LastCount = 0

-- How far back from the end of "Chat" to look for LastEntry once the log is full
-- and old lines start dropping off the top.
CorksChatFilter.SCAN_LIMIT = 200

-- System messages OnChatText has seen, and whether each is blocked, waiting to be
-- matched to their "Chat" entry. The message event and the log entry can come in
-- either order, so a system entry with no match waits up to HOLD_TIME seconds.
CorksChatFilter.Arrived = {}
CorksChatFilter.ARRIVED_TIMEOUT = 5
CorksChatFilter.HOLD_TIME = 0.5
CorksChatFilter.HoldTimer = 0

-- Filter types (chat channels) added to LOG so far.
CorksChatFilter.LogFilters = {}

-- Index TextLogGetEntry uses for the oldest entry; nil until FindFirstIndex runs.
CorksChatFilter.FirstIndex = nil

-- Set to true to write what the filter sees (each message, each chat line copied or
-- skipped, which tabs were moved) to logs/CorksChatFilter.log.
CorksChatFilter.DEBUG = false
CorksChatFilter.DEBUG_LOG = "CorksChatFilterDebug"
CorksChatFilter.DebugStarted = false

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

-- Text for the debug log; wide strings and nil are fine.
function CorksChatFilter.DebugText(value)
	if type(value) ~= "string" then
		return tostring(value)
	end
	local ok, text = pcall(WStringToString, value)
	if ok and text then
		return text
	end
	return tostring(value)
end

function CorksChatFilter.Debug(text)
	if not CorksChatFilter.DEBUG then
		return
	end
	pcall(function()
		local log = CorksChatFilter.DEBUG_LOG
		if not CorksChatFilter.DebugStarted then
			CorksChatFilter.DebugStarted = true
			pcall(TextLogCreate, log, 1000)
			TextLogSetEnabled(log, true)
			TextLogClear(log)
			TextLogSetIncrementalSaving(log, true, "logs/CorksChatFilter.log")
			pcall(TextLogAddFilterType, log, 1, L"")
		end
		TextLogAddEntry(log, 1, StringToWString(text))
	end)
end

function CorksChatFilter.Initialize()
	SnapUtils.SnappableWindows["CorksChatFilter"] = true
	WindowUtils.RestoreWindowPosition("CorksChatFilter", false)
	WindowUtils.LoadScale("CorksChatFilter")
	WindowUtils.SetWindowTitle("CorksChatFilter", L"Corks' Chat Filter")

	ButtonSetCheckButtonFlag("CorksChatFilterEnableButton", true)
	LabelSetTextColor("CorksChatFilterEnableLabel", 255, 200, 50)
	LabelSetText("CorksChatFilterEnableLabel", L"Hide the checked system messages in chat")
	LabelSetText("CorksChatFilterLastHeader", L"Last system message:")
	LabelSetText("CorksChatFilterLastText", L"(none yet)")
	LabelSetText("CorksChatFilterTextLabel", L"Hide messages containing (press Enter):")
	ButtonSetText("CorksChatFilterBlockLastButton", L"Block Last")
	ButtonSetText("CorksChatFilterRemoveButton", L"Remove Unchecked")

	for i = 1, CorksChatFilter.MAX_ROWS do
		ButtonSetCheckButtonFlag(CorksChatFilter.RowName(i) .. "Button", true)
	end

	CorksChatFilter.Load()
	CorksChatFilter.BuildRows()
	CorksChatFilter.Initialized = true

	CorksChatFilter.Enabled = Interface.LoadBoolean("CorksChatFilterEnabled", true)
	ButtonSetPressedFlag("CorksChatFilterEnableButton", CorksChatFilter.Enabled)

	CorksChatFilter.HookOverhead()

	local blockedIds = {}
	for id in pairs(CorksChatFilter.BlockedIds) do
		table.insert(blockedIds, tostring(id))
	end
	CorksChatFilter.Debug("Initialize: enabled=" .. tostring(CorksChatFilter.Enabled)
		.. " wrappers=" .. tostring(LogDisplayAddLog == CorksChatFilter.Wrapped.LogDisplayAddLog)
		.. " SYSTEM=" .. tostring(SystemData.ChatLogFilters.SYSTEM)
		.. " blockedIds=" .. table.concat(blockedIds, ",")
		.. " blockedTexts=" .. table.getn(CorksChatFilter.BlockedTexts))

	if CorksChatFilter.Enabled then
		CorksChatFilter.StartCopy()
	end
end

-- Messages the client also draws over a character's head go through
-- OverheadText.ShowOverheadText, not the chat log, so blocked ones are stopped there.
function CorksChatFilter.HookOverhead()
	if CorksChatFilter.OriginalShowOverheadText or not OverheadText then
		return
	end
	CorksChatFilter.OriginalShowOverheadText = OverheadText.ShowOverheadText
	OverheadText.ShowOverheadText = function(...)
		if CorksChatFilter.CurrentBlocked() then
			CorksChatFilter.Debug("overhead hidden: " .. CorksChatFilter.DebugText(SystemData.Text))
			return
		end
		return CorksChatFilter.OriginalShowOverheadText(...)
	end
end

function CorksChatFilter.Shutdown()
	WindowUtils.SaveWindowPosition("CorksChatFilter")
	CorksChatFilter.SyncFromButtons()
end

function CorksChatFilter.Load()
	local entries = {}
	for _, preset in ipairs(CorksChatFilter.Presets) do
		local text = GetStringFromTid(preset.id)
		if not text or text == L"" then
			text = preset.label
		end
		table.insert(entries, {
			id     = preset.id,
			text   = text,
			on     = Interface.LoadBoolean("CorksChatFilterPreset" .. preset.id, false),
			preset = true,
		})
	end

	local count = Interface.LoadNumber("CorksChatFilterCount", 0)
	for i = 1, math.min(count, CorksChatFilter.MAX_ROWS - table.getn(entries)) do
		table.insert(entries, {
			id   = Interface.LoadNumber("CorksChatFilterId" .. i, 0),
			text = Interface.LoadWString("CorksChatFilterText" .. i, L""),
			on   = Interface.LoadBoolean("CorksChatFilterOn" .. i, true),
		})
	end

	CorksChatFilter.Entries = entries
	CorksChatFilter.SavedCount = count
	CorksChatFilter.UpdateMatches()
end

function CorksChatFilter.Save()
	local count = 0
	for _, entry in ipairs(CorksChatFilter.Entries) do
		if entry.preset then
			Interface.SaveBoolean("CorksChatFilterPreset" .. entry.id, entry.on)
		else
			count = count + 1
			Interface.SaveNumber("CorksChatFilterId" .. count, entry.id)
			Interface.SaveWString("CorksChatFilterText" .. count, entry.text)
			Interface.SaveBoolean("CorksChatFilterOn" .. count, entry.on)
		end
	end

	-- Drop settings left over from entries that were removed.
	for i = count + 1, CorksChatFilter.SavedCount do
		Interface.DeleteSetting("CorksChatFilterId" .. i)
		Interface.DeleteSetting("CorksChatFilterText" .. i)
		Interface.DeleteSetting("CorksChatFilterOn" .. i)
	end
	Interface.SaveNumber("CorksChatFilterCount", count)
	CorksChatFilter.SavedCount = count
end

function CorksChatFilter.UpdateMatches()
	CorksChatFilter.BlockedIds = {}
	CorksChatFilter.BlockedTexts = {}
	for _, entry in ipairs(CorksChatFilter.Entries) do
		if entry.on then
			if entry.id ~= 0 then
				CorksChatFilter.BlockedIds[entry.id] = true
			elseif entry.text ~= L"" then
				table.insert(CorksChatFilter.BlockedTexts, string.lower(WStringToString(entry.text)))
			end
		end
	end
end

-- id is the message's cliloc number, or 0 when it has none (or isn't known).
function CorksChatFilter.IsBlocked(id, text)
	if id ~= 0 and CorksChatFilter.BlockedIds[id] then
		return true
	end

	if table.getn(CorksChatFilter.BlockedTexts) > 0 then
		local lower = string.lower(WStringToString(text))
		for _, filter in ipairs(CorksChatFilter.BlockedTexts) do
			if string.find(lower, filter, 1, true) then
				return true
			end
		end
	end
	return false
end

-- Messages from the game rather than from players: system messages, and anything
-- with a cliloc number (players' own chat never has one). Some game messages come
-- on other channels, like "You have hidden yourself well." on the say channel.
function CorksChatFilter.IsGameMessage(channel, id)
	return channel == SystemData.ChatLogFilters.SYSTEM or (id ~= nil and id ~= 0)
end

-- Whether the message in SystemData right now should be hidden.
function CorksChatFilter.CurrentBlocked()
	local id = SystemData.TextID or 0
	return CorksChatFilter.Enabled and SystemData.Text ~= nil
		and CorksChatFilter.IsGameMessage(SystemData.TextChannelID, id)
		and CorksChatFilter.IsBlocked(id, SystemData.Text)
end

-- Called for every journal line from Interface.NewChatText.
-- Returns true when the line should be kept out of chat.
function CorksChatFilter.OnChatText()
	if not SystemData.Text then
		return false
	end
	local id = SystemData.TextID or 0
	local blocked = CorksChatFilter.CurrentBlocked()
	CorksChatFilter.Debug("message: channel=" .. CorksChatFilter.DebugText(SystemData.TextChannelID)
		.. " id=" .. CorksChatFilter.DebugText(id)
		.. " blocked=" .. tostring(blocked)
		.. " text=" .. CorksChatFilter.DebugText(SystemData.Text))

	-- Every message is recorded, so its chat log line is matched straight away
	-- instead of waiting out HOLD_TIME.
	if CorksChatFilter.Copying then
		table.insert(CorksChatFilter.Arrived, { text = SystemData.Text, channel = SystemData.TextChannelID, blocked = blocked, age = 0 })
	end
	if blocked then
		return true
	end
	if not CorksChatFilter.IsGameMessage(SystemData.TextChannelID, id) then
		return false
	end

	CorksChatFilter.LastId = id
	CorksChatFilter.LastText = SystemData.Text
	if DoesWindowNameExist("CorksChatFilterLastText") then
		LabelSetText("CorksChatFilterLastText", SystemData.Text)
	end
	return false
end

----------------------------------------------------------------
-- List
----------------------------------------------------------------

function CorksChatFilter.RowName(index)
	return "CorksChatFilterListScrollChildRow" .. index
end

function CorksChatFilter.BuildRows()
	local scrollChild = "CorksChatFilterListScrollChild"
	local total = table.getn(CorksChatFilter.Entries)

	for i = 1, CorksChatFilter.MAX_ROWS do
		local rowName = CorksChatFilter.RowName(i)
		local entry = CorksChatFilter.Entries[i]
		WindowSetShowing(rowName, entry ~= nil)
		if entry then
			ButtonSetPressedFlag(rowName .. "Button", entry.on)
			-- A label takes its color when its text is set, so set the color first.
			-- Presets are white, cliloc entries the player added are gold and text
			-- matches are light blue.
			if entry.preset then
				LabelSetTextColor(rowName .. "Label", 255, 255, 255)
				LabelSetText(rowName .. "Label", entry.text)
			elseif entry.id ~= 0 then
				LabelSetTextColor(rowName .. "Label", 255, 200, 50)
				LabelSetText(rowName .. "Label", entry.text)
			else
				LabelSetTextColor(rowName .. "Label", 140, 200, 255)
				LabelSetText(rowName .. "Label", L"Contains: " .. entry.text)
			end
		end
	end

	WindowSetDimensions(scrollChild, CorksChatFilter.ROW_WIDTH, math.max(total, 1) * CorksChatFilter.ROW_HEIGHT)
	ScrollWindowUpdateScrollRect("CorksChatFilterList")
end

function CorksChatFilter.SyncFromButtons()
	if not CorksChatFilter.Initialized then
		return
	end
	local changed = false
	for i, entry in ipairs(CorksChatFilter.Entries) do
		local button = CorksChatFilter.RowName(i) .. "Button"
		if DoesWindowNameExist(button) then
			local on = ButtonGetPressedFlag(button)
			if on ~= entry.on then
				entry.on = on
				changed = true
			end
		end
	end
	if changed then
		CorksChatFilter.UpdateMatches()
		CorksChatFilter.Save()
	end

	if DoesWindowNameExist("CorksChatFilterEnableButton") then
		local on = ButtonGetPressedFlag("CorksChatFilterEnableButton")
		if on ~= CorksChatFilter.Enabled then
			CorksChatFilter.SetEnabled(on)
		end
	end
end

function CorksChatFilter.SetEnabled(on)
	CorksChatFilter.Enabled = on
	Interface.SaveBoolean("CorksChatFilterEnabled", on)
	if on then
		CorksChatFilter.StartCopy()
	else
		CorksChatFilter.StopCopy()
	end
end

-- Adds a filter, or turns an existing one for the same message back on.
function CorksChatFilter.AddEntry(id, text)
	CorksChatFilter.SyncFromButtons()

	local lower = string.lower(WStringToString(text))
	local found = false
	for _, entry in ipairs(CorksChatFilter.Entries) do
		if (id ~= 0 and entry.id == id) or (id == 0 and entry.id == 0 and string.lower(WStringToString(entry.text)) == lower) then
			entry.on = true
			found = true
			break
		end
	end
	if not found then
		if table.getn(CorksChatFilter.Entries) >= CorksChatFilter.MAX_ROWS then
			WindowUtils.ChatPrint(L"Corks' Chat Filter: the list is full. Uncheck some entries and press Remove Unchecked.", SystemData.ChatLogFilters.SYSTEM)
			return false
		end
		table.insert(CorksChatFilter.Entries, { id = id, text = text, on = true })
	end

	CorksChatFilter.UpdateMatches()
	CorksChatFilter.Save()
	CorksChatFilter.BuildRows()
	return true
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CorksChatFilter.OnUpdate(timePassed)
	if CorksChatFilter.Dirty then
		CorksChatFilter.Dirty = false
		CorksChatFilter.SyncFromButtons()
	end
end

function CorksChatFilter.OnRowButton()
	CorksChatFilter.Dirty = true
end

-- Clicking the message text toggles its check box too.
function CorksChatFilter.OnRowLabel()
	local button = string.gsub(SystemData.ActiveWindow.name, "Label$", "Button")
	ButtonSetPressedFlag(button, not ButtonGetPressedFlag(button))
	CorksChatFilter.Dirty = true
end

function CorksChatFilter.OnBlockLast()
	if not CorksChatFilter.LastText then
		WindowUtils.ChatPrint(L"Corks' Chat Filter: no system message to block yet.", SystemData.ChatLogFilters.SYSTEM)
		return
	end
	-- Without a cliloc number the whole message becomes a text match.
	if not CorksChatFilter.AddEntry(CorksChatFilter.LastId, CorksChatFilter.LastText) then
		return
	end
	CorksChatFilter.LastId = 0
	CorksChatFilter.LastText = nil
	LabelSetText("CorksChatFilterLastText", L"(none yet)")
end

function CorksChatFilter.OnRemoveUnchecked()
	CorksChatFilter.SyncFromButtons()
	local kept = {}
	for _, entry in ipairs(CorksChatFilter.Entries) do
		if entry.preset or entry.on then
			table.insert(kept, entry)
		end
	end
	CorksChatFilter.Entries = kept
	CorksChatFilter.UpdateMatches()
	CorksChatFilter.Save()
	CorksChatFilter.BuildRows()
end

function CorksChatFilter.OnTextEnter()
	local text = WStringToString(TextEditBoxGetText("CorksChatFilterTextBox"))
	text = string.gsub(text, "^%s*(.-)%s*$", "%1")
	if text ~= "" then
		CorksChatFilter.AddEntry(0, StringToWString(text))
	end
	TextEditBoxSetText("CorksChatFilterTextBox", L"")
	WindowAssignFocus("CorksChatFilterTextBox", false)
end

function CorksChatFilter.OnTextEscape()
	WindowAssignFocus("CorksChatFilterTextBox", false)
end

function CorksChatFilter.Toggle()
	if not DoesWindowNameExist("CorksChatFilter") then
		return
	end
	local showing = WindowGetShowing("CorksChatFilter")
	if showing then
		CorksChatFilter.SyncFromButtons()
	end
	WindowSetShowing("CorksChatFilter", not showing)
end

function CorksChatFilter.OnClose()
	CorksChatFilter.SyncFromButtons()
	WindowSetShowing("CorksChatFilter", false)
end

----------------------------------------------------------------
-- Chat log copy
----------------------------------------------------------------

-- The LogDisplay of every chat window tab.
function CorksChatFilter.ChatDisplays()
	local displays = {}
	if ChatWindow and ChatWindow.Windows then
		for _, wnd in pairs(ChatWindow.Windows) do
			for _, tab in pairs(wnd.Tabs or {}) do
				if tab.tabWindow and DoesWindowNameExist(tab.tabWindow) then
					table.insert(displays, tab.tabWindow)
				end
			end
		end
	end
	return displays
end

-- Chat channels by filter id. Empty until the chat window module has set them up.
function CorksChatFilter.Channels()
	if ChatSettings and ChatSettings.Channels then
		return ChatSettings.Channels
	end
	return {}
end

-- A LogDisplay can only show a filter type that the log has.
function CorksChatFilter.AddLogFilter(filterType)
	if filterType ~= nil and not CorksChatFilter.LogFilters[filterType] then
		CorksChatFilter.LogFilters[filterType] = true
		-- The log survives a UI reload, so the type may already be there.
		pcall(TextLogAddFilterType, CorksChatFilter.LOG, filterType, L"")
	end
end

-- Points a chat tab at another log, keeping its channel filters and colors.
function CorksChatFilter.MoveDisplay(display, fromLog, toLog)
	local original = CorksChatFilter.Original
	original.LogDisplayAddLog(display, toLog, true)
	for channelId in pairs(CorksChatFilter.Channels()) do
		original.LogDisplaySetFilterState(display, toLog, channelId, original.LogDisplayGetFilterState(display, fromLog, channelId))
		local r, g, b = original.LogDisplayGetFilterColor(display, fromLog, channelId)
		if r then
			original.LogDisplaySetFilterColor(display, toLog, channelId, r, g, b)
		end
	end
	original.LogDisplayRemoveLog(display, fromLog)
end

-- If copying ever fails, the chat window goes back to the game's own log rather
-- than being left on a copy that no longer updates.
function CorksChatFilter.StartCopy()
	local ok, err = pcall(CorksChatFilter.DoStartCopy)
	if not ok then
		CorksChatFilter.CopyFailed(err)
	end
end

function CorksChatFilter.CopyFailed(err)
	pcall(CorksChatFilter.StopCopy)
	CorksChatFilter.Copying = false
	pcall(WindowUtils.ChatPrint, StringToWString("Corks' Chat Filter stopped filtering the chat window: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
end

function CorksChatFilter.DoStartCopy()
	if CorksChatFilter.Copying then
		return
	end

	-- After a UI reload the log is still there from last time.
	pcall(TextLogCreate, CorksChatFilter.LOG, CorksChatFilter.LOG_LIMIT)
	TextLogSetEnabled(CorksChatFilter.LOG, true)
	TextLogClear(CorksChatFilter.LOG)
	CorksChatFilter.LogFilters = {}
	for channelId in pairs(CorksChatFilter.Channels()) do
		CorksChatFilter.AddLogFilter(channelId)
	end

	-- Lines already in chat came in before the filter was running, so only the text
	-- matches can hide them.
	CorksChatFilter.Arrived = {}
	CorksChatFilter.HoldTimer = 0
	CorksChatFilter.LastEntry = nil
	CorksChatFilter.LastCount = 0
	CorksChatFilter.CopyNew(0, true)

	CorksChatFilter.Copying = true
	local displays = CorksChatFilter.ChatDisplays()
	CorksChatFilter.Debug("StartCopy: chat entries=" .. TextLogGetNumEntries(CorksChatFilter.SOURCE_LOG)
		.. " copied=" .. TextLogGetNumEntries(CorksChatFilter.LOG)
		.. " firstIndex=" .. tostring(CorksChatFilter.FirstIndex)
		.. " ChatWindow.Windows=" .. tostring(ChatWindow and ChatWindow.Windows ~= nil)
		.. " displays=" .. table.concat(displays, ","))
	for _, display in ipairs(displays) do
		CorksChatFilter.MoveDisplay(display, CorksChatFilter.SOURCE_LOG, CorksChatFilter.LOG)
	end
end

function CorksChatFilter.StopCopy()
	if not CorksChatFilter.Copying then
		return
	end
	CorksChatFilter.Copying = false
	for _, display in ipairs(CorksChatFilter.ChatDisplays()) do
		CorksChatFilter.MoveDisplay(display, CorksChatFilter.LOG, CorksChatFilter.SOURCE_LOG)
	end
	CorksChatFilter.Arrived = {}
end

-- For error messages: the type of each value, and the value when it's a number.
function CorksChatFilter.Describe(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		if type(value) == "number" then
			table.insert(parts, "number " .. value)
		else
			table.insert(parts, type(value))
		end
	end
	if table.getn(parts) == 0 then
		return "nothing"
	end
	return table.concat(parts, ", ")
end

-- Whether TextLogGetEntry has an entry at this index (an index out of range may
-- return nothing or raise an error).
function CorksChatFilter.HasEntry(index)
	local ok, _, filterType, text = pcall(TextLogGetEntry, CorksChatFilter.SOURCE_LOG, index)
	return ok and filterType ~= nil and text ~= nil
end

-- The docs number entries from 1, but that isn't certain, so the first index is
-- worked out from the log the first time it has something in it.
function CorksChatFilter.FindFirstIndex(count)
	if CorksChatFilter.HasEntry(0) and not CorksChatFilter.HasEntry(count) then
		CorksChatFilter.FirstIndex = 0
	elseif CorksChatFilter.HasEntry(1) then
		CorksChatFilter.FirstIndex = 1
	end
	if CorksChatFilter.FirstIndex then
		CorksChatFilter.Debug("FindFirstIndex: " .. CorksChatFilter.FirstIndex .. " (" .. count .. " entries)")
	else
		error("can't read the chat log (" .. count .. " entries). Entry 0 gave "
			.. CorksChatFilter.Describe(pcall(TextLogGetEntry, CorksChatFilter.SOURCE_LOG, 0))
			.. "; entry 1 gave " .. CorksChatFilter.Describe(pcall(TextLogGetEntry, CorksChatFilter.SOURCE_LOG, 1)))
	end
end

-- "Chat" entry by position, 1 being the oldest still in the log.
function CorksChatFilter.GetEntry(position)
	local index = position - 1 + CorksChatFilter.FirstIndex
	local timestamp, filterType, text = TextLogGetEntry(CorksChatFilter.SOURCE_LOG, index)
	if filterType == nil or text == nil then
		error("no chat log entry at index " .. index .. " of " .. TextLogGetNumEntries(CorksChatFilter.SOURCE_LOG)
			.. " (got " .. CorksChatFilter.Describe(timestamp, filterType, text) .. ")")
	end
	return timestamp, filterType, text
end

function CorksChatFilter.EntryMatches(position, entry)
	local timestamp, filterType, text = CorksChatFilter.GetEntry(position)
	return timestamp == entry.timestamp and filterType == entry.filterType and text == entry.text
end

-- Index of the first "Chat" entry not yet copied, or nil when there's nothing new.
function CorksChatFilter.FindStart(count)
	local last = CorksChatFilter.LastEntry
	if count == 0 then
		CorksChatFilter.LastEntry = nil
		CorksChatFilter.LastCount = 0
		return nil
	end
	if not last then
		return 1
	end

	-- Usually the log has only grown, so the last copied entry is where it was.
	local lastCount = CorksChatFilter.LastCount
	if lastCount <= count and CorksChatFilter.EntryMatches(lastCount, last) then
		if lastCount == count then
			return nil
		end
		return lastCount + 1
	end

	-- Once the log is full, old lines drop off the top and the entry moves up.
	for i = count, math.max(1, count - CorksChatFilter.SCAN_LIMIT), -1 do
		if CorksChatFilter.EntryMatches(i, last) then
			CorksChatFilter.LastCount = i
			if i == count then
				return nil
			end
			return i + 1
		end
	end

	-- Not found: the log was cleared, or more arrived at once than SCAN_LIMIT.
	return math.max(1, count - CorksChatFilter.SCAN_LIMIT + 1)
end

-- The Arrived message a "Chat" entry came from: same channel, and the entry ends
-- with the message (it can have a name in front, like "[Mystic]: ").
function CorksChatFilter.FindArrived(text, filterType)
	local length = wstring.len(text)
	for index, arrived in ipairs(CorksChatFilter.Arrived) do
		local arrivedLength = wstring.len(arrived.text)
		if arrived.channel == filterType and arrivedLength > 0 and arrivedLength <= length
			and wstring.sub(text, length - arrivedLength + 1) == arrived.text then
			return index
		end
	end
	return nil
end

-- history: copying lines that were in chat before the filter started, which have
-- no Arrived messages to wait for.
function CorksChatFilter.CopyNew(timePassed, history)
	local count = TextLogGetNumEntries(CorksChatFilter.SOURCE_LOG)
	if count > 0 and not CorksChatFilter.FirstIndex then
		CorksChatFilter.FindFirstIndex(count)
	end
	local start = CorksChatFilter.FindStart(count)
	if not start then
		return
	end

	for i = start, count do
		local timestamp, filterType, text = CorksChatFilter.GetEntry(i)
		local show = true
		if CorksChatFilter.Enabled then
			local index = CorksChatFilter.FindArrived(text, filterType)
			if index then
				show = not CorksChatFilter.Arrived[index].blocked
				table.remove(CorksChatFilter.Arrived, index)
			elseif not history and CorksChatFilter.HoldTimer < CorksChatFilter.HOLD_TIME then
				-- Its message hasn't come through OnChatText yet; look again next frame.
				if CorksChatFilter.HoldTimer == 0 then
					CorksChatFilter.Debug("hold " .. i .. ": " .. CorksChatFilter.DebugText(text))
				end
				CorksChatFilter.HoldTimer = CorksChatFilter.HoldTimer + timePassed
				return
			elseif filterType == SystemData.ChatLogFilters.SYSTEM then
				-- No message to go by (printed by the UI, or from before the filter
				-- started), so only the text matches apply, and only to system lines.
				show = not CorksChatFilter.IsBlocked(0, text)
			end
		end
		CorksChatFilter.HoldTimer = 0

		CorksChatFilter.Debug("copy " .. i .. "/" .. count .. ": filter=" .. tostring(filterType)
			.. " show=" .. tostring(show) .. " text=" .. CorksChatFilter.DebugText(text))
		if show then
			CorksChatFilter.AddLogFilter(filterType)
			TextLogAddEntry(CorksChatFilter.LOG, filterType, text)
		end
		CorksChatFilter.LastEntry = { timestamp = timestamp, filterType = filterType, text = text }
		CorksChatFilter.LastCount = i
	end
end

-- Called every frame from Interface.Update.
function CorksChatFilter.OnLogUpdate(timePassed)
	if not CorksChatFilter.Copying then
		return
	end
	for i = table.getn(CorksChatFilter.Arrived), 1, -1 do
		local arrived = CorksChatFilter.Arrived[i]
		arrived.age = arrived.age + timePassed
		if arrived.age > CorksChatFilter.ARRIVED_TIMEOUT then
			table.remove(CorksChatFilter.Arrived, i)
		end
	end
	local ok, err = pcall(CorksChatFilter.CopyNew, timePassed, false)
	if not ok then
		CorksChatFilter.CopyFailed(err)
	end
end

----------------------------------------------------------------
-- LogDisplay wrappers
----------------------------------------------------------------

-- The chat window code names the "Chat" log for its tabs: adding it, filters,
-- colors and the saved tab settings. While copying, these calls go to the copy
-- instead, so tabs made later, and changes from the chat options, still work.
CorksChatFilter.Original = {
	LogDisplayAddLog         = LogDisplayAddLog,
	LogDisplayRemoveLog      = LogDisplayRemoveLog,
	LogDisplaySetFilterState = LogDisplaySetFilterState,
	LogDisplayGetFilterState = LogDisplayGetFilterState,
	LogDisplaySetFilterColor = LogDisplaySetFilterColor,
	LogDisplayGetFilterColor = LogDisplayGetFilterColor,
}

function CorksChatFilter.LogName(logName)
	if CorksChatFilter.Copying and logName == CorksChatFilter.SOURCE_LOG then
		return CorksChatFilter.LOG
	end
	return logName
end

function LogDisplayAddLog(display, logName, addEntries)
	CorksChatFilter.Debug("LogDisplayAddLog " .. tostring(display) .. " " .. tostring(logName) .. " -> " .. tostring(CorksChatFilter.LogName(logName)))
	return CorksChatFilter.Original.LogDisplayAddLog(display, CorksChatFilter.LogName(logName), addEntries)
end

function LogDisplayRemoveLog(display, logName)
	return CorksChatFilter.Original.LogDisplayRemoveLog(display, CorksChatFilter.LogName(logName))
end

function LogDisplaySetFilterState(display, logName, filterType, state)
	logName = CorksChatFilter.LogName(logName)
	if logName == CorksChatFilter.LOG then
		CorksChatFilter.AddLogFilter(filterType)
	end
	return CorksChatFilter.Original.LogDisplaySetFilterState(display, logName, filterType, state)
end

function LogDisplayGetFilterState(display, logName, filterType)
	return CorksChatFilter.Original.LogDisplayGetFilterState(display, CorksChatFilter.LogName(logName), filterType)
end

function LogDisplaySetFilterColor(display, logName, filterType, r, g, b)
	logName = CorksChatFilter.LogName(logName)
	if logName == CorksChatFilter.LOG then
		CorksChatFilter.AddLogFilter(filterType)
	end
	return CorksChatFilter.Original.LogDisplaySetFilterColor(display, logName, filterType, r, g, b)
end

function LogDisplayGetFilterColor(display, logName, filterType)
	return CorksChatFilter.Original.LogDisplayGetFilterColor(display, CorksChatFilter.LogName(logName), filterType)
end

-- So Initialize can check the wrappers are the ones in use.
CorksChatFilter.Wrapped = { LogDisplayAddLog = LogDisplayAddLog }
