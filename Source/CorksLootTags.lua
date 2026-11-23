----------------------------------------------------------------
-- Corks' Loot Tags
----------------------------------------------------------------
-- Marks items in container grid view by reading their properties: a short tag
-- in the corner of the slot (LA, GA, LGND, SP20, PARA...) and a tint on the slot,
-- plus a gold tint for items containing words the player picks.
--
-- Works by wrapping the default ContainerWindow rather than replacing it:
--  * ContainerWindow.UpdateObject draws one item; the tag goes on afterwards.
--  * ContainerWindow.UpdateContents redraws a whole container; the tints are
--    taken off first (the stock code clears the labels itself), and its calls to
--    UpdateObject put them back.
-- Item properties can arrive after the item is drawn, so those items wait in
-- Pending and OnUpdate tags them when the properties come in.
--
-- Matching is by the English property text, as the client shows it.

CorksLootTags = {}

-- Colors for the slot tints (multiplied over the slot art)
CorksLootTags.COLOR = {
	magic     = { 80, 140, 255 },
	minor     = { 60, 220, 90 },
	greater   = { 255, 230, 60 },
	major     = { 255, 140, 30 },
	legendary = { 200, 80, 255 },
	splinter  = { 60, 220, 230 },
	para      = { 255, 60, 60 },
	highlight = { 255, 200, 0 },
}

-- Rarity names in the item properties (lower case), the tag and the tint.
-- Each list is checked in order and the first match is used.
CorksLootTags.MAGIC = {
	{ "minor magic item",   "mM", "magic" },
	{ "lesser magic item",  "LM", "magic" },
	{ "greater magic item", "GM", "magic" },
	{ "major magic item",   "MM", "magic" },
}
CorksLootTags.ARTIFACT = {
	{ "legendary artifact", "LGND", "legendary" },
	{ "major artifact",     "MA",   "major" },
	{ "greater artifact",   "GA",   "greater" },
	{ "lesser artifact",    "LA",   "minor" },
	{ "minor artifact",     "mA",   "minor" },
}

-- Window rows, in order. Fields: header (title row), key (setting
-- "CorksLootTags" .. key), label, color (COLOR key, for the label), default.
CorksLootTags.Options = {
	{ key = "Enabled",  label = L"Tag items in container grid view", gold = true },
	{ key = "Labels",   label = L"Show a short tag on the item" },
	{ key = "Tint",     label = L"Tint the item's slot" },
	{ header = L"Tag these" },
	{ key = "Artifact", label = L"Artifacts (mA, LA, GA, MA, LGND)", color = "greater" },
	{ key = "Rarity",   label = L"Artifact rarity (AR and the number)", color = "major" },
	{ key = "Splinter", label = L"Splintering weapons (SP and the %)", color = "splinter" },
	{ key = "Para",     label = L"Reactive paralyze (PARA)", color = "para" },
	{ key = "Magic",    label = L"Magic items (mM, LM, GM, MM)", color = "magic", default = false },
	{ header = L"Highlight items whose name or properties contain" },
}

CorksLootTags.MAX_WORDS = 10
-- Rows defined in CorksLootTags.xml; keep in sync
CorksLootTags.MAX_ROWS = 20
CorksLootTags.ROW_HEIGHT = 24
CorksLootTags.ROW_WIDTH = 330

-- How often pending items are checked, and how long to wait for their properties
CorksLootTags.CHECK_EVERY = 0.5
CorksLootTags.GIVE_UP_AFTER = 10

CorksLootTags.On = {}          -- option key -> true/false
CorksLootTags.Words = {}       -- { text = wstring, lower = string, on = bool }
CorksLootTags.SavedWordCount = 0
CorksLootTags.Loaded = false

CorksLootTags.TextCache = {}   -- objectId -> lower-case name and properties
CorksLootTags.TagCache = {}    -- objectId -> tag table, or false for no tag
CorksLootTags.Requested = {}   -- objectId -> true while its properties are registered
CorksLootTags.Pending = {}     -- objectId -> seconds waited
CorksLootTags.Tinted = {}      -- socket name -> { r, g, b, container = id }: the tint it had before
CorksLootTags.Hooked = false
CorksLootTags.Clock = 0
CorksLootTags.Dirty = false
CorksLootTags.Initialized = false

----------------------------------------------------------------
-- Settings
----------------------------------------------------------------

function CorksLootTags.Load()
	if CorksLootTags.Loaded then
		return
	end
	for _, option in ipairs(CorksLootTags.Options) do
		if option.key then
			CorksLootTags.On[option.key] = Interface.LoadBoolean("CorksLootTags" .. option.key, option.default ~= false)
		end
	end
	local words = {}
	local count = Interface.LoadNumber("CorksLootTagsWordCount", 0)
	for i = 1, math.min(count, CorksLootTags.MAX_WORDS) do
		local text = Interface.LoadWString("CorksLootTagsWord" .. i, L"")
		if text ~= L"" then
			table.insert(words, {
				text  = text,
				lower = string.lower(WStringToString(text)),
				on    = Interface.LoadBoolean("CorksLootTagsWordOn" .. i, true),
			})
		end
	end
	CorksLootTags.Words = words
	CorksLootTags.SavedWordCount = count
	CorksLootTags.Loaded = true
end

function CorksLootTags.IsOn(key)
	CorksLootTags.Load()
	return CorksLootTags.On[key] == true
end

function CorksLootTags.SetOn(key, on)
	CorksLootTags.On[key] = on
	Interface.SaveBoolean("CorksLootTags" .. key, on)
end

function CorksLootTags.SaveWords()
	local count = 0
	for _, word in ipairs(CorksLootTags.Words) do
		count = count + 1
		Interface.SaveWString("CorksLootTagsWord" .. count, word.text)
		Interface.SaveBoolean("CorksLootTagsWordOn" .. count, word.on)
	end
	for i = count + 1, CorksLootTags.SavedWordCount do
		Interface.DeleteSetting("CorksLootTagsWord" .. i)
		Interface.DeleteSetting("CorksLootTagsWordOn" .. i)
	end
	Interface.SaveNumber("CorksLootTagsWordCount", count)
	CorksLootTags.SavedWordCount = count
end

----------------------------------------------------------------
-- Reading items
----------------------------------------------------------------

function CorksLootTags.ToText(value)
	if value == nil then
		return nil
	end
	if type(value) == "number" then
		return tostring(value)
	end
	local isWide = wstring ~= nil and pcall(wstring.len, value)
	if not isWide and type(value) == "string" then
		return value
	end
	local ok, text = pcall(WStringToString, value)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

-- An item's lower-case name and properties, or nil while they haven't arrived.
-- Asks the client for them the first time and keeps the request open until
-- they come, so they load without hovering the item.
function CorksLootTags.ItemText(objectId)
	local cached = CorksLootTags.TextCache[objectId]
	if cached then
		return cached
	end
	local data = WindowData.ItemProperties[objectId]
	if not data and not CorksLootTags.Requested[objectId] then
		CorksLootTags.Requested[objectId] = true
		pcall(RegisterWindowData, WindowData.ItemProperties.Type, objectId)
		data = WindowData.ItemProperties[objectId]
	end
	if type(data) ~= "table" or type(data.PropertiesList) ~= "table" or #data.PropertiesList == 0 then
		return nil
	end
	local parts = {}
	for _, line in ipairs(data.PropertiesList) do
		local ok, plain = pcall(WindowUtils.translateMarkup, line)
		local text = CorksLootTags.ToText(ok and plain or line)
		if text then
			table.insert(parts, text)
		end
	end
	if #parts == 0 then
		return nil
	end
	local text = string.lower(table.concat(parts, " | "))
	CorksLootTags.TextCache[objectId] = text
	CorksLootTags.ReleaseRequest(objectId)
	return text
end

function CorksLootTags.ReleaseRequest(objectId)
	if CorksLootTags.Requested[objectId] then
		CorksLootTags.Requested[objectId] = nil
		pcall(UnregisterWindowData, WindowData.ItemProperties.Type, objectId)
	end
end

-- The tag for an item's text: { label = wstring or nil, color = COLOR key or nil },
-- or false when nothing applies. The label shows the most useful match
-- (splintering, then paralyze, then rarity); the tint prefers a highlight word.
function CorksLootTags.Classify(text)
	local On = CorksLootTags.On
	local label, color

	if On.Splinter then
		local percent = string.match(text, "splintering weapon%s*(%d+)")
		if percent or string.find(text, "splintering weapon", 1, true) then
			label = "SP" .. (percent or "")
			color = "splinter"
		end
	end
	if On.Para and string.find(text, "reactive paralyze", 1, true) then
		label = label or "PARA"
		color = color or "para"
	end
	if On.Artifact then
		for _, tier in ipairs(CorksLootTags.ARTIFACT) do
			if string.find(text, tier[1], 1, true) then
				label = label or tier[2]
				color = color or tier[3]
				break
			end
		end
	end
	if On.Rarity then
		local rarity = tonumber(string.match(text, "artifact rarity%s*(%d+)"))
		if rarity then
			label = label or ("AR" .. rarity)
			if not color then
				if rarity >= 11 then
					color = "legendary"
				elseif rarity >= 9 then
					color = "major"
				elseif rarity >= 6 then
					color = "greater"
				else
					color = "minor"
				end
			end
		end
	end
	if On.Magic then
		for _, tier in ipairs(CorksLootTags.MAGIC) do
			if string.find(text, tier[1], 1, true) then
				label = label or tier[2]
				color = color or tier[3]
				break
			end
		end
	end
	for _, word in ipairs(CorksLootTags.Words) do
		if word.on and word.lower ~= "" and string.find(text, word.lower, 1, true) then
			color = "highlight"
			break
		end
	end

	if not label and not color then
		return false
	end
	return { label = label and StringToWString(label), color = color }
end

-- The item's tag, false for none, or nil while its properties haven't arrived
function CorksLootTags.TagFor(objectId)
	local cached = CorksLootTags.TagCache[objectId]
	if cached ~= nil then
		return cached
	end
	local text = CorksLootTags.ItemText(objectId)
	if not text then
		return nil
	end
	local tag = CorksLootTags.Classify(text)
	CorksLootTags.TagCache[objectId] = tag
	return tag
end

----------------------------------------------------------------
-- Drawing on the container slots
----------------------------------------------------------------

-- The grid slot an item is drawn in, or nil (not in grid view, not in this window)
function CorksLootTags.SocketOf(windowName, objectId)
	if not DoesWindowNameExist(windowName) then
		return nil
	end
	local containerId = WindowGetId(windowName)
	if ContainerWindow.ViewModes[containerId] ~= "Grid" then
		return nil
	end
	local info = WindowData.ObjectInfo[objectId]
	local data = WindowData.ContainerWindow[containerId]
	if not info or info.containerId ~= containerId or not data or not data.ContainedItems then
		return nil
	end
	for i = 1, data.numItems or 0 do
		local item = data.ContainedItems[i]
		if item and item.objectId == objectId then
			local socket = windowName .. "GridViewSocket" .. item.gridIndex
			if DoesWindowNameExist(socket) then
				return socket, containerId
			end
			return nil
		end
	end
	return nil
end

function CorksLootTags.Untint(socket)
	local saved = CorksLootTags.Tinted[socket]
	if not saved then
		return
	end
	CorksLootTags.Tinted[socket] = nil
	if DoesWindowNameExist(socket) then
		WindowSetTintColor(socket, saved[1], saved[2], saved[3])
	end
end

function CorksLootTags.Apply(socket, containerId, tag)
	CorksLootTags.Untint(socket)
	if not tag then
		return
	end
	if tag.color and CorksLootTags.On.Tint then
		local r, g, b = WindowGetTintColor(socket)
		CorksLootTags.Tinted[socket] = { r, g, b, container = containerId }
		local c = CorksLootTags.COLOR[tag.color]
		WindowSetTintColor(socket, c[1], c[2], c[3])
	end
	-- The stock code puts a stack's amount or an item's charges here; leave those
	local label = socket .. "Quantity"
	if tag.label and CorksLootTags.On.Labels and DoesWindowNameExist(label) and LabelGetText(label) == L"" then
		LabelSetText(label, tag.label)
	end
end

-- Called after the stock ContainerWindow.UpdateObject draws an item
function CorksLootTags.TagItem(windowName, objectId)
	if not CorksLootTags.IsOn("Enabled") then
		return
	end
	local socket, containerId = CorksLootTags.SocketOf(windowName, objectId)
	if not socket then
		return
	end
	local tag = CorksLootTags.TagFor(objectId)
	if tag == nil then
		CorksLootTags.Untint(socket)
		CorksLootTags.Pending[objectId] = CorksLootTags.Pending[objectId] or 0
		return
	end
	CorksLootTags.Pending[objectId] = nil
	CorksLootTags.Apply(socket, containerId, tag)
end

-- Called before the stock ContainerWindow.UpdateContents redraws a container
function CorksLootTags.ClearContainer(containerId)
	for socket, saved in pairs(CorksLootTags.Tinted) do
		if saved.container == containerId then
			CorksLootTags.Untint(socket)
		end
	end
end

function CorksLootTags.InstallHook()
	if CorksLootTags.Hooked or not ContainerWindow
		or type(ContainerWindow.UpdateObject) ~= "function"
		or type(ContainerWindow.UpdateContents) ~= "function" then
		return
	end
	local updateObject = ContainerWindow.UpdateObject
	local updateContents = ContainerWindow.UpdateContents
	ContainerWindow.UpdateObject = function(windowName, objectId, ...)
		local result = updateObject(windowName, objectId, ...)
		pcall(CorksLootTags.TagItem, windowName, objectId)
		return result
	end
	ContainerWindow.UpdateContents = function(containerId, ...)
		pcall(CorksLootTags.ClearContainer, containerId)
		return updateContents(containerId, ...)
	end
	CorksLootTags.Hooked = true
end

-- Redraws the open containers, after the settings change
function CorksLootTags.Refresh()
	CorksLootTags.TagCache = {}
	CorksLootTags.Pending = {}
	for containerId in pairs(ContainerWindow.OpenContainers or {}) do
		CorksLootTags.ClearContainer(containerId)
		pcall(ContainerWindow.UpdateContents, containerId)
	end
end

-- Tags the items whose properties have come in since they were drawn
function CorksLootTags.OnUpdate(timePassed)
	CorksLootTags.Clock = CorksLootTags.Clock + (timePassed or 0)
	if CorksLootTags.Clock < CorksLootTags.CHECK_EVERY then
		return
	end
	local elapsed = CorksLootTags.Clock
	CorksLootTags.Clock = 0
	if next(CorksLootTags.Pending) == nil then
		return
	end
	for objectId, waited in pairs(CorksLootTags.Pending) do
		local tag = CorksLootTags.TagFor(objectId)
		if tag ~= nil then
			CorksLootTags.Pending[objectId] = nil
			local info = WindowData.ObjectInfo[objectId]
			if tag and info then
				local windowName = "ContainerWindow_" .. tostring(info.containerId)
				local socket, containerId = CorksLootTags.SocketOf(windowName, objectId)
				if socket then
					CorksLootTags.Apply(socket, containerId, tag)
				end
			end
		elseif waited + elapsed >= CorksLootTags.GIVE_UP_AFTER then
			CorksLootTags.Pending[objectId] = nil
			CorksLootTags.ReleaseRequest(objectId)
		else
			CorksLootTags.Pending[objectId] = waited + elapsed
		end
	end
end

----------------------------------------------------------------
-- Window
----------------------------------------------------------------

function CorksLootTags.RowName(index)
	return "CorksLootTagsListScrollChildRow" .. index
end

-- What each window row shows: the options, then one row per word
function CorksLootTags.Rows()
	local rows = {}
	for _, option in ipairs(CorksLootTags.Options) do
		table.insert(rows, option)
	end
	for _, word in ipairs(CorksLootTags.Words) do
		table.insert(rows, { word = word })
	end
	return rows
end

function CorksLootTags.Initialize()
	SnapUtils.SnappableWindows["CorksLootTags"] = true
	WindowUtils.RestoreWindowPosition("CorksLootTags", false)
	WindowUtils.LoadScale("CorksLootTags")
	WindowUtils.SetWindowTitle("CorksLootTags", L"Corks' Loot Tags")

	LabelSetText("CorksLootTagsTextLabel", L"Highlight items containing (press Enter):")
	ButtonSetText("CorksLootTagsRemoveButton", L"Remove Unchecked")

	for i = 1, CorksLootTags.MAX_ROWS do
		ButtonSetCheckButtonFlag(CorksLootTags.RowName(i) .. "Button", true)
	end

	CorksLootTags.Load()
	CorksLootTags.BuildRows()
	CorksLootTags.Initialized = true
end

function CorksLootTags.Shutdown()
	WindowUtils.SaveWindowPosition("CorksLootTags")
	CorksLootTags.SyncFromButtons()
end

function CorksLootTags.BuildRows()
	local rows = CorksLootTags.Rows()
	for i = 1, CorksLootTags.MAX_ROWS do
		local rowName = CorksLootTags.RowName(i)
		local row = rows[i]
		WindowSetShowing(rowName, row ~= nil)
		if row then
			local button, label = rowName .. "Button", rowName .. "Label"
			WindowClearAnchors(label)
			-- A label takes its color when its text is set, so set the color first
			if row.header then
				WindowSetShowing(button, false)
				WindowAddAnchor(label, "left", rowName, "left", 5, 0)
				LabelSetTextColor(label, 255, 200, 50)
				LabelSetText(label, row.header)
			else
				WindowSetShowing(button, true)
				WindowAddAnchor(label, "right", button, "left", 8, 0)
				if row.word then
					ButtonSetPressedFlag(button, row.word.on)
					local c = CorksLootTags.COLOR.highlight
					LabelSetTextColor(label, c[1], c[2], c[3])
					LabelSetText(label, row.word.text)
				else
					ButtonSetPressedFlag(button, CorksLootTags.IsOn(row.key))
					local c = row.color and CorksLootTags.COLOR[row.color]
					if row.gold then
						LabelSetTextColor(label, 255, 200, 50)
					elseif c then
						LabelSetTextColor(label, c[1], c[2], c[3])
					else
						LabelSetTextColor(label, 255, 255, 255)
					end
					LabelSetText(label, row.label)
				end
			end
		end
	end
	WindowSetDimensions("CorksLootTagsListScrollChild", CorksLootTags.ROW_WIDTH, math.max(table.getn(rows), 1) * CorksLootTags.ROW_HEIGHT)
	ScrollWindowUpdateScrollRect("CorksLootTagsList")
end

-- A check button changes its own pressed flag, possibly after the click handler
-- runs, so clicks only mark the list dirty and OnWindowUpdate reads the buttons next frame.
function CorksLootTags.SyncFromButtons()
	if not CorksLootTags.Initialized then
		return
	end
	local changed, wordsChanged = false, false
	for i, row in ipairs(CorksLootTags.Rows()) do
		local button = CorksLootTags.RowName(i) .. "Button"
		if i <= CorksLootTags.MAX_ROWS and DoesWindowNameExist(button) and not row.header then
			local on = ButtonGetPressedFlag(button)
			if row.word then
				if on ~= row.word.on then
					row.word.on = on
					wordsChanged = true
				end
			elseif on ~= CorksLootTags.IsOn(row.key) then
				CorksLootTags.SetOn(row.key, on)
				changed = true
			end
		end
	end
	if wordsChanged then
		CorksLootTags.SaveWords()
	end
	if changed or wordsChanged then
		CorksLootTags.Refresh()
	end
end

function CorksLootTags.AddWord(text)
	CorksLootTags.SyncFromButtons()
	local lower = string.lower(WStringToString(text))
	for _, word in ipairs(CorksLootTags.Words) do
		if word.lower == lower then
			word.on = true
			CorksLootTags.SaveWords()
			CorksLootTags.BuildRows()
			CorksLootTags.Refresh()
			return
		end
	end
	if table.getn(CorksLootTags.Words) >= CorksLootTags.MAX_WORDS then
		WindowUtils.ChatPrint(L"Corks' Loot Tags: the word list is full. Uncheck some words and press Remove Unchecked.", SystemData.ChatLogFilters.SYSTEM)
		return
	end
	table.insert(CorksLootTags.Words, { text = text, lower = lower, on = true })
	CorksLootTags.SaveWords()
	CorksLootTags.BuildRows()
	CorksLootTags.Refresh()
end

function CorksLootTags.OnWindowUpdate()
	if CorksLootTags.Dirty then
		CorksLootTags.Dirty = false
		CorksLootTags.SyncFromButtons()
	end
end

function CorksLootTags.OnRowButton()
	CorksLootTags.Dirty = true
end

-- Clicking a row's text toggles its check box too
function CorksLootTags.OnRowLabel()
	local button = string.gsub(SystemData.ActiveWindow.name, "Label$", "Button")
	if DoesWindowNameExist(button) and WindowGetShowing(button) then
		ButtonSetPressedFlag(button, not ButtonGetPressedFlag(button))
		CorksLootTags.Dirty = true
	end
end

function CorksLootTags.OnRemoveUnchecked()
	CorksLootTags.SyncFromButtons()
	local kept = {}
	for _, word in ipairs(CorksLootTags.Words) do
		if word.on then
			table.insert(kept, word)
		end
	end
	CorksLootTags.Words = kept
	CorksLootTags.SaveWords()
	CorksLootTags.BuildRows()
	CorksLootTags.Refresh()
end

function CorksLootTags.OnTextEnter()
	local text = WStringToString(TextEditBoxGetText("CorksLootTagsTextBox"))
	text = string.gsub(text, "^%s*(.-)%s*$", "%1")
	if text ~= "" then
		CorksLootTags.AddWord(StringToWString(text))
	end
	TextEditBoxSetText("CorksLootTagsTextBox", L"")
	WindowAssignFocus("CorksLootTagsTextBox", false)
end

function CorksLootTags.OnTextEscape()
	WindowAssignFocus("CorksLootTagsTextBox", false)
end

function CorksLootTags.Toggle()
	local open = DoesWindowNameExist("CorksLootTags") and WindowGetShowing("CorksLootTags")
	CorksLootTags.SetOpen(not open)
end

-- Right-click closes the window until the action opens it again
function CorksLootTags.OnClose()
	CorksLootTags.SetOpen(false)
end

function CorksLootTags.SetOpen(open)
	Interface.SaveBoolean("CorksLootTagsOpen", open)
	if not DoesWindowNameExist("CorksLootTags") then
		if open then
			CreateWindow("CorksLootTags", true)
		end
		return
	end
	if not open then
		CorksLootTags.SyncFromButtons()
	end
	WindowSetShowing("CorksLootTags", open)
end
