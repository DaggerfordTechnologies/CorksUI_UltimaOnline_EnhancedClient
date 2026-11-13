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

-- Classic UO gump background (base gump art ID), or nil for the standard EC look.
-- The classic controls below are only used along with it.
CorksDropAlerts.ClassicBackground = 83
-- Classic check box art { unchecked, checked }, or nil for the EC check boxes
CorksDropAlerts.ClassicCheck = { 210, 211 }
-- Classic background for the entry box (base gump art ID), or nil for the EC box
CorksDropAlerts.ClassicTextBox = 3000
-- Classic button art { normal, mouse over, pressed }, or nil for the EC buttons
CorksDropAlerts.ClassicResetButton = { 4005, 4006, 4007 }
CorksDropAlerts.ClassicRemoveButton = { 4017, 4018, 4019 }
-- How far below the gump's top edge the title sits (clears the classic border)
CorksDropAlerts.TitleOffsetY = 8
-- Gump art loaded for the classic look, released on shutdown
CorksDropAlerts.GumpArt = {}

-- Layout; must match CorksDropAlertsWindow in the XML. The window is sized to fit
-- the rows in use: ROWS_TOP + rows * ROW_HEIGHT + BOTTOM_HEIGHT (580 with 10 rows).
CorksDropAlerts.WIDTH = 420
CorksDropAlerts.ROWS_TOP = 138
CorksDropAlerts.ROW_HEIGHT = 24
CorksDropAlerts.BOTTOM_HEIGHT = 202
CorksDropAlerts.TEXTBOX_WIDTH = 380
CorksDropAlerts.TEXTBOX_HEIGHT = 30
-- How dark the stripe behind every other row is
CorksDropAlerts.STRIPE_ALPHA = 0.3
-- How long a row lights up after its message arrives (seconds)
CorksDropAlerts.FLASH_SECONDS = 2.5

-- Text colors
CorksDropAlerts.COLOR_ON = { 255, 255, 255 }
CorksDropAlerts.COLOR_OFF = { 130, 130, 130 }
CorksDropAlerts.COLOR_FLASH = { 255, 215, 90 }
CorksDropAlerts.COLOR_COUNT = { 255, 200, 50 }

-- { text = wstring, lower = string, on = boolean, count = number }
CorksDropAlerts.Entries = {}
CorksDropAlerts.Total = 0
CorksDropAlerts.SavedCount = 0
CorksDropAlerts.Loaded = false
-- Interface.TimeSinceLogin when the last drop arrived, nil before the first one
CorksDropAlerts.LastDropTime = nil
-- Row lit up by the latest drop and how long it stays lit
CorksDropAlerts.FlashRow = nil
CorksDropAlerts.FlashLeft = 0
-- Time since the "Last drop" line was redrawn
CorksDropAlerts.LastDropTick = 0
CorksDropAlerts.CurrentHeight = 0

-- Backpack items counted by name. ItemText is what the user typed (saved);
-- ItemPatterns is it split at commas, lower-case. Rescanned every
-- ITEM_SCAN_SECONDS while the window is open.
CorksDropAlerts.ITEM_SCAN_SECONDS = 3
-- Bags inside bags are followed this deep
CorksDropAlerts.ITEM_SCAN_DEPTH = 6
CorksDropAlerts.ItemText = L""
CorksDropAlerts.ItemPatterns = {}
CorksDropAlerts.ItemCount = nil
CorksDropAlerts.ItemScanTick = 0
-- objectId -> lower-case name, so names are only looked up once
CorksDropAlerts.ItemNames = {}

----------------------------------------------------------------
-- Saved messages
----------------------------------------------------------------

function CorksDropAlerts.Load()
	if CorksDropAlerts.Loaded then
		return
	end
	CorksDropAlerts.Loaded = true

	CorksDropAlerts.SetItemText(Interface.LoadWString("CorksDropAlertsItemName", L""))

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
	for index, entry in ipairs(CorksDropAlerts.Entries) do
		if entry.on and string.find(text, entry.lower, 1, true) then
			entry.count = entry.count + 1
			CorksDropAlerts.Total = CorksDropAlerts.Total + 1
			CorksDropAlerts.LastDropTime = Interface.TimeSinceLogin
			if not CorksDropAlerts.DEFAULT_UI_ARTIFACT_IDS[SystemData.TextID] then
				CenterScreenText.SendCenterScreenTexture("artifact")
			end
			CorksDropAlerts.StartFlash(index)
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
	LabelSetText("CorksDropAlertsWindowItemLabel", L"Count backpack items named (press Enter):")
	ButtonSetText("CorksDropAlertsWindowResetButton", L"Reset Count")
	ButtonSetText("CorksDropAlertsWindowRemoveButton", L"Remove Unchecked")

	for i = 1, CorksDropAlerts.MAX_ROWS do
		local rowName = CorksDropAlerts.RowName(i)
		ButtonSetCheckButtonFlag(rowName .. "Button", true)
		WindowSetAlpha(rowName .. "Stripe", CorksDropAlerts.STRIPE_ALPHA)
		WindowSetShowing(rowName .. "Check", false)
	end
	WindowSetShowing("CorksDropAlertsWindowResetClassic", false)
	WindowSetShowing("CorksDropAlertsWindowRemoveClassic", false)

	-- The artifact banner: the same art the default UI shows over your head
	DynamicImageSetTexture("CorksDropAlertsWindowBanner", "CST_Artifact", 0, 0)
	DynamicImageSetTextureDimensions("CorksDropAlertsWindowBanner", 220, 80)

	CorksDropAlerts.Load()
	CorksDropAlerts.Initialized = true
	TextEditBoxSetText("CorksDropAlertsWindowItemTextBox", CorksDropAlerts.ItemText)
	CorksDropAlerts.ScanBackpack()

	-- Protected, so a problem with the art can never break the window
	CorksDropAlerts.CheckArt = nil
	CorksDropAlerts.CheckImages = {}
	CorksDropAlerts.ButtonArt = {}
	local ok, err = pcall(CorksDropAlerts.ApplyClassicControls)
	if not ok then
		CorksDropAlerts.ReportArtError(err)
	end

	-- Sizes the window to its rows, which also draws the classic background
	CorksDropAlerts.CurrentHeight = 0
	CorksDropAlerts.Refresh()
end

function CorksDropAlerts.Shutdown()
	CorksDropAlerts.SyncFromButtons()
	WindowUtils.SaveWindowPosition("CorksDropAlertsWindow")
	CorksGumpArt.ReleaseAll(CorksDropAlerts.GumpArt)
end

function CorksDropAlerts.RowName(index)
	return "CorksDropAlertsWindowRow" .. index
end

function CorksDropAlerts.ReportArtError(err)
	pcall(WindowUtils.ChatPrint, StringToWString("Event Drops art: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
end

function CorksDropAlerts.HeightFor(rows)
	return CorksDropAlerts.ROWS_TOP + rows * CorksDropAlerts.ROW_HEIGHT + CorksDropAlerts.BOTTOM_HEIGHT
end

----------------------------------------------------------------
-- Classic look
----------------------------------------------------------------

-- Shows one piece of art in an image made by CorksGumpArt.Image
function CorksDropAlerts.SetArt(image, piece)
	DynamicImageSetTexture(image, piece.tex, 0, 0)
	DynamicImageSetTextureDimensions(image, piece.w, piece.h)
	WindowSetDimensions(image, piece.w, piece.h)
end

-- Check boxes, buttons and entry box, drawn once when the window opens. Each one
-- keeps its EC version when its art can't be loaded.
function CorksDropAlerts.ApplyClassicControls()
	if not CorksDropAlerts.ClassicBackground then
		return
	end
	CorksDropAlerts.ApplyClassicChecks()
	CorksDropAlerts.ApplyClassicButton("CorksDropAlertsWindowResetClassic", "CorksDropAlertsWindowResetButton",
		CorksDropAlerts.ClassicResetButton, L"Reset Count", CorksDropAlerts.OnReset)
	CorksDropAlerts.ApplyClassicButton("CorksDropAlertsWindowRemoveClassic", "CorksDropAlertsWindowRemoveButton",
		CorksDropAlerts.ClassicRemoveButton, L"Remove Unchecked", CorksDropAlerts.OnRemoveUnchecked)
	CorksDropAlerts.ApplyClassicTextBox("CorksDropAlertsWindowTextBox")
	CorksDropAlerts.ApplyClassicTextBox("CorksDropAlertsWindowItemTextBox")
end

function CorksDropAlerts.ApplyClassicChecks()
	local ids = CorksDropAlerts.ClassicCheck
	if not ids then
		return
	end
	local off = CorksGumpArt.Request(ids[1], CorksDropAlerts.GumpArt)
	local on = CorksGumpArt.Request(ids[2], CorksDropAlerts.GumpArt)
	if not off or not on then
		return
	end
	CorksDropAlerts.CheckArt = { [false] = off, [true] = on }
	for i = 1, CorksDropAlerts.MAX_ROWS do
		local holder = CorksDropAlerts.RowName(i) .. "Check"
		CorksGumpArt.Clear(holder)
		WindowSetDimensions(holder, off.w, off.h)
		CorksDropAlerts.CheckImages[i] = CorksGumpArt.Image(holder, off.tex, 0, 0, off.w, off.h)
	end
end

-- holder is the classic button window, ecButton the EC button it replaces;
-- ids are { normal, mouse over, pressed } (the last two fall back to normal).
function CorksDropAlerts.ApplyClassicButton(holder, ecButton, ids, text, action)
	if not ids then
		return
	end
	local owner = CorksDropAlerts.GumpArt
	local normal = CorksGumpArt.Request(ids[1], owner)
	if not normal then
		return
	end
	local over = CorksGumpArt.Request(ids[2], owner) or normal
	local pressed = CorksGumpArt.Request(ids[3], owner) or normal

	local art = holder .. "Art"
	CorksGumpArt.Clear(art)
	local _, artHeight = WindowGetDimensions(art)
	local y = math.max(0, math.floor((artHeight - normal.h) / 2))
	local image = CorksGumpArt.Image(art, normal.tex, 0, y, normal.w, normal.h)
	LabelSetText(holder .. "Text", text)

	CorksDropAlerts.ButtonArt[holder] = {
		image = image, normal = normal, over = over, pressed = pressed, action = action,
	}
	WindowSetShowing(ecButton, false)
	WindowSetShowing(holder, true)
end

-- Classic white entry box with black text, like Corks' Targeting. The art goes in
-- the box's <box>BG holder.
function CorksDropAlerts.ApplyClassicTextBox(box)
	if not CorksDropAlerts.ClassicTextBox then
		return
	end
	local holder = box .. "BG"
	CorksGumpArt.Clear(holder)
	if CorksGumpArt.Background(holder, CorksDropAlerts.ClassicTextBox,
		CorksDropAlerts.TEXTBOX_WIDTH, CorksDropAlerts.TEXTBOX_HEIGHT, CorksDropAlerts.GumpArt) then
		WindowSetShowing(holder .. "BG", false)
		WindowSetShowing(holder .. "Frame", false)
		TextEditBoxSetTextColor(box, 0, 0, 0)
	end
end

-- Draws the classic background at the window's height, then lines up the art
-- and the title (CorksGumpArt.FinishClassic re-scales the whole window, which
-- also fixes the size of the classic controls made from Lua). Protected, so a
-- problem with the art can never stop the list updating.
function CorksDropAlerts.ApplyClassicBackground(height)
	if not CorksDropAlerts.ClassicBackground then
		return
	end
	local ok, err = pcall(function()
		CorksGumpArt.ApplyClassic("CorksDropAlertsWindow", CorksDropAlerts.ClassicBackground,
			CorksDropAlerts.WIDTH, height, CorksDropAlerts.GumpArt)
		CorksGumpArt.FinishClassic("CorksDropAlertsWindow", CorksDropAlerts.TitleOffsetY)
	end)
	if not ok then
		CorksDropAlerts.ReportArtError(err)
	end
end

function CorksDropAlerts.OnClassicButtonDown()
	local state = CorksDropAlerts.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		state.down = true
		CorksDropAlerts.SetArt(state.image, state.pressed)
	end
end

function CorksDropAlerts.OnClassicButtonUp()
	local state = CorksDropAlerts.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		CorksDropAlerts.SetArt(state.image, state.over)
		if state.down then
			state.down = false
			state.action()
		end
	end
end

function CorksDropAlerts.OnClassicButtonOver()
	local state = CorksDropAlerts.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		CorksDropAlerts.SetArt(state.image, state.over)
	end
end

function CorksDropAlerts.OnClassicButtonOverEnd()
	local state = CorksDropAlerts.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		state.down = false
		CorksDropAlerts.SetArt(state.image, state.normal)
	end
end

----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------

-- A label takes its color when its text is set, so this sets the color first.
function CorksDropAlerts.SetLabel(label, text, color)
	LabelSetTextColor(label, color[1], color[2], color[3])
	LabelSetText(label, text)
end

function CorksDropAlerts.FormatAgo(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s ago"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	end
	return string.format("%dh %02dm ago", math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
end

function CorksDropAlerts.UpdateLastDrop()
	local text = "No drops yet"
	if CorksDropAlerts.LastDropTime then
		text = "Last drop: " .. CorksDropAlerts.FormatAgo(Interface.TimeSinceLogin - CorksDropAlerts.LastDropTime)
	end
	LabelSetText("CorksDropAlertsWindowLastDrop", StringToWString(text))
end

-- Redraw the header and the rows, and fit the window to the rows in use.
function CorksDropAlerts.Refresh()
	if not CorksDropAlerts.Initialized or not DoesWindowNameExist("CorksDropAlertsWindow") then
		return
	end
	local D = CorksDropAlerts

	LabelSetText("CorksDropAlertsWindowTotal", towstring(D.Total))
	if D.Total == 1 then
		LabelSetText("CorksDropAlertsWindowTotalCaption", L"drop this session")
	else
		LabelSetText("CorksDropAlertsWindowTotalCaption", L"drops this session")
	end
	D.UpdateLastDrop()

	local classicChecks = D.CheckArt ~= nil
	for i = 1, D.MAX_ROWS do
		local rowName = D.RowName(i)
		local entry = D.Entries[i]
		-- With no messages, row 1 says how to add one
		local placeholder = (i == 1 and entry == nil)
		WindowSetShowing(rowName, entry ~= nil or placeholder)
		WindowSetShowing(rowName .. "Stripe", i % 2 == 1)
		if entry then
			ButtonSetPressedFlag(rowName .. "Button", entry.on)
			WindowSetShowing(rowName .. "Button", not classicChecks)
			WindowSetShowing(rowName .. "Check", classicChecks)
			if classicChecks then
				D.SetArt(D.CheckImages[i], D.CheckArt[entry.on == true])
			end
			local color, countColor = D.COLOR_ON, D.COLOR_COUNT
			if D.FlashRow == i then
				color = D.COLOR_FLASH
			elseif not entry.on then
				color, countColor = D.COLOR_OFF, D.COLOR_OFF
			end
			D.SetLabel(rowName .. "Label", entry.text, color)
			D.SetLabel(rowName .. "Count", towstring(entry.count), countColor)
		elseif placeholder then
			WindowSetShowing(rowName .. "Button", false)
			WindowSetShowing(rowName .. "Check", false)
			D.SetLabel(rowName .. "Label", L"No messages yet. Add one below.", D.COLOR_OFF)
			LabelSetText(rowName .. "Count", L"")
		end
	end

	local height = D.HeightFor(math.max(table.getn(D.Entries), 1))
	if height ~= D.CurrentHeight then
		D.CurrentHeight = height
		WindowSetDimensions("CorksDropAlertsWindow", D.WIDTH, height)
		D.ApplyClassicBackground(height)
	end
end

----------------------------------------------------------------
-- Drop flash
----------------------------------------------------------------

-- Windows that pulse while a row is lit
function CorksDropAlerts.FlashWindows(row)
	local rowName = CorksDropAlerts.RowName(row)
	return { rowName .. "Label", rowName .. "Count", "CorksDropAlertsWindowTotal", "CorksDropAlertsWindowBanner" }
end

-- Lights up the row whose message just arrived and pulses it with the total.
-- Only while the window is showing, as it doesn't update while it's closed.
function CorksDropAlerts.StartFlash(row)
	if CorksDropAlerts.FlashRow then
		CorksDropAlerts.StopFlash()
	end
	if not DoesWindowNameExist("CorksDropAlertsWindow") or not WindowGetShowing("CorksDropAlertsWindow") then
		return
	end
	CorksDropAlerts.FlashRow = row
	CorksDropAlerts.FlashLeft = CorksDropAlerts.FLASH_SECONDS
	for _, name in ipairs(CorksDropAlerts.FlashWindows(row)) do
		WindowStartAlphaAnimation(name, Window.AnimationType.LOOP, 0.35, 1, 0.4, false, 0, 0)
	end
end

function CorksDropAlerts.StopFlash()
	local row = CorksDropAlerts.FlashRow
	CorksDropAlerts.FlashRow = nil
	if not row or not DoesWindowNameExist("CorksDropAlertsWindow") then
		return
	end
	for _, name in ipairs(CorksDropAlerts.FlashWindows(row)) do
		WindowStopAlphaAnimation(name)
		WindowSetAlpha(name, 1)
	end
	CorksDropAlerts.Refresh()
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

function CorksDropAlerts.OnUpdate(timePassed)
	timePassed = timePassed or 0
	if CorksDropAlerts.Dirty then
		CorksDropAlerts.Dirty = false
		CorksDropAlerts.SyncFromButtons()
	end

	if CorksDropAlerts.FlashRow then
		CorksDropAlerts.FlashLeft = CorksDropAlerts.FlashLeft - timePassed
		if CorksDropAlerts.FlashLeft <= 0 then
			CorksDropAlerts.StopFlash()
		end
	end

	-- Keep "Last drop: 4m ago" current
	CorksDropAlerts.LastDropTick = CorksDropAlerts.LastDropTick + timePassed
	if CorksDropAlerts.LastDropTick >= 1 then
		CorksDropAlerts.LastDropTick = 0
		if CorksDropAlerts.Initialized then
			CorksDropAlerts.UpdateLastDrop()
		end
	end

	CorksDropAlerts.ItemScanTick = CorksDropAlerts.ItemScanTick + timePassed
	if CorksDropAlerts.ItemScanTick >= CorksDropAlerts.ITEM_SCAN_SECONDS then
		CorksDropAlerts.ItemScanTick = 0
		if WindowGetShowing("CorksDropAlertsWindow") then
			CorksDropAlerts.ScanBackpack()
		end
	end
end

function CorksDropAlerts.OnRowButton()
	CorksDropAlerts.Dirty = true
end

-- Flips a row's EC check button, which keeps the checked state even while the
-- classic check box art is shown in its place.
function CorksDropAlerts.ToggleRowButton(button)
	ButtonSetPressedFlag(button, not ButtonGetPressedFlag(button))
	CorksDropAlerts.Dirty = true
end

-- Clicking the message text toggles its check box too.
function CorksDropAlerts.OnRowLabel()
	CorksDropAlerts.ToggleRowButton((string.gsub(SystemData.ActiveWindow.name, "Label$", "Button")))
end

-- The classic check box
function CorksDropAlerts.OnRowCheck()
	CorksDropAlerts.ToggleRowButton((string.gsub(SystemData.ActiveWindow.name, "Check$", "Button")))
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

function CorksDropAlerts.OnItemTextClick()
	WindowAssignFocus("CorksDropAlertsWindowItemTextBox", true)
end

-- The item name text stays in its box; an empty box stops the counting.
function CorksDropAlerts.OnItemTextEnter()
	CorksDropAlerts.SetItemText(TextEditBoxGetText("CorksDropAlertsWindowItemTextBox"))
	Interface.SaveWString("CorksDropAlertsItemName", CorksDropAlerts.ItemText)
	TextEditBoxSetText("CorksDropAlertsWindowItemTextBox", CorksDropAlerts.ItemText)
	WindowAssignFocus("CorksDropAlertsWindowItemTextBox", false)
	CorksDropAlerts.ItemScanTick = 0
	CorksDropAlerts.ScanBackpack()
end

function CorksDropAlerts.OnItemTextEscape()
	TextEditBoxSetText("CorksDropAlertsWindowItemTextBox", CorksDropAlerts.ItemText)
	WindowAssignFocus("CorksDropAlertsWindowItemTextBox", false)
end

----------------------------------------------------------------
-- Backpack items
----------------------------------------------------------------

-- Takes the typed text (wstring); several names can be given, split by commas.
function CorksDropAlerts.SetItemText(text)
	local patterns = {}
	local parts = {}
	for part in string.gmatch(WStringToString(text or L""), "[^,]+") do
		part = string.gsub(part, "^%s*(.-)%s*$", "%1")
		if part ~= "" then
			table.insert(patterns, string.lower(part))
			table.insert(parts, part)
		end
	end
	CorksDropAlerts.ItemPatterns = patterns
	CorksDropAlerts.ItemText = StringToWString(table.concat(parts, ", "))
end

function CorksDropAlerts.BackpackId()
	if ContainerWindow and ContainerWindow.PlayerBackpack and ContainerWindow.PlayerBackpack ~= 0 then
		return ContainerWindow.PlayerBackpack
	end
	local slot = WindowData.PlayerEquipmentSlot and WindowData.PlayerEquipmentSlot[EquipmentData.EQPOS_BACKPACK]
	if slot and slot.objectId and slot.objectId ~= 0 then
		return slot.objectId
	end
	return nil
end

-- The item's name in lower case, or nil while the client hasn't got it yet
-- (it's looked up again on the next scan).
function CorksDropAlerts.ItemName(objectId)
	local name = CorksDropAlerts.ItemNames[objectId]
	if name then
		return name
	end
	local wname = ItemProperties.GetObjectProperties(objectId, 1, "CorksDropAlerts")
	if not wname or wname == L"" then
		return nil
	end
	name = string.lower(WStringToString(wname))
	CorksDropAlerts.ItemNames[objectId] = name
	return name
end

-- How many items a name stands for: "5 Unhallowed Shards" is a stack of 5
function CorksDropAlerts.ItemAmount(name)
	return tonumber(string.match(name, "^(%d+) ")) or 1
end

function CorksDropAlerts.NameMatches(name)
	for _, pattern in ipairs(CorksDropAlerts.ItemPatterns) do
		if string.find(name, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Adds up the matching items in a container and the bags in it. Only containers
-- the client has contents for are seen (in practice, ones opened this session).
function CorksDropAlerts.CountIn(containerId, depth, seen)
	local registered = false
	if not WindowData.ContainerWindow[containerId] then
		RegisterWindowData(WindowData.ContainerWindow.Type, containerId)
		registered = true
	end
	local total = 0
	local data = WindowData.ContainerWindow[containerId]
	if data and data.ContainedItems then
		for i = 1, (data.numItems or 0) do
			local item = data.ContainedItems[i]
			if item and item.objectId then
				seen[item.objectId] = true
				local name = CorksDropAlerts.ItemName(item.objectId)
				if name and CorksDropAlerts.NameMatches(name) then
					total = total + CorksDropAlerts.ItemAmount(name)
				end
				if depth < CorksDropAlerts.ITEM_SCAN_DEPTH then
					total = total + CorksDropAlerts.CountIn(item.objectId, depth + 1, seen)
				end
			end
		end
	end
	if registered and not (ContainerWindow and ContainerWindow.OpenContainers and ContainerWindow.OpenContainers[containerId]) then
		UnregisterWindowData(WindowData.ContainerWindow.Type, containerId)
	end
	return total
end

-- Recounts the matching backpack items and shows the total. Protected, so a
-- problem reading the backpack can never break the window.
function CorksDropAlerts.ScanBackpack()
	if not CorksDropAlerts.Initialized then
		return
	end
	local count = nil
	if #CorksDropAlerts.ItemPatterns > 0 then
		local ok, result = pcall(function()
			local backpack = CorksDropAlerts.BackpackId()
			if not backpack then
				return nil
			end
			local seen = {}
			local total = CorksDropAlerts.CountIn(backpack, 1, seen)
			-- Forget the names of items that have left the backpack
			for objectId in pairs(CorksDropAlerts.ItemNames) do
				if not seen[objectId] then
					CorksDropAlerts.ItemNames[objectId] = nil
				end
			end
			return total
		end)
		if ok then
			count = result
		end
	end
	CorksDropAlerts.ItemCount = count
	CorksDropAlerts.UpdateItemCount()
end

function CorksDropAlerts.UpdateItemCount()
	local text = L""
	if #CorksDropAlerts.ItemPatterns > 0 then
		if CorksDropAlerts.ItemCount then
			text = towstring(CorksDropAlerts.ItemCount) .. L" in backpack"
		else
			text = L"backpack not found"
		end
	end
	LabelSetText("CorksDropAlertsWindowItemCount", text)
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
