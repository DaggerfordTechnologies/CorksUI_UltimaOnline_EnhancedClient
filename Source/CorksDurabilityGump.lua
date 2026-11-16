----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksDurabilityGump = {}

CorksDurabilityGump.DURABILITY_TID = 1060639
CorksDurabilityGump.REFRESH_INTERVAL = 10
CorksDurabilityGump.RefreshTimer = 0
CorksDurabilityGump.RowCount = 0
CorksDurabilityGump.CurrentHeight = 0
CorksDurabilityGump.MAX_ROWS = 19  -- Max equippable slots

-- The window background image can't be drawn shorter than 90px and starts 28px
-- down, so a shorter window lets it spill past the frame at the bottom.
CorksDurabilityGump.MIN_HEIGHT = 120

-- Width and starting height, as in the XML
CorksDurabilityGump.WIDTH = 400
CorksDurabilityGump.XML_HEIGHT = 400

-- Classic UO gump background (base gump art ID), or nil for the standard EC look.
-- Redrawn whenever the window changes height.
CorksDurabilityGump.ClassicBackground = 2620
-- How far below the gump's top edge the title sits (clears the classic border)
CorksDurabilityGump.TitleOffsetY = 8
-- Gump art loaded for the classic background, released on shutdown
CorksDurabilityGump.GumpArt = {}

-- Settings, changed in the Gear Watcher Setup window (CorksGearWatcherSetup) and
-- read with CorksDurabilityGump.Get / changed with CorksDurabilityGump.Set.
-- save: the saved setting's name; numbers are kept within min..max.
CorksDurabilityGump.SETTINGS = {
	-- Repair alert: shown once when an equipped item drops to AlertPercent or lower,
	-- and again only after that item has been repaired above it and worn down again
	PopupOn      = { save = "CorksGearWatcherPopupOn",      default = true },
	ChatOn       = { save = "CorksGearWatcherChatOn",       default = true },
	AlertPercent = { save = "CorksGearWatcherAlertPercent", default = 25,  min = 1, max = 99 },
	-- List: items above this are left out (100 shows everything)
	HideAbove    = { save = "CorksGearWatcherHideAbove",    default = 100, min = 1, max = 100 },
	-- How durability is shown (FORMAT_POINTS, FORMAT_PERCENT or FORMAT_BOTH)
	Format       = { save = "CorksGearWatcherFormat",       default = 1,   min = 1, max = 3 },
	-- Colour levels: green above Green, yellow above Yellow, orange above Orange,
	-- and red at or below Orange. Kept in order (each at least 1 below the one
	-- before), see COLOR_ORDER.
	Green        = { save = "CorksGearWatcherGreen",        default = 75,  min = 1, max = 99 },
	Yellow       = { save = "CorksGearWatcherYellow",       default = 50,  min = 1, max = 99 },
	Orange       = { save = "CorksGearWatcherOrange",       default = 25,  min = 1, max = 99 },
}
CorksDurabilityGump.FORMAT_POINTS = 1   -- "11 / 50"
CorksDurabilityGump.FORMAT_PERCENT = 2  -- "22%"
CorksDurabilityGump.FORMAT_BOTH = 3     -- "22% (11 / 50)"
-- Item name and durability column widths in the list ("22% (11 / 50)" needs a
-- wider durability column, so the name gives some up); the row is 360 wide
CorksDurabilityGump.COLUMN_WIDTHS = {
	[1] = { name = 240, durability = 100 },
	[2] = { name = 240, durability = 100 },
	[3] = { name = 205, durability = 135 },
}
-- Format the columns were last sized for
CorksDurabilityGump.ColumnsFormat = nil
-- Colour levels, highest first; each colour is shown above its level, and red at
-- or below the last
CorksDurabilityGump.COLOR_ORDER = { "Green", "Yellow", "Orange" }
CorksDurabilityGump.COLORS = {
	Green      = { 0, 255, 0 },
	Yellow     = { 255, 255, 0 },
	Orange     = { 255, 165, 0 },
	Red        = { 255, 0, 0 },
}
-- Current values, filled from the saved settings on first use
CorksDurabilityGump.Values = nil

-- The repair alert is checked from Interface's update loop, so it works while the
-- window is closed
CorksDurabilityGump.ALERT_CHECK_SECONDS = 10
CorksDurabilityGump.AlertTick = 0
-- Items already warned about, by object id
CorksDurabilityGump.Alerted = {}

CorksDurabilityGump.SlotNames = {
	[1]  = "Head",
	[2]  = "Neck",
	[3]  = "Arms",
	[4]  = "Right Hand",
	[5]  = "Ring",
	[6]  = "Legs",
	[7]  = "Ears",
	[8]  = "Chest",
	[9]  = "Bracelet",
	[10] = "Left Hand",
	[11] = "Gloves",
	[12] = "Talisman",
	[13] = "Feet",
	[14] = "Shirt",
	[15] = "Waist",
	[16] = "Robe",
	[17] = "Gorget",
	[18] = "Cape",
	[19] = "Pants",
}

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksDurabilityGump.Initialize()
	WindowSetScale("CorksDurabilityGump", SystemData.Settings.Interface.customUiScale * 0.80)
	WindowUtils.LoadScale("CorksDurabilityGump")
	WindowUtils.SetWindowTitle("CorksDurabilityGump", L"Corks Gear Watcher")

	LabelSetText("CorksDurabilityGumpHeaderItem", L"Item")
	LabelSetText("CorksDurabilityGumpHeaderDur", L"Durability")
	LabelSetText("CorksDurabilityGumpSetupLabel", L"Setup")

	WindowRegisterEventHandler("Root", WindowData.Paperdoll.Event, "CorksDurabilityGump.OnPaperdollEvent")

	-- Rows are defined statically in XML, so just hide them all until Update populates them.
	CorksDurabilityGump.CreateRows()

	WindowUtils.RestoreWindowPosition("CorksDurabilityGump")

	-- The window starts at its XML size; Update resizes it (and redraws the art)
	CorksDurabilityGump.CurrentHeight = 0
	CorksDurabilityGump.ApplyClassicLook(CorksDurabilityGump.XML_HEIGHT)
	CorksDurabilityGump.Update()
end

function CorksDurabilityGump.Shutdown()
	WindowUtils.SaveWindowPosition("CorksDurabilityGump")
	CorksGumpArt.ReleaseAll(CorksDurabilityGump.GumpArt)
end

-- Draws the classic background at the window's current height (protected, so a
-- problem with the art can never stop the durability list updating).
function CorksDurabilityGump.ApplyClassicLook(height)
	if not CorksDurabilityGump.ClassicBackground then
		return
	end
	local ok, err = pcall(function()
		CorksGumpArt.ApplyClassic("CorksDurabilityGump", CorksDurabilityGump.ClassicBackground,
			CorksDurabilityGump.WIDTH, height, CorksDurabilityGump.GumpArt)
		CorksGumpArt.FinishClassic("CorksDurabilityGump", CorksDurabilityGump.TitleOffsetY)
	end)
	if not ok then
		pcall(WindowUtils.ChatPrint, StringToWString("Gear Watcher background: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
	end
end

function CorksDurabilityGump.CreateRows()
	local scrollChild = "CorksDurabilityGumpListScrollChild"
	for i = 1, CorksDurabilityGump.MAX_ROWS do
		WindowSetShowing(scrollChild .. "Row" .. i, false)
	end
end

function CorksDurabilityGump.OnPaperdollEvent()
	if WindowData.UpdateInstanceId == WindowData.PlayerStatus.PlayerId then
		CorksDurabilityGump.Update()
	end
end

function CorksDurabilityGump.OnUpdate(timePassed)
	CorksDurabilityGump.RefreshTimer = CorksDurabilityGump.RefreshTimer + timePassed
	if CorksDurabilityGump.RefreshTimer >= CorksDurabilityGump.REFRESH_INTERVAL then
		CorksDurabilityGump.RefreshTimer = 0
		CorksDurabilityGump.Update()
	end
end

-- The window only opens when the user turns it on with the Durability Gump action.
-- Whether it's open is saved, so it opens again at login if it was open when the
-- client closed (Interface.lua reads the setting when it creates the window).

-- Right-click closes the window until the action opens it again.
function CorksDurabilityGump.OnClose()
	CorksDurabilityGump.SetOpen(false)
end

-- Open or close the window, creating it again if it was destroyed.
function CorksDurabilityGump.Toggle()
	local open = DoesWindowNameExist("CorksDurabilityGump") and WindowGetShowing("CorksDurabilityGump")
	CorksDurabilityGump.SetOpen(not open)
end

function CorksDurabilityGump.SetOpen(open)
	Interface.SaveBoolean("CorksDurabilityGumpOpen", open)
	if not DoesWindowNameExist("CorksDurabilityGump") then
		if open then
			CreateWindow("CorksDurabilityGump", true)
		end
		return
	end
	WindowSetShowing("CorksDurabilityGump", open)
	if open then
		CorksDurabilityGump.Update()
	end
end

function CorksDurabilityGump.Update()
	local windowName = "CorksDurabilityGump"
	local scrollChild = windowName .. "ListScrollChild"

	if not DoesWindowNameExist(windowName) then
		return
	end

	local playerId = WindowData.PlayerStatus.PlayerId
	if not WindowData.Paperdoll[playerId] then
		return
	end

	-- Hide all rows first
	for i = 1, CorksDurabilityGump.MAX_ROWS do
		WindowSetShowing(scrollChild .. "Row" .. i, false)
	end

	CorksDurabilityGump.SizeColumns()

	local rowCount = 0
	local hiddenCount = 0
	local hideAbove = CorksDurabilityGump.Get("HideAbove")

	for index = 1, WindowData.Paperdoll[playerId].numSlots do
		local slotData = WindowData.Paperdoll[playerId][index]

		if slotData.slotId ~= 0 and CorksDurabilityGump.SlotNames[index] then
			local objectId = slotData.slotId
			local current, max, perc = CorksDurabilityGump.GetDurability(objectId)

			if current and hideAbove < 100 and perc > hideAbove then
				hiddenCount = hiddenCount + 1
			elseif current then
				rowCount = rowCount + 1

				local itemName = ItemProperties.GetObjectProperties(objectId, 1, "CorksDurabilityGump")
				if not itemName then
					itemName = L"Unknown"
				end

				local rowName = scrollChild .. "Row" .. rowCount
				WindowSetShowing(rowName, true)

				-- A label takes its color when its text is set, so set the color first.
				-- Row 1 may have been gray from the "no items" placeholder.
				LabelSetTextColor(rowName .. "ItemName", 255, 255, 255)
				LabelSetText(rowName .. "ItemName", itemName)

				local color = CorksDurabilityGump.DurabilityColor(perc)
				LabelSetTextColor(rowName .. "Durability", color[1], color[2], color[3])
				LabelSetText(rowName .. "Durability", StringToWString(CorksDurabilityGump.DurabilityText(current, max, perc)))
			end
		end
	end

	-- If nothing is listed, show a placeholder in row 1
	if rowCount == 0 then
		rowCount = 1
		local rowName = scrollChild .. "Row1"
		WindowSetShowing(rowName, true)
		LabelSetTextColor(rowName .. "ItemName", 180, 180, 180)
		if hiddenCount > 0 then
			LabelSetText(rowName .. "ItemName", StringToWString("All items are above " .. hideAbove .. "%."))
		else
			LabelSetText(rowName .. "ItemName", L"No items with durability equipped.")
		end
		LabelSetText(rowName .. "Durability", L"")
	end

	CorksDurabilityGump.RowCount = rowCount

	-- Resize the window and scroll child to fit the visible rows exactly.
	-- Rows are statically defined in XML so WindowSetDimensions does not reset
	-- their inherited scale. Only resize when row count actually changes.
	local targetHeight = math.max(rowCount * 22 + 80, CorksDurabilityGump.MIN_HEIGHT)
	if targetHeight ~= CorksDurabilityGump.CurrentHeight then
		CorksDurabilityGump.CurrentHeight = targetHeight
		WindowSetDimensions(windowName, CorksDurabilityGump.WIDTH, targetHeight)
		WindowSetDimensions(scrollChild, 360, rowCount * 22)
		CorksDurabilityGump.ApplyClassicLook(targetHeight)
	end
end

-- An item's durability as current, max and percent left (rounded down),
-- or nil when the item has no durability (or its properties haven't loaded yet).
function CorksDurabilityGump.GetDurability(objectId)
	local dur = ItemProperties.GetObjectPropertiesParamsForTid(objectId, CorksDurabilityGump.DURABILITY_TID, "CorksDurabilityGump")
	if not dur then
		return nil
	end
	local current = tonumber(dur[1])
	local max = tonumber(dur[2])
	if not current or not max then
		return nil
	end
	local perc = 0
	if max > 0 then
		perc = math.floor((current / max) * 100)
	end
	return current, max, perc
end

-- Sizes the item name and durability columns of every row for the chosen format
-- (only when the format has changed since last time)
function CorksDurabilityGump.SizeColumns()
	local D = CorksDurabilityGump
	local format = D.Get("Format")
	if D.ColumnsFormat == format then
		return
	end
	local widths = D.COLUMN_WIDTHS[format] or D.COLUMN_WIDTHS[D.FORMAT_POINTS]
	local scrollChild = "CorksDurabilityGumpListScrollChild"
	for i = 1, D.MAX_ROWS do
		local rowName = scrollChild .. "Row" .. i
		WindowSetDimensions(rowName .. "ItemName", widths.name, 20)
		WindowSetDimensions(rowName .. "Durability", widths.durability, 20)
	end
	D.ColumnsFormat = format
end

-- The colour for a durability percentage, from the colour levels
function CorksDurabilityGump.DurabilityColor(perc)
	local D = CorksDurabilityGump
	for _, key in ipairs(D.COLOR_ORDER) do
		if perc > D.Get(key) then
			return D.COLORS[key]
		end
	end
	return D.COLORS.Red
end

-- The durability as shown in the list, in the chosen format
function CorksDurabilityGump.DurabilityText(current, max, perc)
	local D = CorksDurabilityGump
	local points = tostring(current) .. " / " .. tostring(max)
	local format = D.Get("Format")
	if format == D.FORMAT_PERCENT then
		return perc .. "%"
	elseif format == D.FORMAT_BOTH then
		return perc .. "% (" .. points .. ")"
	end
	return points
end

----------------------------------------------------------------
-- Settings
----------------------------------------------------------------

function CorksDurabilityGump.LoadSettings()
	local D = CorksDurabilityGump
	if D.Values then
		return
	end
	-- Filled before D.Values is set, so Clamp only applies each setting's own
	-- limits here (not the colour level neighbours)
	local values = {}
	for key, setting in pairs(D.SETTINGS) do
		if type(setting.default) == "boolean" then
			values[key] = Interface.LoadBoolean(setting.save, setting.default)
		else
			values[key] = D.Clamp(key, Interface.LoadNumber(setting.save, setting.default))
		end
	end
	-- Saved colour levels out of order (shouldn't happen) go back to the defaults
	for i = 2, table.getn(D.COLOR_ORDER) do
		if values[D.COLOR_ORDER[i]] >= values[D.COLOR_ORDER[i - 1]] then
			for _, key in ipairs(D.COLOR_ORDER) do
				values[key] = D.SETTINGS[key].default
			end
			break
		end
	end
	D.Values = values
end

function CorksDurabilityGump.Get(key)
	CorksDurabilityGump.LoadSettings()
	return CorksDurabilityGump.Values[key]
end

-- Whole number within the setting's min..max (and between its neighbours for a
-- colour level)
function CorksDurabilityGump.Clamp(key, value)
	local D = CorksDurabilityGump
	local setting = D.SETTINGS[key]
	value = math.floor((tonumber(value) or setting.default) + 0.5)
	local low, high = setting.min, setting.max
	if D.Values then
		for i, colorKey in ipairs(D.COLOR_ORDER) do
			if colorKey == key then
				local above = D.COLOR_ORDER[i - 1]
				local below = D.COLOR_ORDER[i + 1]
				if above then
					high = math.min(high, D.Values[above] - 1)
				end
				if below then
					low = math.max(low, D.Values[below] + 1)
				end
			end
		end
	end
	return math.max(low, math.min(high, value))
end

-- Changes and saves a setting, then applies it. Returns the value kept (numbers
-- may be pulled back within their limits).
function CorksDurabilityGump.Set(key, value)
	local D = CorksDurabilityGump
	D.LoadSettings()
	local setting = D.SETTINGS[key]
	if type(setting.default) == "boolean" then
		value = value and true or false
		Interface.SaveBoolean(setting.save, value)
	else
		value = D.Clamp(key, value)
		Interface.SaveNumber(setting.save, value)
	end
	if D.Values[key] == value then
		return value
	end
	D.Values[key] = value

	if key == "PopupOn" or key == "ChatOn" or key == "AlertPercent" then
		-- Check straight away rather than waiting for the next timed check
		D.AlertTick = D.ALERT_CHECK_SECONDS
	else
		D.Update()
	end
	return value
end

----------------------------------------------------------------
-- Repair alert
----------------------------------------------------------------

-- Called every frame from Interface's update loop; looks at the equipped items
-- every ALERT_CHECK_SECONDS and alerts (popup and/or chat) for any newly worn-down item.
function CorksDurabilityGump.CheckAlerts(timePassed)
	local D = CorksDurabilityGump
	D.AlertTick = D.AlertTick + (timePassed or 0)
	if D.AlertTick < D.ALERT_CHECK_SECONDS then
		return
	end
	-- Paused while the Setup window is open, so trying out the settings doesn't set
	-- it off; the tick stays due, so it checks as soon as the window closes
	if CorksGearWatcherSetup and CorksGearWatcherSetup.IsOpen() then
		D.AlertTick = D.ALERT_CHECK_SECONDS
		return
	end
	D.AlertTick = 0

	local popupOn, chatOn = D.Get("PopupOn"), D.Get("ChatOn")
	if not popupOn and not chatOn then
		-- Start fresh, so turning an alert back on warns about anything already worn down
		D.Alerted = {}
		return
	end
	local alertPercent = D.Get("AlertPercent")

	local playerId = WindowData.PlayerStatus and WindowData.PlayerStatus.PlayerId
	if not playerId or playerId == 0 then
		return
	end
	-- The player's paperdoll data stays registered once asked for (as PaperdollWindow does)
	if not WindowData.Paperdoll[playerId] then
		RegisterWindowData(WindowData.Paperdoll.Type, playerId)
	end
	local paperdoll = WindowData.Paperdoll[playerId]
	if not paperdoll then
		return
	end

	local show = false
	for index = 1, paperdoll.numSlots do
		local slotData = paperdoll[index]
		if slotData and slotData.slotId ~= 0 and D.SlotNames[index] then
			local objectId = slotData.slotId
			local current, max, perc = D.GetDurability(objectId)
			if max and max > 0 then
				if perc <= alertPercent then
					if not D.Alerted[objectId] then
						D.Alerted[objectId] = true
						show = true
						if chatOn then
							D.SayRepair(objectId, current, max, perc)
						end
					end
				else
					-- Repaired (or the level was lowered): warn again next time it wears down
					D.Alerted[objectId] = nil
				end
			end
		end
	end

	if show and popupOn then
		D.ShowRepairPopup()
	end
end

-- "Gear Watcher: Platemail Tunic needs repair (22%, 11 / 50)." in chat
function CorksDurabilityGump.SayRepair(objectId, current, max, perc)
	local name = "An item"
	local ok, text = pcall(function()
		return WStringToString(ItemProperties.GetObjectProperties(objectId, 1, "CorksDurabilityGump"))
	end)
	if ok and type(text) == "string" and text ~= "" then
		name = text
	end
	local message = "Gear Watcher: " .. name .. " needs repair (" .. perc .. "%, " .. current .. " / " .. max .. ")."
	pcall(WindowUtils.ChatPrint, StringToWString(message), SystemData.ChatLogFilters.SYSTEM)
end

-- Flashes the CST_Repair graphic (Source/CorksTextures.xml) mid-screen, the same
-- way CenterScreenText shows the stock popups like Low Life
function CorksDurabilityGump.ShowRepairPopup()
	local image = "CenterScreenTextImage"
	DynamicImageSetTexture(image, "CST_Repair", 0, 0)
	DynamicImageSetTextureDimensions(image, 400, 100)
	WindowSetDimensions(image, 400, 100)
	WindowStopAlphaAnimation(image)
	WindowSetAlpha(image, 0)
	WindowStartAlphaAnimation(image, Window.AnimationType.LOOP, 0.5, 1, 1, false, 0, 3)
end

function CorksDurabilityGump.OnSetupButton()
	CorksGearWatcherSetup.Toggle()
end

-- The Setup text is a label over the button, so it's coloured here: pale gold
-- while the mouse is over the button, white otherwise
function CorksDurabilityGump.OnSetupButtonOver()
	LabelSetTextColor("CorksDurabilityGumpSetupLabel", 255, 220, 120)
	LabelSetText("CorksDurabilityGumpSetupLabel", L"Setup")
end

function CorksDurabilityGump.OnSetupButtonOverEnd()
	LabelSetTextColor("CorksDurabilityGumpSetupLabel", 255, 255, 255)
	LabelSetText("CorksDurabilityGumpSetupLabel", L"Setup")
end