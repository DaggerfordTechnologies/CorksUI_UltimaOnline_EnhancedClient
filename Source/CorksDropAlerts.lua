----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksDropAlerts = {}

-- The Event Drops window. It keeps a list of drop messages: when a game message
-- containing one of the checked ones arrives, the artifact graphic shows over your
-- head and the drop is counted. Counts are for this session only (they start at 0
-- after logging in or reloading the UI); the messages themselves are saved.

-- Messages added the first time the window loads, before any are saved.
CorksDropAlerts.DEFAULT_MESSAGES = {
	L"You recover an artifact bearing the mark of the Unhallowed",
}

-- The default UI already shows the artifact graphic for these (TextParsing.lua), so
-- they're counted here but don't show it a second time.
CorksDropAlerts.DEFAULT_UI_ARTIFACT_IDS = {
	[1062317] = true,  -- "For your valor in combating the fallen beast, a special artifact has been bestowed on you."
	[502088]  = true,  -- "A special gift has been placed in your backpack."
	[1154530] = true,  -- "You notice the crest of Minax on your fallen foe's equipment..."
	[1154554] = true,  -- "You recover an artifact bearing the crest of Minax from the rubble."
}

-- Rows defined in CorksDropAlerts.xml.
CorksDropAlerts.MAX_ROWS = 10

-- { text = wstring, lower = string, on = boolean, count = number }
CorksDropAlerts.Entries = {}
CorksDropAlerts.Total = 0
CorksDropAlerts.SavedCount = 0
CorksDropAlerts.Loaded = false

----------------------------------------------------------------
-- Saved messages
----------------------------------------------------------------

function CorksDropAlerts.Load()
	if CorksDropAlerts.Loaded then
		return
	end
	CorksDropAlerts.Loaded = true

	local count = Interface.LoadNumber("CorksDropAlertsCount", -1)
	if count < 0 then
		-- Never saved: start with the defaults.
		for _, text in ipairs(CorksDropAlerts.DEFAULT_MESSAGES) do
			CorksDropAlerts.AddEntry(text)
		end
		CorksDropAlerts.Save()
		return
	end

	for i = 1, math.min(count, CorksDropAlerts.MAX_ROWS) do
		local text = Interface.LoadWString("CorksDropAlertsText" .. i, L"")
		if text ~= L"" then
			table.insert(CorksDropAlerts.Entries, {
				text  = text,
				lower = string.lower(WStringToString(text)),
				on    = Interface.LoadBoolean("CorksDropAlertsOn" .. i, true),
				count = 0,
			})
		end
	end
	CorksDropAlerts.SavedCount = count
end

function CorksDropAlerts.Save()
	local count = 0
	for _, entry in ipairs(CorksDropAlerts.Entries) do
		count = count + 1
		Interface.SaveWString("CorksDropAlertsText" .. count, entry.text)
		Interface.SaveBoolean("CorksDropAlertsOn" .. count, entry.on)
	end
	-- Drop settings left over from messages that were removed.
	for i = count + 1, CorksDropAlerts.SavedCount do
		Interface.DeleteSetting("CorksDropAlertsText" .. i)
		Interface.DeleteSetting("CorksDropAlertsOn" .. i)
	end
	Interface.SaveNumber("CorksDropAlertsCount", count)
	CorksDropAlerts.SavedCount = count
end

-- Adds a message, or turns an existing one back on. Returns false when the list is full.
function CorksDropAlerts.AddEntry(text)
	local lower = string.lower(WStringToString(text))
	for _, entry in ipairs(CorksDropAlerts.Entries) do
		if entry.lower == lower then
			entry.on = true
			return true
		end
	end
	if table.getn(CorksDropAlerts.Entries) >= CorksDropAlerts.MAX_ROWS then
		WindowUtils.ChatPrint(L"Event Drops: the list is full. Uncheck some messages and press Remove Unchecked.", SystemData.ChatLogFilters.SYSTEM)
		return false
	end
	table.insert(CorksDropAlerts.Entries, { text = text, lower = lower, on = true, count = 0 })
	return true
end

----------------------------------------------------------------
-- Matching drops
----------------------------------------------------------------

-- Called for every journal line from Interface.NewChatText.
-- Only game messages count, so a player saying the phrase won't show the graphic.
-- Some game messages arrive on other channels than SYSTEM, but they all carry a
-- TextID; text players type never does.
function CorksDropAlerts.OnChatText()
	if not SystemData.Text then
		return
	end
	local isGameMessage = SystemData.TextChannelID == SystemData.ChatLogFilters.SYSTEM
		or (SystemData.TextID ~= nil and SystemData.TextID ~= 0)
	if not isGameMessage then
		return
	end

	CorksDropAlerts.Load()
	local text = string.lower(WStringToString(SystemData.Text))
	for _, entry in ipairs(CorksDropAlerts.Entries) do
		if entry.on and string.find(text, entry.lower, 1, true) then
			entry.count = entry.count + 1
			CorksDropAlerts.Total = CorksDropAlerts.Total + 1
			if not CorksDropAlerts.DEFAULT_UI_ARTIFACT_IDS[SystemData.TextID] then
				CenterScreenText.SendCenterScreenTexture("artifact")
			end
			CorksDropAlerts.Refresh()
			return
		end
	end
end

----------------------------------------------------------------
-- Window
----------------------------------------------------------------

function CorksDropAlerts.Initialize()
	SnapUtils.SnappableWindows["CorksDropAlertsWindow"] = true
	WindowUtils.RestoreWindowPosition("CorksDropAlertsWindow", false)
	WindowUtils.LoadScale("CorksDropAlertsWindow")
	WindowUtils.SetWindowTitle("CorksDropAlertsWindow", L"Event Drops")

	LabelSetText("CorksDropAlertsWindowListHeader", L"Show the artifact graphic for messages containing:")
	LabelSetText("CorksDropAlertsWindowTextLabel", L"Add a drop message (press Enter):")
	ButtonSetText("CorksDropAlertsWindowResetButton", L"Reset Count")
	ButtonSetText("CorksDropAlertsWindowRemoveButton", L"Remove Unchecked")

	for i = 1, CorksDropAlerts.MAX_ROWS do
		ButtonSetCheckButtonFlag(CorksDropAlerts.RowName(i) .. "Button", true)
	end

	CorksDropAlerts.Load()
	CorksDropAlerts.Initialized = true
	CorksDropAlerts.Refresh()
end

function CorksDropAlerts.Shutdown()
	CorksDropAlerts.SyncFromButtons()
	WindowUtils.SaveWindowPosition("CorksDropAlertsWindow")
end

function CorksDropAlerts.RowName(index)
	return "CorksDropAlertsWindowRow" .. index
end

-- Redraw the total and the rows.
function CorksDropAlerts.Refresh()
	if not CorksDropAlerts.Initialized or not DoesWindowNameExist("CorksDropAlertsWindow") then
		return
	end

	LabelSetText("CorksDropAlertsWindowTotal", L"Drops this session: " .. towstring(CorksDropAlerts.Total))

	for i = 1, CorksDropAlerts.MAX_ROWS do
		local rowName = CorksDropAlerts.RowName(i)
		local entry = CorksDropAlerts.Entries[i]
		WindowSetShowing(rowName, entry ~= nil)
		if entry then
			ButtonSetPressedFlag(rowName .. "Button", entry.on)
			-- A label takes its color when its text is set, so set the color first.
			if entry.on then
				LabelSetTextColor(rowName .. "Label", 255, 255, 255)
			else
				LabelSetTextColor(rowName .. "Label", 150, 150, 150)
			end
			LabelSetText(rowName .. "Label", L"[" .. towstring(entry.count) .. L"] " .. entry.text)
		end
	end
end

-- Copy the check boxes into the entries and save if anything changed.
function CorksDropAlerts.SyncFromButtons()
	if not CorksDropAlerts.Initialized then
		return
	end
	local changed = false
	for i, entry in ipairs(CorksDropAlerts.Entries) do
		local button = CorksDropAlerts.RowName(i) .. "Button"
		if DoesWindowNameExist(button) then
			local on = ButtonGetPressedFlag(button)
			if on ~= entry.on then
				entry.on = on
				changed = true
			end
		end
	end
	if changed then
		CorksDropAlerts.Save()
		CorksDropAlerts.Refresh()
	end
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CorksDropAlerts.OnUpdate()
	if CorksDropAlerts.Dirty then
		CorksDropAlerts.Dirty = false
		CorksDropAlerts.SyncFromButtons()
	end
end

function CorksDropAlerts.OnRowButton()
	CorksDropAlerts.Dirty = true
end

-- Clicking the message text toggles its check box too.
function CorksDropAlerts.OnRowLabel()
	local button = string.gsub(SystemData.ActiveWindow.name, "Label$", "Button")
	ButtonSetPressedFlag(button, not ButtonGetPressedFlag(button))
	CorksDropAlerts.Dirty = true
end

function CorksDropAlerts.OnReset()
	CorksDropAlerts.Total = 0
	for _, entry in ipairs(CorksDropAlerts.Entries) do
		entry.count = 0
	end
	CorksDropAlerts.Refresh()
end

function CorksDropAlerts.OnRemoveUnchecked()
	CorksDropAlerts.SyncFromButtons()
	local kept = {}
	for _, entry in ipairs(CorksDropAlerts.Entries) do
		if entry.on then
			table.insert(kept, entry)
		end
	end
	CorksDropAlerts.Entries = kept
	CorksDropAlerts.Save()
	CorksDropAlerts.Refresh()
end

function CorksDropAlerts.OnTextClick()
	WindowAssignFocus("CorksDropAlertsWindowTextBox", true)
end

function CorksDropAlerts.OnTextEnter()
	local text = WStringToString(TextEditBoxGetText("CorksDropAlertsWindowTextBox"))
	text = string.gsub(text, "^%s*(.-)%s*$", "%1")
	if text ~= "" then
		CorksDropAlerts.SyncFromButtons()
		if CorksDropAlerts.AddEntry(StringToWString(text)) then
			CorksDropAlerts.Save()
			CorksDropAlerts.Refresh()
		end
	end
	TextEditBoxSetText("CorksDropAlertsWindowTextBox", L"")
	WindowAssignFocus("CorksDropAlertsWindowTextBox", false)
end

function CorksDropAlerts.OnTextEscape()
	WindowAssignFocus("CorksDropAlertsWindowTextBox", false)
end

-- The window only opens when the user turns it on with the Event Drops action.
-- Whether it's open is saved, so it opens again at login if it was open when the
-- client closed (Interface.lua reads the setting when it creates the window).
-- Drops are matched and counted while it's closed.

-- Open or close the window, creating it again if it was destroyed.
function CorksDropAlerts.Toggle()
	local open = DoesWindowNameExist("CorksDropAlertsWindow") and WindowGetShowing("CorksDropAlertsWindow")
	CorksDropAlerts.SetOpen(not open)
end

-- Right-click closes the window until the action opens it again.
function CorksDropAlerts.OnClose()
	CorksDropAlerts.SetOpen(false)
end

function CorksDropAlerts.SetOpen(open)
	Interface.SaveBoolean("CorksDropAlertsWindowOpen", open)
	if not DoesWindowNameExist("CorksDropAlertsWindow") then
		if open then
			CreateWindow("CorksDropAlertsWindow", true)
		end
		return
	end
	if not open then
		CorksDropAlerts.SyncFromButtons()
	end
	WindowSetShowing("CorksDropAlertsWindow", open)
	if open then
		CorksDropAlerts.Refresh()
	end
end
