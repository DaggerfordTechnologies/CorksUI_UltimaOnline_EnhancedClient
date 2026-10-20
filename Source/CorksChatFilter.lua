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

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksChatFilter.Initialize()
	SnapUtils.SnappableWindows["CorksChatFilter"] = true
	WindowUtils.RestoreWindowPosition("CorksChatFilter", false)
	WindowUtils.LoadScale("CorksChatFilter")
	WindowUtils.SetWindowTitle("CorksChatFilter", L"Corks' Chat Filter")

	LabelSetText("CorksChatFilterHeader", L"Checked system messages are hidden from chat:")
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

-- Called for every journal line from Interface.NewChatText.
-- Returns true when the line should be kept out of chat.
function CorksChatFilter.OnChatText()
	if not SystemData.Text or SystemData.TextChannelID ~= SystemData.ChatLogFilters.SYSTEM then
		return false
	end

	local id = SystemData.TextID or 0
	if id ~= 0 and CorksChatFilter.BlockedIds[id] then
		return true
	end

	if table.getn(CorksChatFilter.BlockedTexts) > 0 then
		local text = string.lower(WStringToString(SystemData.Text))
		for _, filter in ipairs(CorksChatFilter.BlockedTexts) do
			if string.find(text, filter, 1, true) then
				return true
			end
		end
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
